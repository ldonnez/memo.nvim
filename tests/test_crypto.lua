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
			helpers.kill_gpg_agent()
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
        gpg.exec_with_gpg_auth = function(cmd, opts, on_exit)
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
			-- exec_with_gpg_auth returns nil without ever calling on_exit.
			gpg.exec_with_gpg_auth = function()
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
				return child.cmd_capture("messages") == "Decryption failed: could not authenticate"
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
			gpg.exec_with_gpg_auth = function(_, _, on_exit)
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
end)
