local helpers = require("tests.helpers")
local child = MiniTest.new_child_neovim()

describe("autocmd", function()
	local TEST_HOME = vim.fn.resolve("/tmp/memo.nvim")
	local TEST_GNUPGHOME = TEST_HOME .. "/.gnupg"
	local NOTES_DIR = TEST_HOME .. "/notes"

	before_each(function()
		vim.env.HOME = TEST_HOME
		vim.env.GNUPGHOME = TEST_HOME .. "/.gnupg"

		vim.fn.mkdir(TEST_HOME, "p")
		vim.fn.system({ "chmod", "700", TEST_GNUPGHOME })
		vim.fn.mkdir(NOTES_DIR, "p")

		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		child.lua(string.format(
			[[
            local config = require('memo.config')
            config.notes_dir = %q
            M = require('memo.autocmd')
        ]],
			NOTES_DIR
		))
	end)

	after_each(function()
		vim.fn.delete(TEST_HOME, "rf")
		vim.fn.delete(NOTES_DIR, "rf")
		child.stop()
		helpers.kill_gpg_agent()
	end)

	it("disables swap and unsafe files for GPG notes", function()
		local plain = NOTES_DIR .. "/secret.md"
		local encrypted = plain .. ".gpg"
		helpers.create_gpg_key("mock@example.com")

		helpers.write_file(plain, "Hello world!")

		local cmd = {
			"memo",
			"encrypt",
			plain,
			encrypted,
		}
		vim.system(cmd, { stdin = "test", text = true }):wait()

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
		helpers.create_gpg_key("mock@example.com")

		helpers.write_file(plain, "Hello world!")

		local cmd = {
			"memo",
			"encrypt",
			plain,
			encrypted,
		}
		vim.system(cmd, { stdin = "test", text = true }):wait()

		child.lua([[ M.setup() ]])
		child.cmd("edit " .. encrypted)

		-- Check if buffer content is decrypted and buffer is renamed
		local result = child.lua([[
            return {
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")
            }
        ]])

		MiniTest.expect.equality(result.lines, { "Hello world!" })
		MiniTest.expect.equality(result.name, "secret.md")
	end)

	it("automatically encrypts a new .md file saved in notes dir", function()
		helpers.create_gpg_key("mock@example.com")
		local plain = NOTES_DIR .. "/new_note.md"
		local encrypted = plain .. ".gpg"

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

		MiniTest.expect.equality(vim.fn.fnamemodify(result.new_name, ":t"), "new_note.md")
		MiniTest.expect.equality(result.plaintext_exists, false)
		MiniTest.expect.equality(result.gpg_exists, true)
	end)

	it("wipes buffer if decryption fails", function()
		helpers.create_gpg_key("mock@example.com")
		local test_file = NOTES_DIR .. "/broken.md.gpg"
		vim.fn.writefile({ "not a gpg file" }, test_file)

		child.lua([[ M.setup() ]])
		child.lua(string.format([[ pcall(vim.cmd, "edit %s") ]], test_file))

		local buf_name = child.api.nvim_buf_get_name(0)
		MiniTest.expect.no_equality(buf_name, test_file)
	end)

	it("does not trigger logic for files outside notes_dir", function()
		helpers.create_gpg_key("mock@example.com")
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
