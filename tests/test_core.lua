local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("core", function()
	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		-- Load tested plugin
		child.lua([[ M = require('memo.core') ]])
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

		it("fails encrypting - unsupported extension jpeg", function()
			local encrypted = vim.env.HOME .. "/stdin_test.jpg.gpg"
			local test_lines = { "Hello World", "Line 2" }

			child.lua(
				[[
        local args = {...}
        local lines = args[1]
        local target = args[2]

        M.encrypt_from_stdin(target, lines)
    ]],
				{ test_lines, encrypted }
			)

			local messages = child.cmd_capture("messages")
			MiniTest.expect.equality(messages, "Extension: jpg not supported\n")

			local exists = child.fn.filereadable(encrypted)
			MiniTest.expect.equality(exists, 0)
		end)

		it("decrypt_to_buffer: decrypts content and ensures cursor stays on top of file", function()
			local path = "/tmp/test.md.gpg"

			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3\n\n")

			child.lua(string.format(
				[[
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        M.decrypt_to_buffer(%q, bufnr, function(obj)
          return true
        end)
    ]],
				path
			))

			child.wait_until(function()
				return child.bo.modifiable == false
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

			child.lua(string.format(
				[[
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        M.decrypt_to_buffer(%q, bufnr, function(obj)
          return true
        end)
    ]],
				path
			))

			child.wait_until(function()
				return child.bo.modifiable == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(#lines, 1)
			MiniTest.expect.equality(lines[1], "")
		end)

		it("decrypt_to_buffer: handles file without trailing newline", function()
			local path = "/tmp/no_newline.md.gpg"
			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3")

			child.lua(string.format(
				[[
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        M.decrypt_to_buffer(%q, bufnr, function(obj)
          return true
        end)
    ]],
				path
			))

			child.wait_until(function()
				return child.bo.modifiable == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(lines, { "Line 1", "Line 2", "Line 3" })
		end)

		it("decrypt_to_buffer: correctly assembles fragmented data chunks without adding extra new lines", function()
			local path = "/tmp/chunk_test.md.gpg"
			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3\n\n")

			child.lua(string.format(
				[[
        local gpg = require("memo.gpg")

        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        -- We mock gpg call to return chunks
        gpg.exec_with_gpg_auth = function(cmd, opts, on_exit)
          opts.stdout(nil, "Line 1\nLi")
          opts.stdout(nil, "ne 2\nLine 3")
          opts.stdout(nil, "\n\n")

          on_exit({ code = 0 })
          return
        end

        M.decrypt_to_buffer(%q, bufnr, function(obj)
            _G.finished = true
        end)
    ]],
				path
			))

			child.wait_until(function()
				return child.lua_get("_G.finished") == true
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)

			MiniTest.expect.equality(lines, { "Line 1", "Line 2", "Line 3", "" })
		end)

		it("decrypt_to_stdout: decrypts content", function()
			local path = "/tmp/test.md.gpg"

			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3")

			local result = child.lua(string.format([[ return M.decrypt_to_stdout(%q) ]], path))

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

			child.lua(string.format(
				[[
        local gpg = require("memo.gpg")

        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        gpg.prompt_passphrase = function()
          return %q
        end

        M.decrypt_to_buffer(%q, bufnr, function(obj)
          return true
        end)
    ]],
				gpg_key_password,
				path
			))

			child.wait_until(function()
				return child.bo.modifiable == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)

			MiniTest.expect.equality(lines, { "Line 1", "Line 2", "Line 3" })
		end)

		it("decrypt_to_stdout: decrypts content when gpg key has password", function()
			local path = "/tmp/test.md.gpg"

			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3")

			local result = child.lua(string.format(
				[[
      local gpg = require("memo.gpg")

      gpg.prompt_passphrase = function()
        return %q
      end

      return M.decrypt_to_stdout(%q)
      ]],
				gpg_key_password,
				path
			))

			MiniTest.expect.equality(vim.split(result.stdout, "\n"), { "Line 1", "Line 2", "Line 3" })
		end)
	end)
end)
