local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

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

		local cmd = {
			"memo",
			"encrypt",
			encrypted,
		}
		vim.system(cmd, { stdin = "Hello World!" }):wait()

		child.lua([[ M.setup() ]])
		child.cmd("edit " .. encrypted)

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		local swap = child.bo.swapfile
		local undo = child.bo.undofile

		MiniTest.expect.equality(swap, false)
		MiniTest.expect.equality(undo, false)
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

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
		local buffer_name = child.api.nvim_buf_get_name(0)

		local buf = child.api.nvim_get_current_buf()
		local filetype = child.api.nvim_get_option_value("filetype", { buf = buf })
		MiniTest.expect.equality(filetype, "markdown")

		MiniTest.expect.equality(lines, { "Hello world!" })
		MiniTest.expect.equality(vim.fn.fnamemodify(buffer_name, ":t"), "secret.md.gpg")
	end)

	it("ensures not writing when decrypting", function()
		local plain = NOTES_DIR .. "/secret.md"
		local encrypted = plain .. ".gpg"

		local cmd = {
			"memo",
			"encrypt",
			encrypted,
		}
		vim.system(cmd, { stdin = "Hello world!" }):wait()

		child.lua([[
      local core = require('memo.core')

      core.decrypt_to_buffer = function(path, bufnr, on_exit)
        return vim.defer_fn(function()
				    vim.bo[bufnr].modifiable = true
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {"Hello world!"})
    				vim.bo[bufnr].modified = false
	    			vim.bo[bufnr].modifiable = false

            on_exit({ code = 0 })
        end, 1000)
      end

      M.setup()
    ]])

		child.cmd("edit " .. encrypted)

		MiniTest.expect.equality(child.b.decrypting, true)
		MiniTest.expect.equality(child.b.hash ~= vim.NIL, false)

		child.cmd("write")

		MiniTest.expect.equality(child.b.decrypting, true)
		MiniTest.expect.equality(child.b.hash ~= vim.NIL, false)

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		MiniTest.expect.equality(child.b.decrypting, false)
		MiniTest.expect.equality(child.b.hash ~= vim.NIL, true)

		local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)

		MiniTest.expect.equality(lines, { "Hello world!" })
	end)

	it("does not trigger decryption when existing .md file is opened; reencrypts it after saving", function()
		local plain = NOTES_DIR .. "/existing.md"
		helpers.write_file(plain, "Hello world")

		child.lua([[ M.setup() ]])
		child.cmd("edit " .. plain)

		local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
		local buffer_name = child.api.nvim_buf_get_name(0)

		MiniTest.expect.equality(lines, { "Hello world" })
		MiniTest.expect.equality(buffer_name, plain)

		child.cmd("write")

		local new_buffer_name_after_write = child.api.nvim_buf_get_name(0)

		local cmd = {
			"memo",
			"decrypt",
			plain .. ".gpg",
		}
		local decrypted_result = vim.system(cmd):wait()

		MiniTest.expect.equality(decrypted_result.stdout, "Hello world\n")
		MiniTest.expect.equality(new_buffer_name_after_write, plain .. ".gpg")
	end)

	it("automatically encrypts a new .md file saved in notes dir", function()
		local plain = NOTES_DIR .. "/new_note.md"
		local encrypted = plain .. ".gpg"

		vim.system({ "touch", plain }):wait()

		child.lua([[ M.setup() ]])
		child.cmd("edit " .. plain)
		child.api.nvim_buf_set_lines(0, 0, -1, false, { "My new private note" })
		child.cmd("write")

		local new_buffer_name = child.api.nvim_buf_get_name(0)
		local plaintext_file_exists = vim.fn.filereadable(plain) == 1
		local gpg_file_exists = vim.fn.filereadable(encrypted) == 1

		MiniTest.expect.equality(new_buffer_name, plain .. ".gpg")
		MiniTest.expect.equality(plaintext_file_exists, false)
		MiniTest.expect.equality(gpg_file_exists, true)
	end)

	it("automatically encrypts a new .md.gpg file saved in notes dir", function()
		local plain = NOTES_DIR .. "/new_note.md"
		local encrypted = plain .. ".gpg"

		vim.system({ "touch", encrypted }):wait()

		child.lua([[ M.setup() ]])
		child.cmd("edit " .. encrypted)

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		child.api.nvim_buf_set_lines(0, 0, -1, false, { "My new private note" })
		child.cmd("write")

		local new_buffer_name = child.api.nvim_buf_get_name(0)
		local plaintext_file_exists = vim.fn.filereadable(plain) == 1
		local gpg_file_exists = vim.fn.filereadable(encrypted) == 1

		MiniTest.expect.equality(new_buffer_name, plain .. ".gpg")
		MiniTest.expect.equality(plaintext_file_exists, false)
		MiniTest.expect.equality(gpg_file_exists, true)
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

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		child.cmd("write")

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		local messages = child.cmd_capture("messages")
		MiniTest.expect.equality(messages, "No changes detected")

		child.cmd("messages clear")
		child.api.nvim_buf_set_lines(0, 0, -1, false, { "My new private note" })
		child.cmd("write")

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		local messages2 = child.cmd_capture("messages")
		MiniTest.expect.equality(messages2, "")

		child.cmd("write")

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		local messages3 = child.cmd_capture("messages")
		MiniTest.expect.equality(messages3, "No changes detected")
	end)

	it("wipes buffer if decryption fails", function()
		local test_file = NOTES_DIR .. "/broken.md.gpg"
		vim.fn.writefile({ "not a gpg file" }, test_file)

		child.lua([[ M.setup() ]])

		local target_bufnr = child.lua(string.format(
			[[
        pcall(vim.cmd, "edit %s")

        return vim.api.nvim_get_current_buf()
    ]],
			test_file
		))

		child.sleep(1000)
		local is_valid = child.api.nvim_buf_is_valid(target_bufnr)
		MiniTest.expect.equality(is_valid, false)
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
