local helpers = require("tests.helpers")
local events = require("memo.events")
local child = MiniTest.new_child_neovim()

describe("autocmd", function()
	local TEST_HOME = vim.fn.resolve("/tmp/memo.nvim")
	local NOTES_DIR = TEST_HOME .. "/notes"

	setup(function()
		helpers.setup_test_env(TEST_HOME, NOTES_DIR)
		helpers.create_gpg_key("mock@example.com")
	end)

	teardown(function()
		vim.fn.delete(TEST_HOME, "rf")
		helpers.kill_gpg_agent()
	end)

	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		child.lua(string.format(
			[[
            local config = require('memo.config')
            config.setup({ notes_dir = %q })
            M = require('memo.autocmd')
        ]],
			NOTES_DIR
		))
	end)

	it("disables swap and unsafe files for GPG notes", function()
		local plain = NOTES_DIR .. "/secret.md"
		local encrypted = plain .. ".gpg"

		helpers.write_file(plain, "Hello world!")

		local cmd = {
			"memo",
			"encrypt",
			encrypted,
			plain,
		}
		vim.system(cmd, { text = true }):wait()

		child.lua([[ M.setup() ]])
		child.cmd("edit " .. encrypted)

		local result = child.lua([[
		    return {
		        swap = vim.opt_local.swapfile:get(),
		        undo = vim.opt_local.undofile:get(),
		        shada = vim.opt_local.shadafile:get(),
		    }
		    ]])

		MiniTest.expect.equality(result.swap, false)
		MiniTest.expect.equality(result.undo, false)
		MiniTest.expect.equality(result.shada, { "NONE" })
	end)

	it("triggers decryption when opening a .gpg file", function()
		local plain = NOTES_DIR .. "/secret.md"
		local encrypted = plain .. ".gpg"

		local cmd = {
			"memo",
			"encrypt",
			encrypted,
			plain,
		}
		vim.system(cmd, { stdin = "Hello world!" }):wait()

		child.lua([[ M.setup() ]])
		child.cmd("edit " .. encrypted)
		helpers.wait_for_event(child, events.types.DECRYPT_DONE)

		-- Check if buffer content is decrypted and buffer is renamed
		local result = child.lua([[
            return {
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")
            }
        ]])
		local buf = child.api.nvim_get_current_buf()
		local filetype = child.api.nvim_get_option_value("filetype", { buf = buf })
		MiniTest.expect.equality(filetype, "markdown")

		MiniTest.expect.equality(result.lines, { "Hello world!" })
		MiniTest.expect.equality(result.name, "secret.md.gpg")
	end)

	it("does not trigger decryption when existing .md file is opened; reencrypts it after saving", function()
		local plain = NOTES_DIR .. "/existing.md"
		helpers.write_file(plain, "Hello world")

		child.lua([[ M.setup() ]])
		child.cmd("edit " .. plain)

		-- Check if buffer content
		local result = child.lua([[
            return {
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")
            }
        ]])

		MiniTest.expect.equality(result.lines, { "Hello world" })
		MiniTest.expect.equality(result.name, "existing.md")

		child.cmd("write")

		local result_after_write = child.lua([[
            return {
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")
            }
        ]])

		local cmd = {
			"memo",
			"decrypt",
			plain .. ".gpg",
		}
		local decrypted_result = vim.system(cmd):wait()

		MiniTest.expect.equality(decrypted_result.stdout, "Hello world\n")
		MiniTest.expect.equality(result_after_write.name, "existing.md.gpg")
	end)

	it("automatically encrypts a new .md file saved in notes dir", function()
		local plain = NOTES_DIR .. "/new_note.md"
		local encrypted = plain .. ".gpg"

		vim.system({ "touch", plain }):wait()

		child.lua([[ M.setup() ]])
		child.cmd("edit " .. plain)
		child.api.nvim_buf_set_lines(0, 0, -1, false, { "My new private note" })
		child.cmd("write")

		local result = child.lua(string.format(
			[[
            return {
                new_name = vim.api.nvim_buf_get_name(0),
                plaintext_exists = vim.fn.filereadable(%q) == 1,
                gpg_exists = vim.fn.filereadable(%q) == 1,
            }
        ]],
			plain,
			encrypted
		))

		MiniTest.expect.equality(vim.fn.fnamemodify(result.new_name, ":t"), "new_note.md.gpg")
		MiniTest.expect.equality(result.plaintext_exists, false)
		MiniTest.expect.equality(result.gpg_exists, true)
	end)

	it("automatically encrypts a new .md.gpg file saved in notes dir", function()
		local plain = NOTES_DIR .. "/new_note.md"
		local encrypted = plain .. ".gpg"

		vim.system({ "touch", encrypted }):wait()

		child.lua([[ M.setup() ]])
		child.cmd("edit " .. encrypted)

		helpers.wait_for_event(child, events.types.DECRYPT_DONE)

		child.api.nvim_buf_set_lines(0, 0, -1, false, { "My new private note" })
		child.cmd("write")

		local result = child.lua(string.format(
			[[
            return {
                new_name = vim.api.nvim_buf_get_name(0),
                plaintext_exists = vim.fn.filereadable(%q) == 1,
                gpg_exists = vim.fn.filereadable(%q) == 1,
            }
        ]],
			plain,
			encrypted
		))

		MiniTest.expect.equality(vim.fn.fnamemodify(result.new_name, ":t"), "new_note.md.gpg")
		MiniTest.expect.equality(result.plaintext_exists, false)
		MiniTest.expect.equality(result.gpg_exists, true)
	end)

	it("does not re-encrypt (no-op) if content hasn't changed", function()
		local encrypted = NOTES_DIR .. "/unchanged.md.gpg"

		local cmd = {
			"memo",
			"encrypt",
			encrypted,
		}
		vim.system(cmd, { stdin = "Hello world!", text = true }):wait()
		child.lua([[ M.setup() ]])
		child.cmd("edit " .. encrypted)

		helpers.wait_for_event(child, events.types.BUFFER_READY)
		child.cmd("write")
		helpers.wait_for_event(child, events.types.BUFFER_READY)

		local messages = child.cmd_capture("messages")
		MiniTest.expect.equality(messages, "No changes detected")

		child.cmd("messages clear")
		child.api.nvim_buf_set_lines(0, 0, -1, false, { "My new private note" })
		child.cmd("write")
		helpers.wait_for_event(child, events.types.BUFFER_READY)

		local messages2 = child.cmd_capture("messages")
		MiniTest.expect.equality(messages2, "")

		child.cmd("write")
		helpers.wait_for_event(child, events.types.BUFFER_READY)

		local messages3 = child.cmd_capture("messages")
		MiniTest.expect.equality(messages3, "No changes detected")
	end)

	it("wipes buffer if decryption fails", function()
		local test_file = NOTES_DIR .. "/broken.md.gpg"
		vim.fn.writefile({ "not a gpg file" }, test_file)

		child.lua([[ M.setup() ]])
		child.lua(string.format([[ pcall(vim.cmd, "edit %s") ]], test_file))

		helpers.wait_for_event(child, events.types.DECRYPT_DONE)

		local buf_name = child.api.nvim_buf_get_name(0)
		MiniTest.expect.no_equality(buf_name, test_file)
	end)

	it("does not trigger logic for files outside notes_dir", function()
		local outside_dir = TEST_HOME .. "/outside"
		vim.fn.mkdir(outside_dir, "p")
		local outside_file = outside_dir .. "/normal.md"

		child.cmd("edit " .. outside_file)
		child.api.nvim_buf_set_lines(0, 0, -1, false, { "Normal stuff" })
		child.cmd("write")

		local result = child.lua([[
            return {
                swap = vim.opt_local.swapfile:get(),
                is_gpg = vim.api.nvim_buf_get_name(0):match("%.gpg$") ~= nil
            }
        ]])

		MiniTest.expect.equality(result.swap, true)
		MiniTest.expect.equality(result.is_gpg, false)
	end)
end)
