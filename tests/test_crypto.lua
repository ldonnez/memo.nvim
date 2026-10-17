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

	describe("failure reporting", function()
		it("reports clear decryption errors through the public API", function()
			local cases = {
				{ "gpg: decryption failed: Bad session key\n", "GPG: incorrect passphrase or corrupted file" },
				{ "gpg: signing failed: Bad passphrase\n", "GPG: incorrect passphrase" },
				{ "gpg: decryption failed: No secret key\n", "GPG: no secret key available" },
				{ "  some other gpg failure\n", "some other gpg failure" },
				{ "", "GPG: decryption failed" },
			}
			for _, case in ipairs(cases) do
				local result = child.lua(
					[[
					local stderr = ...
					require("memo.gpg").decrypt = function()
						return { wait = function() return { code = 2, stderr = stderr } end }
					end
					local result, err = M.decrypt_to_stdout("note.gpg")
					return { failed = result == nil, err = err }
				]],
					{ case[1] }
				)
				MiniTest.expect.equality(result, { failed = true, err = case[2] })
			end
			MiniTest.expect.equality(child.lua_get("M.decrypt_failure_reason == nil"), true)
		end)

		it("returns startup errors from decrypt_to_stdout", function()
			local result = child.lua([[
				require("memo.gpg").decrypt = function()
					return nil, "GPG: incorrect passphrase"
				end
				local decrypted, err = M.decrypt_to_stdout("note.gpg")
				return { failed = decrypted == nil, err = err }
			]])
			MiniTest.expect.equality(result, { failed = true, err = "GPG: incorrect passphrase" })
		end)

		it("reports timeout as a clear decryption error", function()
			local result = child.lua([[
				require("memo.gpg").decrypt = function()
					return { wait = function() return { code = 124 } end }
				end
				local result, err = M.decrypt_to_stdout("note.gpg")
				return { failed = result == nil, err = err }
			]])
			MiniTest.expect.equality(result, { failed = true, err = "GPG: decryption timed out" })
		end)

		it("reports encryption errors through the public API", function()
			local result = child.lua([[
				require("memo.gpg").encrypt = function()
					return { code = 1, stderr = "  some gpg failure\n" }
				end
				local encrypted, err = M.encrypt_from_stdin("note.gpg", {})
				return { failed = not encrypted, err = err, public_formatter = M.encrypt_failure_reason ~= nil }
			]])
			MiniTest.expect.equality(result, {
				failed = true,
				err = "some gpg failure",
				public_formatter = false,
			})
		end)
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

			local success = child.lua(
				[[
        local test_lines, encrypted = ...
        return M.encrypt_from_stdin(encrypted, test_lines)
    ]],
				{ test_lines, encrypted }
			)

			local exists = child.fn.filereadable(encrypted)
			local lines = child.fn.readfile(encrypted)
			MiniTest.expect.equality(success, true)
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

        M.decrypt_to_buffer(path, bufnr, function(result, _)
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

        M.decrypt_to_buffer(path, bufnr, function(result, _)
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

        M.decrypt_to_buffer(path, bufnr, function(result, _)
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
        gpg.decrypt = function(path, bufnr, opts, on_exit)
          opts.stdout(nil, "Line 1\nLi")
          opts.stdout(nil, "ne 2\nLine 3")
          opts.stdout(nil, "\n\n")

          on_exit({ code = 0 })
          return true -- truthy so decrypt_to_buffer treats it as started
        end

        M.decrypt_to_buffer(path, bufnr, function(result, _)
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

		it("decrypt_to_buffer: safely ignores the result when the buffer was closed mid-decrypt", function()
			child.cmd("messages clear")

			child.lua([[
			local gpg = require("memo.gpg")

			local bufnr = vim.api.nvim_create_buf(true, false)

			-- Simulate the buffer being closed while the async decrypt is in
			-- flight. The `settled` sentinel is scheduled after on_exit's inner
			-- callback, so once it is set the guard has had its chance to run.
			gpg.decrypt = function(_, _, _, on_exit)
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

		it("decrypt_to_buffer: reports cancellation through the completion callback", function()
			child.lua([[
			local gpg = require("memo.gpg")
			gpg.decrypt = function() return nil end

			local bufnr = vim.api.nvim_create_buf(true, false)
			local returned = M.decrypt_to_buffer("/tmp/dummy.gpg", bufnr, function(result, err)
				vim.b.callback_called = true
				vim.b.result_nil = result == nil
				vim.b.err_nil = err == nil
			end)

			vim.b.returned_nil = returned == nil
		]])

			child.wait_until(function()
				return child.b.callback_called == true
			end)

			MiniTest.expect.equality(child.b.returned_nil, true)
			MiniTest.expect.equality(child.b.err_nil, true)
			MiniTest.expect.equality(child.b.result_nil, true)
		end)

		it("decrypt_to_buffer: reports startup errors through the completion callback", function()
			child.lua([[
			local gpg = require("memo.gpg")
			gpg.decrypt = function() return nil, "GPG: incorrect passphrase" end

			local bufnr = vim.api.nvim_create_buf(true, false)
			local returned = M.decrypt_to_buffer("/tmp/dummy.gpg", bufnr, function(result, err)
				vim.b.callback_called = true
				vim.b.result_nil = result == nil
				vim.b.reason = err
			end)

			vim.b.returned_nil = returned == nil
		]])

			child.wait_until(function()
				return child.b.callback_called == true
			end)

			MiniTest.expect.equality(child.b.returned_nil, true)
			MiniTest.expect.equality(child.b.result_nil, true)
			MiniTest.expect.equality(child.b.reason, "GPG: incorrect passphrase")
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

        M.decrypt_to_buffer(path, bufnr, function(result, _)
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

        M.decrypt_to_buffer(path, bufnr, function(result, _)
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
			-- The passphrase is kept in the buffer, so a later write reuses it.
			MiniTest.expect.equality(child.b.memo_symmetric_passphrase, passphrase)
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

		it("decrypt_to_stdout: hands the failure back without notifying", function()
			local path = vim.env.NOTES_DIR .. "/sym.md.gpg"

			helpers.encrypt_symmetric_file(path, "Line 1\n", passphrase)

			child.lua(
				[[
      local path = ...
      require("memo.gpg").prompt_passphrase = function()
        return "wrong"
      end

      local result, err = M.decrypt_to_stdout(path)
      vim.g.result_nil = result == nil
      vim.g.fail_reason = err
    ]],
				{ path }
			)

			MiniTest.expect.equality(child.g.result_nil, true)
			MiniTest.expect.equality(child.g.fail_reason, "GPG: incorrect passphrase or corrupted file")
			-- gpg reports failures to the caller, not to the user.
			MiniTest.expect.equality(child.cmd_capture("messages"), "")
		end)

		it("writes a symmetric note back symmetrically without prompting again", function()
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

      M.decrypt_to_buffer(path, bufnr, function(result, _)
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

			MiniTest.expect.equality(helpers.is_symmetric_file(path), true)

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

      M.decrypt_to_buffer(path, bufnr, function(result, err)
        vim.b.failed = result == nil and err ~= nil
        vim.b.done = true
        return true
      end)
    ]],
				{ path }
			)

			child.wait_until(function()
				return child.b.done == true
			end)

			MiniTest.expect.equality(child.b.failed, true)
		end)

		it("prompts once, returns nothing and stays silent when the prompt is dismissed", function()
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
			-- A dismissed prompt is a cancellation, not a failure to report.
			MiniTest.expect.equality(child.cmd_capture("messages"), "")
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

      -- A dismissed prompt is a cancellation: it returns false without an error.
      local success, err = M.encrypt_from_stdin(path, { "Rewritten" })
      vim.g.dismissed = success == false and err == nil
    ]],
				{ path }
			)

			MiniTest.expect.equality(child.g.dismissed, true)
			MiniTest.expect.equality(helpers.is_symmetric_file(path), true)
			MiniTest.expect.equality(vim.trim(helpers.decrypt_symmetric_file(path, passphrase).stdout or ""), "Line 1")
		end)
	end)
end)
