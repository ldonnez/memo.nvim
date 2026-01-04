local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("capture", function()
	before_each(function()
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
			vim.env.NOTES_DIR
		))
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

		it("captures window contains correct buffer options", function()
			local capture_file = "capture.md"
			local capture_file_path = vim.env.NOTES_DIR .. "/" .. capture_file
			local encrypted = capture_file_path .. ".gpg"

			helpers.encrypt_file(encrypted, "CAPTURE\n")

			child.lua(string.format(
				[[
	       M.register({ capture_file = %q })
	   ]],
				capture_file .. ".gpg"
			))

			local swap = child.bo.swapfile
			local bufhidden = child.bo.bufhidden
			local encoding = child.bo.fileencoding

			MiniTest.expect.equality(swap, false)
			MiniTest.expect.equality(bufhidden, "wipe")
			MiniTest.expect.equality(encoding, "utf-8")
		end)

		it("captures text when capture file exists and keeps new lines in place", function()
			local capture_file = "capture.md"
			local capture_file_path = vim.env.NOTES_DIR .. "/" .. capture_file
			local encrypted = capture_file_path .. ".gpg"

			helpers.encrypt_file(encrypted, "CAPTURE\n")

			child.lua(string.format(
				[[
	       M.register({ capture_file = %q })
	   ]],
				capture_file .. ".gpg"
			))

			child.type_keys("i", "Integration Test Content", "<Esc>")

			local buf = child.api.nvim_get_current_buf()
			local filetype = child.api.nvim_get_option_value("filetype", { buf = buf })
			MiniTest.expect.equality(filetype, "markdown")

			child.cmd("write")

			local exists = child.fn.filereadable(encrypted)
			MiniTest.expect.equality(exists, 1)

			local head = child.fn.readfile(encrypted)[1]
			MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

			local result = helpers.decrypt_file(encrypted)

			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			local lines = vim.split(result.stdout, "\n", { plain = true })
			MiniTest.expect.equality(lines, { "Integration Test Content", "CAPTURE", "" })
		end)

		it("aborts capture when capture window only contains header", function()
			local capture_file = "capture.md"
			local capture_file_path = vim.env.NOTES_DIR .. "/" .. capture_file
			local encrypted = capture_file_path .. ".gpg"

			helpers.encrypt_file(encrypted, "CAPTURE")

			child.lua(string.format(
				[[
	       M.register({ capture_file = %q })
	   ]],
				capture_file .. ".gpg"
			))

			child.cmd("write")
			local messages = child.cmd_capture("messages")
			MiniTest.expect.equality(messages, "Capture aborted: empty content")
		end)

		it("aborts capture when capture window has no content", function()
			local capture_file = "capture.md"

			child.lua(string.format(
				[[
	       M.register({ capture_file = %q })
	   ]],
				capture_file .. ".gpg"
			))

			-- empty the buffer
			local buf = child.api.nvim_get_current_buf()
			child.api.nvim_buf_set_lines(buf, 0, -1, false, {})

			child.cmd("write")
			local messages = child.cmd_capture("messages")
			MiniTest.expect.equality(messages, "Capture aborted: empty content")
		end)

		it("captures text when capture file and target header does not exists", function()
			local capture_file = "capture.md.gpg"
			local capture_file_path = vim.env.NOTES_DIR .. "/capture.md.gpg"

			child.lua(string.format(
				[[
	       M.register({ capture_file = %q, capture_template = { target_header = "inbox" }})
	   ]],
				capture_file
			))

			child.type_keys("i", "Integration Test Content", "<Esc>")

			child.cmd("write")

			local exists = child.fn.filereadable(capture_file_path)
			MiniTest.expect.equality(exists, 1)

			local head = child.fn.readfile(capture_file_path)[1]
			MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

			local result = helpers.decrypt_file(capture_file_path)

			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Integration Test Content") ~= nil, true)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("inbox") ~= nil, true)
		end)

		it("ensures relative directories from capture_file are created", function()
			local capture_file = "journals/capture.md.gpg"
			local capture_file_path = vim.env.NOTES_DIR .. "/journals/capture.md.gpg"

			child.lua(string.format(
				[[
	       M.register({ capture_file = %q, capture_template = { target_header = "inbox" }})
	   ]],
				capture_file
			))

			child.type_keys("i", "Integration Test Content", "<Esc>")

			child.cmd("write")

			local exists = child.fn.filereadable(capture_file_path)
			MiniTest.expect.equality(exists, 1)

			local head = child.fn.readfile(capture_file_path)[1]
			MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

			local result = helpers.decrypt_file(capture_file_path)

			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Integration Test Content") ~= nil, true)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("inbox") ~= nil, true)
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

		it("captures text when capture file does not exists and gpg key has password", function()
			local capture_file = "capture-test-password.md.gpg"
			local capture_file_path = vim.env.NOTES_DIR .. "/capture-test-password.md.gpg"

			child.lua(string.format(
				[[
	      M.register({ capture_file = %q})
	   ]],
				capture_file
			))

			child.type_keys("i", "Integration Test Content 1", "<Esc>")

			child.cmd("write")

			local exists = child.fn.filereadable(capture_file_path)
			MiniTest.expect.equality(exists, 1)

			local head = child.fn.readfile(capture_file_path)[1]
			MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

			helpers.cache_gpg_password(gpg_key_password)

			local result = helpers.decrypt_file(capture_file_path)

			MiniTest.expect.equality(result.code, 0)
			MiniTest.expect.equality((result.stdout or ""):find("Integration Test Content 1") ~= nil, true)
		end)

		it("captures text when capture file exists", function()
			local capture_file = "second-capture-test-with-password.md"
			local capture_file_path = vim.env.NOTES_DIR .. "/" .. capture_file
			local encrypted = capture_file_path .. ".gpg"

			helpers.encrypt_file(encrypted, "CAPTURE")

			child.lua(string.format(
				[[
        local gpg = require("memo.gpg")

        gpg.prompt_passphrase = function()
          return %q
        end

	      M.register({ capture_file = %q })
	    ]],
				gpg_key_password,
				capture_file .. ".gpg"
			))

			child.type_keys("i", "Integration Test Content 2", "<Esc>")

			child.cmd("write")

			local exists = child.fn.filereadable(encrypted)
			MiniTest.expect.equality(exists, 1)

			local head = child.fn.readfile(encrypted)[1]
			MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

			local result = helpers.decrypt_file(encrypted)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Integration Test Content 2") ~= nil, true)
		end)
	end)
end)
