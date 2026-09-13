local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("scratch", function()
	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		child.lua([[ M = require('memo.scratch') ]])
	end)

	after_each(function()
		child.stop()
	end)

	local function cwd_key()
		return (vim.fn.getcwd():gsub("[^%w%-]", "%%"))
	end

	describe("with gpg key without password", function()
		setup(function()
			helpers.setup_test_env()
			helpers.create_gpg_key("mock@example.com")
		end)

		teardown(function()
			helpers.cleanup_test_env()
			helpers.kill_gpg_agent()
		end)

		it("opens a scratch buffer named as a real file in the nvim data dir", function()
			child.lua("M.create()")

			local buffer = child.api.nvim_get_current_buf()
			local name = child.api.nvim_buf_get_name(buffer)

			MiniTest.expect.equality(vim.startswith(name, vim.fn.stdpath("data") .. "/memo-scratch/"), true)
			MiniTest.expect.equality(vim.fn.fnamemodify(name, ":e"), "gpg")
		end)

		it("names the scratch file with the cwd path and a timestamp", function()
			child.lua("M.create()")

			local name = child.api.nvim_buf_get_name(0)

			MiniTest.expect.equality(name:find(cwd_key() .. "-", 1, true) ~= nil, true)
			MiniTest.expect.equality(name:match("T%d%d%d%d%d%d%-%x%x%x%x%x%x%.gpg$") ~= nil, true)
		end)

		it("opens in a new tab when direction is tab", function()
			child.lua("M.create('tab')")

			local buffer = child.api.nvim_get_current_buf()
			local name = child.api.nvim_buf_get_name(buffer)

			MiniTest.expect.equality(child.fn.tabpagenr("$"), 2)
			MiniTest.expect.equality(vim.startswith(name, vim.fn.stdpath("data") .. "/memo-scratch/"), true)
		end)

		it("does not show the [Not edited] flag", function()
			child.lua("M.create()")

			local info = child.cmd_capture("file")
			MiniTest.expect.equality(info:find("[Not edited]", 1, true) == nil, true)
		end)

		it("encrypts scratch content to the nvim data dir on write", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "Secret scratch content", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(child.fn.filereadable(name), 1)
			MiniTest.expect.equality(child.fn.readfile(name)[1], "-----BEGIN PGP MESSAGE-----")

			local result = helpers.decrypt_file(name)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Secret scratch content") ~= nil, true)
		end)

		it("keeps the buffer open after writing", function()
			child.lua("M.create()")
			local buffer = child.api.nvim_get_current_buf()
			local name = child.api.nvim_buf_get_name(buffer)

			child.type_keys("i", "content", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(child.api.nvim_buf_is_valid(buffer), true)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(buffer), name)
		end)

		it("survives switching away", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "sticky", "<Esc>")
			child.cmd("write")

			child.cmd("enew")

			MiniTest.expect.equality(child.fn.bufexists(name), 1)

			child.cmd("buffer " .. vim.fn.fnameescape(name))
			local buffer = child.api.nvim_get_current_buf()
			local lines = child.api.nvim_buf_get_lines(buffer, 0, -1, false)

			MiniTest.expect.equality(lines, { "sticky" })
		end)

		it("re-encrypts updated content on subsequent writes", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "First line", "<Esc>")
			child.cmd("write")

			child.type_keys("A", "\nSecond line", "<Esc>")
			child.cmd("write")

			local result = helpers.decrypt_file(name)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("First line") ~= nil, true)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Second line") ~= nil, true)
		end)

		it("restores scratch buffers from a session", function()
			child.lua("M.create()")

			child.type_keys("i", "Session restored content", "<Esc>")
			child.cmd("write")
			local name = child.api.nvim_buf_get_name(0)

			child.cmd("mksession! /tmp/memo_session.vim")
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.lua([[ M = require('memo.scratch') ]])

			child.cmd("source /tmp/memo_session.vim")

			MiniTest.expect.equality(child.fn.bufexists(name), 1)

			local buffer = child.fn.bufnr(name)
			child.wait_until(function()
				local l = child.api.nvim_buf_get_lines(buffer, 0, -1, false)
				return #l > 0 and l[1] ~= ""
			end)

			local lines = child.api.nvim_buf_get_lines(buffer, 0, -1, false)
			MiniTest.expect.equality(lines, { "Session restored content" })
		end)

		it("opens unique scratch buffers on repeated calls", function()
			child.lua("M.create()")
			local first = child.api.nvim_buf_get_name(0)

			child.lua("M.create()")
			local second = child.api.nvim_buf_get_name(0)

			MiniTest.expect.equality(first == second, false)
		end)

		it("loads content when opening an existing scratch file directly", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "durable content", "<Esc>")
			child.cmd("write")

			child.cmd("enew")
			child.cmd("edit " .. vim.fn.fnameescape(name))

			child.wait_until(function()
				local l = child.api.nvim_buf_get_lines(0, 0, -1, false)
				return #l > 0 and l[1] ~= ""
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(lines, { "durable content" })
		end)

		it("deletes the encrypted file when the buffer is deleted", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "content", "<Esc>")
			child.cmd("write")

			child.cmd("bdelete")

			MiniTest.expect.equality(child.fn.buflisted(name), 0)
			MiniTest.expect.equality(child.fn.filereadable(name), 0)
		end)

		it("deletes the encrypted file when the buffer is wiped", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "content", "<Esc>")
			child.cmd("write")

			child.cmd("bwipeout")

			MiniTest.expect.equality(child.fn.bufexists(name), 0)
			MiniTest.expect.equality(child.fn.filereadable(name), 0)
		end)

		it("saves a scratch buffer as a note in the notes dir", function()
			child.cmd("MemoScratch")
			local scratch_buf = child.api.nvim_get_current_buf()
			local scratch = child.api.nvim_buf_get_name(scratch_buf)

			child.type_keys("i", "Scratch to note", "<Esc>")

			-- stub the interactive prompt with the note name
			child.lua("vim.fn.input = function() return 'ideas' end")
			child.cmd("MemoSaveToNote")

			local note = vim.env.NOTES_DIR .. "/ideas.gpg"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			child.wait_until(function()
				return child.api.nvim_buf_is_valid(scratch_buf) == false
			end)

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Scratch to note") ~= nil, true)
			MiniTest.expect.equality(child.fn.filereadable(scratch), 0)
		end)

		it("respects the typed extension and appends .gpg", function()
			child.cmd("MemoScratch")
			child.type_keys("i", "content", "<Esc>")
			child.lua("vim.fn.input = function() return 'ideas.md' end")
			child.cmd("MemoSaveToNote")

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/ideas.md.gpg"), 1)
		end)

		it("saves a regular note buffer as a note and keeps it open", function()
			local note = vim.env.NOTES_DIR .. "/scratch-check.md"
			child.cmd("edit " .. vim.fn.fnameescape(note))

			child.lua("vim.fn.input = function() return 'cloned' end")
			child.cmd("MemoSaveToNote")

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/cloned.gpg"), 1)
			local buf = child.api.nvim_get_current_buf()
			MiniTest.expect.equality(child.api.nvim_buf_is_valid(buf), true)
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
			helpers.kill_gpg_agent()
		end)

		it("encrypts scratch content when gpg key has password", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "Secret scratch content", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(child.fn.filereadable(name), 1)

			helpers.cache_gpg_password(gpg_key_password)

			local result = helpers.decrypt_file(name)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Secret scratch content") ~= nil, true)
		end)

		it("saves a scratch buffer as a note when gpg key has password", function()
			child.cmd("MemoScratch")
			local scratch_buf = child.api.nvim_get_current_buf()

			child.type_keys("i", "Password note content", "<Esc>")
			helpers.cache_gpg_password(gpg_key_password)

			child.lua("vim.fn.input = function() return 'password-note' end")
			child.cmd("MemoSaveToNote")

			local note = vim.env.NOTES_DIR .. "/password-note.gpg"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)

			child.wait_until(function()
				return child.api.nvim_buf_is_valid(scratch_buf) == false
			end)

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Password note content") ~= nil, true)
		end)
	end)
end)
