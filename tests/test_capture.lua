local helpers = require("tests.helpers")
local child = MiniTest.new_child_neovim()

describe("capture", function()
	local TEST_HOME = vim.fn.tempname()
	local TEST_GNUPGHOME = TEST_HOME .. "/.gnupg"
	local NOTES_DIR = TEST_HOME .. "/notes"

	before_each(function()
		vim.env.HOME = TEST_HOME
		vim.env.GNUPGHOME = TEST_HOME .. "/.gnupg"

		vim.fn.mkdir(TEST_HOME, "p")
		vim.fn.mkdir(NOTES_DIR, "p")
		vim.fn.system({ "chmod", "700", TEST_GNUPGHOME })

		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		-- Load tested plugin
		child.lua(string.format(
			[[
    config = require("memo.config")
    core = require("memo.core")

    config.setup({ notes_dir = %q })
    M = require('memo.capture')
    ]],
			NOTES_DIR
		))
	end)

	after_each(function()
		vim.fn.delete(TEST_HOME, "rf")
		child.stop()
		helpers.kill_gpg_agent()
	end)

	it("captures text when capture file exists", function()
		helpers.create_gpg_key("mock@example.com")

		local capture_file = "capture.md"
		local capture_file_path = NOTES_DIR .. "/" .. capture_file
		local encrypted = capture_file_path .. ".gpg"

		helpers.write_file(capture_file_path, "CAPTURE")

		child.lua(string.format([[ return core.encrypt_file(%q, %q) ]], capture_file, encrypted))
		child.lua(string.format(
			[[
	       M.register({ capture_file = %q })
	   ]],
			capture_file .. ".gpg"
		))

		child.type_keys("i", "Integration Test Content", "<Esc>")

		local buf = child.api.nvim_get_current_buf()

		child.lua(
			[[
        local buf = ...
        vim.api.nvim_exec_autocmds("BufWriteCmd", { buffer = buf })
    ]],
			{ buf }
		)

		local exists = child.fn.filereadable(encrypted)
		MiniTest.expect.equality(exists, 1)

		local head = child.fn.readfile(encrypted)[1]
		MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

		local result = child.lua(string.format([[ return core.decrypt_file(%q) ]], encrypted))
		MiniTest.expect.equality(result.code, 0)
		MiniTest.expect.equality(result.stdout:find("Integration Test Content") ~= nil, true)
	end)

	it("captures text when capture file does not exists", function()
		helpers.create_gpg_key("mock@example.com")

		local capture_file = "capture.md.gpg"
		local capture_file_path = NOTES_DIR .. "/capture.md.gpg"

		child.lua(string.format(
			[[
	       M.register({ capture_file = %q})
	   ]],
			capture_file
		))

		child.type_keys("i", "Integration Test Content", "<Esc>")

		local buf = child.api.nvim_get_current_buf()

		child.lua(
			[[
        local buf = ...
        vim.api.nvim_exec_autocmds("BufWriteCmd", { buffer = buf })
    ]],
			{ buf }
		)

		local exists = child.fn.filereadable(capture_file_path)
		MiniTest.expect.equality(exists, 1)

		local head = child.fn.readfile(capture_file_path)[1]
		MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

		local result = child.lua(string.format([[ return core.decrypt_file(%q) ]], capture_file_path))
		MiniTest.expect.equality(result.code, 0)
		MiniTest.expect.equality(result.stdout:find("Integration Test Content") ~= nil, true)
	end)

	it("captures text when capture file does not exists and gpg key has password", function()
		local password = "test"
		helpers.create_gpg_key("mock-password@example.com", password)

		local capture_file = "capture-test-password.md.gpg"
		local capture_file_path = NOTES_DIR .. "/capture-test-password.md.gpg"

		child.lua(string.format(
			[[
        local utils = require("memo.utils")

        utils.prompt_passphrase = function()
          return %q
        end

	      M.register({ capture_file = %q})
	   ]],
			password,
			capture_file
		))

		child.type_keys("i", "Integration Test Content", "<Esc>")

		local buf = child.api.nvim_get_current_buf()

		child.lua(
			[[
        local buf = ...
        return vim.api.nvim_exec_autocmds("BufWriteCmd", { buffer = buf })
    ]],
			{ buf }
		)

		local exists = child.fn.filereadable(capture_file_path)
		MiniTest.expect.equality(exists, 1)

		local head = child.fn.readfile(capture_file_path)[1]
		MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

		local cmd = {
			"memo",
			"decrypt",
			capture_file_path,
		}
		local result = vim.system(cmd):wait()

		MiniTest.expect.equality(result.code, 0)
		MiniTest.expect.equality((result.stdout or ""):find("Integration Test Content") ~= nil, true)
	end)
end)
