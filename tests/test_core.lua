local helpers = require("tests.helpers")
local events = require("memo.events")
local child = MiniTest.new_child_neovim()

describe("core", function()
	local TEST_HOME = vim.fn.tempname()
	local NOTES_DIR = TEST_HOME .. "/notes"

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
			helpers.setup_test_env(TEST_HOME, NOTES_DIR)
			helpers.create_gpg_key("mock@example.com")
		end)

		teardown(function()
			vim.fn.delete(TEST_HOME, "rf")
			helpers.kill_gpg_agent()
		end)

		it("correctly encrypts from stdin", function()
			local encrypted = TEST_HOME .. "/stdin_test.md.gpg"
			local test_lines = { "Hello World", "Line 2" }

			child.lua(
				[[
        local test_lines, encrypted = ...
        M.encrypt_from_stdin(encrypted, test_lines, function()
          return true
        end)
    ]],
				{ test_lines, encrypted }
			)

			helpers.wait_for_event(child, events.types.ENCRYPT_DONE)

			local exists = child.fn.filereadable(encrypted)
			local lines = child.fn.readfile(encrypted)
			MiniTest.expect.equality(exists, 1)
			MiniTest.expect.equality(lines[1], "-----BEGIN PGP MESSAGE-----")
		end)

		it("fails encrypting - unsupported extension jpeg", function()
			local encrypted = TEST_HOME .. "/stdin_test.jpg.gpg"
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

			helpers.wait_for_event(child, events.types.ENCRYPT_DONE)

			local messages = child.cmd_capture("messages")
			MiniTest.expect.equality(messages, "Memo failed: Extension: jpg not supported\n")

			local exists = child.fn.filereadable(encrypted)
			MiniTest.expect.equality(exists, 0)
		end)

		it("decrypt_to_buffer: decrypts content and ensures cursor stays on top of file", function()
			local path = "/tmp/test.md.gpg"

			vim.system({ "memo", "encrypt", path }, { stdin = "Line 1\nLine 2\nLine 3\n" }):wait()

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

			helpers.wait_for_event(child, events.types.DECRYPT_DONE)

			local result = child.lua([[
        return {
            lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
            cursor = vim.api.nvim_win_get_cursor(0)
        }
    ]])

			MiniTest.expect.equality(#result.lines, 3)
			MiniTest.expect.equality(result.lines, { "Line 1", "Line 2", "Line 3" })
			MiniTest.expect.equality(result.cursor, { 1, 0 })
		end)
	end)

	describe("with gpg key with password", function()
		local gpg_key_password = "test"

		setup(function()
			helpers.setup_test_env(TEST_HOME, NOTES_DIR)
			helpers.create_gpg_key("mock-password@example.com", gpg_key_password)
		end)

		teardown(function()
			vim.fn.delete(TEST_HOME, "rf")
		end)

		after_each(function()
			helpers.kill_gpg_agent()
		end)

		it("decrypt_to_buffer: decrypts content when gpg key has password", function()
			local path = "/tmp/test-password.md.gpg"

			vim.system({ "memo", "encrypt", path }, { stdin = "Line 1\nLine 2\nLine 3" }):wait()

			child.lua(string.format(
				[[
        local utils = require("memo.utils")

        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        utils.prompt_passphrase = function()
          return %q
        end

        M.decrypt_to_buffer(%q, bufnr, function(obj)
          return true
        end)
    ]],
				gpg_key_password,
				path
			))

			helpers.wait_for_event(child, events.types.DECRYPT_DONE)

			local result = child.lua([[
        return {
            lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
            cursor = vim.api.nvim_win_get_cursor(0)
        }
    ]])

			MiniTest.expect.equality(result.lines, { "Line 1", "Line 2", "Line 3" })
		end)
	end)
end)
