local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("crypto", function()
	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		-- Load tested plugin
		child.lua([[ M = require('memo.crypto') ]])
	end)

	after_each(function()
		child.stop()
	end)

	describe("with gpg key without password", function()
		setup(function()
			helpers.setup_test_env()
			helpers.create_gpg_key("mock@example.com")
		end)

		teardown(function()
			helpers.cleanup_test_env()
		end)

		it("correctly encrypts from stdin", function()
			local encrypted = vim.env.HOME .. "/stdin_test.md.gpg"
			local test_lines = { "Hello World", "Line 2" }

			child.lua(
				[[
        local test_lines, encrypted = ...
        M.encrypt_from_stdin(encrypted, test_lines)
    ]],
				{ test_lines, encrypted }
			)

			local exists = child.fn.filereadable(encrypted)
			local lines = child.fn.readfile(encrypted)
			MiniTest.expect.equality(exists, 1)
			MiniTest.expect.equality(lines[1], "-----BEGIN PGP MESSAGE-----")
		end)

		it("decrypt_to_buffer: decrypts content and ensures cursor stays on top of file", function()
			local path = "/tmp/test.md.gpg"

			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3\n\n")

			child.lua(
				[[
        local path = ...
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        M.decrypt_to_buffer(path, bufnr, function(obj)
          vim.b.decrypting = false
          return true
        end)
    ]],
				{ path }
			)

			child.wait_until(function()
				return child.b.decrypting == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			local cursor = child.api.nvim_win_get_cursor(0)

			MiniTest.expect.equality(#lines, 4)
			MiniTest.expect.equality(lines, { "Line 1", "Line 2", "Line 3", "" })
			MiniTest.expect.equality(cursor, { 1, 0 })
		end)

		it("decrypt_to_buffer: handles empty file", function()
			local path = "/tmp/empty.md.gpg"
			helpers.encrypt_file(path, "")

			child.lua(
				[[
        local path = ...
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        M.decrypt_to_buffer(path, bufnr, function(obj)
          vim.b.decrypting = false
          return true
        end)
    ]],
				{ path }
			)

			child.wait_until(function()
				return child.b.decrypting == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(#lines, 1)
			MiniTest.expect.equality(lines[1], "")
		end)

		it("decrypt_to_buffer: handles file without trailing newline", function()
			local path = "/tmp/no_newline.md.gpg"
			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3")

			child.lua(
				[[
        local path = ...
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        M.decrypt_to_buffer(path, bufnr, function(obj)
          vim.b.decrypting = false
          return true
        end)
    ]],
				{ path }
			)

			child.wait_until(function()
				return child.b.decrypting == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(lines, { "Line 1", "Line 2", "Line 3" })
		end)

		it("decrypt_to_buffer: correctly assembles fragmented data chunks without adding extra new lines", function()
			local path = "/tmp/chunk_test.md.gpg"
			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3\n\n")

			child.lua(
				[[
        local path = ...
        local gpg = require("memo.gpg")

        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        -- We mock gpg call to return chunks
        gpg.run_with_key = function(cmd, opts, on_exit)
          opts.stdout(nil, "Line 1\nLi")
          opts.stdout(nil, "ne 2\nLine 3")
          opts.stdout(nil, "\n\n")

          on_exit({ code = 0 })
          return true -- truthy so decrypt_to_buffer treats it as started
        end

        M.decrypt_to_buffer(path, bufnr, function(obj)
          vim.b.decrypting = false
          return true
        end)
    ]],
				{ path }
			)

			child.wait_until(function()
				return child.b.decrypting == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)

			MiniTest.expect.equality(lines, { "Line 1", "Line 2", "Line 3", "" })
		end)

		it("decrypt_to_buffer: wipes the buffer and reports when the passphrase cannot be obtained", function()
			local path = "/tmp/auth_aborted.md.gpg"
			helpers.encrypt_file(path, "Line 1\nLine 2")

			local bufnr = child.lua(
				[[
			local path = ...
			local gpg = require("memo.gpg")

			-- Simulate an auth failure (e.g. the user aborted the prompt):
			-- run_with_key returns nil without ever calling on_exit.
			gpg.run_with_key = function()
				return nil
			end

			local bufnr = vim.api.nvim_create_buf(true, false)
			vim.api.nvim_win_set_buf(0, bufnr)

			vim.g.auth_cb_called = false
			M.decrypt_to_buffer(path, bufnr, function()
				vim.g.auth_cb_called = true
			end)

			return bufnr
			]],
				{ path }
			)

			child.wait_until(function()
				return not child.api.nvim_buf_is_valid(bufnr)
			end)

			MiniTest.expect.equality(child.api.nvim_buf_is_valid(bufnr), false)
			MiniTest.expect.equality(child.g.auth_cb_called, false)

			child.wait_until(function()
				return child.cmd_capture("messages") == "Decryption failed: the passphrase was not given"
			end)
		end)

		it("decrypt_to_buffer: safely ignores the result when the buffer was closed mid-decrypt", function()
			child.cmd("messages clear")

			child.lua([[
			local gpg = require("memo.gpg")

			local bufnr = vim.api.nvim_create_buf(true, false)

			-- Simulate the buffer being closed while the async decrypt is in
			-- flight. The `settled` sentinel is scheduled after on_exit's inner
			-- callback, so once it is set the guard has had its chance to run.
			gpg.run_with_key = function(_, _, on_exit)
				vim.g.exit_cb_called = false
				vim.g.settled = false
				vim.api.nvim_buf_delete(bufnr, { force = true })
				on_exit({ code = 0 })
				vim.schedule(function()
					vim.g.settled = true
				end)
				return true
			end

			M.decrypt_to_buffer("/tmp/dummy.gpg", bufnr, function()
				vim.g.exit_cb_called = true
			end)
		]])

			child.wait_until(function()
				return child.g.settled == true
			end)

			MiniTest.expect.equality(child.g.exit_cb_called, false)
			MiniTest.expect.equality(child.cmd_capture("messages"), "")
		end)

		it("decrypt_to_stdout: decrypts content", function()
			local path = "/tmp/test.md.gpg"

			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3")

			local result = child.lua_get("M.decrypt_to_stdout(...)", { path })

			MiniTest.expect.equality(vim.split(result.stdout, "\n"), { "Line 1", "Line 2", "Line 3" })
		end)
	end)

	describe("with gpg key with password", function()
		local gpg_key_password = "test"

		setup(function()
			helpers.setup_test_env()
			helpers.create_gpg_key("mock-password@example.com", gpg_key_password)
		end)

		teardown(function()
			helpers.cleanup_test_env()
		end)

		after_each(function()
			helpers.kill_gpg_agent()
		end)

		it("decrypt_to_buffer: decrypts content when gpg key has password", function()
			local path = "/tmp/test-password.md.gpg"

			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3")

			child.lua(
				[[
        local password, path = ...
        local gpg = require("memo.gpg")

        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        gpg.prompt_passphrase = function()
          return password
        end

        M.decrypt_to_buffer(path, bufnr, function(obj)
          vim.b.decrypting = false
          return true
        end)
    ]],
				{ gpg_key_password, path }
			)

			child.wait_until(function()
				return child.b.decrypting == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)

			MiniTest.expect.equality(lines, { "Line 1", "Line 2", "Line 3" })
		end)

		it("decrypt_to_stdout: decrypts content when gpg key has password", function()
			local path = "/tmp/test.md.gpg"

			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3")

			local result = child.lua(
				[[
      local password, path = ...
      local gpg = require("memo.gpg")

      gpg.prompt_passphrase = function()
        return password
      end

      return M.decrypt_to_stdout(path)
      ]],
				{ gpg_key_password, path }
			)

			MiniTest.expect.equality(vim.split(result.stdout, "\n"), { "Line 1", "Line 2", "Line 3" })
		end)
	end)
	describe("with a symmetric passphrase", function()
		local passphrase = "sym-pass"

		setup(function()
			helpers.setup_test_env()
		end)

		teardown(function()
			helpers.cleanup_test_env()
		end)

		it("decrypts a symmetric file into a buffer and keeps the passphrase", function()
			local path = vim.env.NOTES_DIR .. "/sym.md.gpg"

			helpers.encrypt_symmetric_file(path, "Line 1\nLine 2\n", passphrase)

			child.lua(
				[[
      local password, path = ...
      local gpg = require("memo.gpg")

      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(0, bufnr)

      gpg.prompt_passphrase = function()
        return password
      end

      M.decrypt_to_buffer(path, bufnr, function(obj)
        vim.b.decrypting = false
        return true
      end)
    ]],
				{ passphrase, path }
			)

			child.wait_until(function()
				return child.b.decrypting == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)

			MiniTest.expect.equality(lines, { "Line 1", "Line 2" })
			MiniTest.expect.equality(child.b.memo_symmetric_passphrase, passphrase)
		end)

		it("asks for the passphrase by file name", function()
			local path = vim.env.NOTES_DIR .. "/sym.md.gpg"

			helpers.encrypt_symmetric_file(path, "Line 1\n", passphrase)

			local label = child.lua(
				[[
      local path = ...
      require("memo.gpg").prompt_passphrase = function(l)
        return l
      end

      return require("memo.gpg").get_symmetric_passphrase(path)
    ]],
				{ path }
			)

			MiniTest.expect.equality(label, "note sym.md.gpg (symmetric)")
		end)

		it("decrypts a symmetric file to stdout", function()
			local path = vim.env.NOTES_DIR .. "/sym.md.gpg"

			helpers.encrypt_symmetric_file(path, "Line 1\nLine 2", passphrase)

			local result = child.lua(
				[[
      local password, path = ...
      require("memo.gpg").prompt_passphrase = function()
        return password
      end

      return M.decrypt_to_stdout(path)
    ]],
				{ passphrase, path }
			)

			MiniTest.expect.equality(vim.split(result.stdout, "\n"), { "Line 1", "Line 2" })
		end)

		it("writes a symmetric note back symmetrically without asking again", function()
			local path = vim.env.NOTES_DIR .. "/sym.md.gpg"

			helpers.encrypt_symmetric_file(path, "Line 1\n", passphrase)

			child.lua(
				[[
      local password, path = ...
      local gpg = require("memo.gpg")
      local prompts = 0

      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(0, bufnr)

      gpg.prompt_passphrase = function()
        prompts = prompts + 1
        return password
      end

      M.decrypt_to_buffer(path, bufnr, function(obj)
        vim.b.decrypting = false
        M.encrypt_from_stdin(path, { "Rewritten" }, bufnr)
        vim.b.prompts = prompts
        vim.b.done = true
        return true
      end)
    ]],
				{ passphrase, path }
			)

			child.wait_until(function()
				return child.b.done == true
			end)

			MiniTest.expect.equality(child.b.prompts, 1)

			local is_symmetric = child.lua_get([[ require("memo.gpg").is_symmetric(...) ]], { path })
			MiniTest.expect.equality(is_symmetric, true)

			local decrypted = helpers.decrypt_symmetric_file(path, passphrase)
			MiniTest.expect.equality(vim.trim(decrypted.stdout or ""), "Rewritten")
		end)

		it("fails when the passphrase is wrong", function()
			local path = vim.env.NOTES_DIR .. "/sym.md.gpg"

			helpers.encrypt_symmetric_file(path, "Line 1\n", passphrase)

			child.lua(
				[[
      local path = ...
      require("memo.gpg").prompt_passphrase = function()
        return "wrong"
      end

      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(0, bufnr)

      M.decrypt_to_buffer(path, bufnr, function(obj)
        vim.b.code = obj.code
        vim.b.done = true
        return true
      end)
    ]],
				{ path }
			)

			child.wait_until(function()
				return child.b.done == true
			end)

			MiniTest.expect.equality(child.b.code ~= 0, true)
		end)

		it("wipes the buffer when the prompt is dismissed", function()
			local path = vim.env.NOTES_DIR .. "/sym.md.gpg"

			helpers.encrypt_symmetric_file(path, "Line 1\n", passphrase)

			child.lua(
				[[
      local path = ...
      local prompts = 0
      require("memo.gpg").prompt_passphrase = function()
        prompts = prompts + 1
        return ""
      end

      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_win_set_buf(0, bufnr)

      -- Globals, because the buffer holding them is the one that gets wiped.
      vim.g.sym_bufnr = bufnr
      vim.g.sym_called_back = false

      M.decrypt_to_buffer(path, bufnr, function(obj)
        vim.g.sym_called_back = true
        return true
      end)
    ]],
				{ path }
			)

			child.wait_until(function()
				return child.cmd_capture("messages"):find("passphrase was not given", 1, true) ~= nil
			end)

			MiniTest.expect.equality(child.g.sym_called_back, false)
			MiniTest.expect.equality(child.api.nvim_buf_is_valid(child.g.sym_bufnr), false)
		end)

		it("asks once and returns nothing when the prompt is dismissed", function()
			local path = vim.env.NOTES_DIR .. "/sym.md.gpg"

			helpers.encrypt_symmetric_file(path, "Line 1\n", passphrase)

			child.lua(
				[[
      local path = ...
      require("memo.gpg").prompt_passphrase = function()
        vim.g.sym_prompts = (vim.g.sym_prompts or 0) + 1
        return ""
      end

      vim.g.sym_prompts = 0
      vim.g.sym_stdout = "unset"

      local result = M.decrypt_to_stdout(path)
      vim.g.sym_stdout = result == nil and "nil" or "object"
    ]],
				{ path }
			)

			child.wait_until(function()
				return child.g.sym_stdout ~= "unset"
			end)

			MiniTest.expect.equality(child.g.sym_stdout, "nil")
			MiniTest.expect.equality(child.g.sym_prompts, 1)
		end)

		it("hands the passphrase to memo through the environment", function()
			local path = vim.env.NOTES_DIR .. "/sym.md.gpg"

			helpers.encrypt_symmetric_file(path, "Line 1\n", passphrase)

			child.lua(
				[[
      local path, passphrase = ...
      require("memo.gpg").prompt_passphrase = function()
        return passphrase
      end

      local seen = {}
      local system = vim.system
      vim.system = function(cmd, opts, on_exit)
        table.insert(seen, { cmd = cmd, env = opts and opts.env })
        return system(cmd, opts, on_exit)
      end

      local result = M.encrypt_from_stdin(path, { "Rewritten" })

      -- The first call is gpg detecting the symmetric note, so pick the one that
      -- asks for --symmetric.
      local encrypt_call
      for _, call in ipairs(seen) do
        if vim.tbl_contains(call.cmd, "--symmetric") then
          encrypt_call = call
        end
      end

      vim.g.cmd = encrypt_call and encrypt_call.cmd or {}
      vim.g.leaked = encrypt_call and vim.inspect(encrypt_call.env) or ""
      vim.g.code = result.code
    ]],
				{ path, passphrase }
			)

			MiniTest.expect.equality(child.g.code, 0)
			MiniTest.expect.equality(child.g.cmd[1], "memo")
			MiniTest.expect.equality(child.g.cmd[2], "encrypt")
			MiniTest.expect.equality(child.g.cmd[3], "--symmetric")
			MiniTest.expect.equality(child.g.cmd[4], path)
			MiniTest.expect.equality(child.g.cmd[5], "--passphrase-env")
			MiniTest.expect.equality(child.g.cmd[6], "MEMO_NOTE_PASSPHRASE")
			-- The passphrase must not appear in the arguments themselves.
			MiniTest.expect.equality(vim.tbl_contains(child.g.cmd, passphrase), false)
			MiniTest.expect.equality(child.g.leaked:find("MEMO_NOTE_PASSPHRASE", 1, true) ~= nil, true)
		end)

		it("does not re-encrypt a symmetric note when the passphrase is dismissed", function()
			local path = vim.env.NOTES_DIR .. "/sym.md.gpg"

			helpers.encrypt_symmetric_file(path, "Line 1\n", passphrase)

			child.lua(
				[[
      local path = ...
      require("memo.gpg").prompt_passphrase = function()
        return ""
      end

      vim.g.write_code = M.encrypt_from_stdin(path, { "Rewritten" }).code
    ]],
				{ path }
			)

			MiniTest.expect.equality(child.g.write_code ~= 0, true)
			MiniTest.expect.equality(helpers.is_symmetric_file(path), true)
			MiniTest.expect.equality(vim.trim(helpers.decrypt_symmetric_file(path, passphrase).stdout or ""), "Line 1")
		end)
	end)
end)
