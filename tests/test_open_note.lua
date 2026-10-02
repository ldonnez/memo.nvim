local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("open_note", function()
	local gpg_key_password = "test"

	before_each(function()
		child.restart({ "-u", "scripts/minimal_init.lua" })
		-- Load tested plugin
		child.lua([[ M = require('memo.open_note') ]])
	end)

	after_each(function()
		child.stop()
	end)

	describe("with gpg key with password", function()
		setup(function()
			helpers.setup_test_env()
			helpers.create_gpg_key("mock@example.com", gpg_key_password)
			helpers.cache_gpg_password(gpg_key_password)
		end)

		teardown(function()
			helpers.cleanup_test_env()
		end)

		it("opens an existing note", function()
			local note = vim.env.NOTES_DIR .. "/existing.md.gpg"
			helpers.encrypt_file(note, "Decrypted content\n")

			MiniTest.expect.equality(child.lua_get([[ M.open({ path = "existing.md.gpg" }) ]]), true)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), note)

			-- Decryption is async, so the buffer is empty for a moment.
			child.wait_until(function()
				return child.b.decrypting == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(lines, { "Decrypted content" })
		end)

		it("opens a note by its .gpg path", function()
			local note = vim.env.NOTES_DIR .. "/by-extension.gpg"
			helpers.encrypt_file(note, "By extension\n")

			MiniTest.expect.equality(child.lua_get([[ M.open({ path = "by-extension.gpg" }) ]]), true)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), note)
		end)

		it("opens a note by its .asc path", function()
			local note = vim.env.NOTES_DIR .. "/by-asc.asc"
			helpers.encrypt_file(note, "By asc\n")

			MiniTest.expect.equality(child.lua_get([[ M.open({ path = "by-asc.asc" }) ]]), true)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), note)
		end)

		it("finds a note written with the other extension", function()
			local note = vim.env.NOTES_DIR .. "/legacy.md.gpg"
			helpers.encrypt_file(note, "Legacy\n")

			MiniTest.expect.equality(child.lua_get([[ M.open({ path = "legacy.md.gpg" }) ]]), true)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), note)
		end)

		it("opens a note nested in a subdirectory", function()
			local note = vim.env.NOTES_DIR .. "/journals/2026-01-01.md.gpg"
			vim.fn.mkdir(vim.env.NOTES_DIR .. "/journals", "p")
			helpers.encrypt_file(note, "Journal entry\n")

			MiniTest.expect.equality(child.lua_get([[ M.open({ path = "journals/2026-01-01.md.gpg" }) ]]), true)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), note)
		end)

		it("opens the note in a configured split", function()
			helpers.encrypt_file(vim.env.NOTES_DIR .. "/split.md.gpg", "Split note\n")

			local wins = #child.api.nvim_list_wins()

			MiniTest.expect.equality(
				child.lua_get([[ M.open({ path = "split.md.gpg", window = { split = "vsplit" } }) ]]),
				true
			)

			MiniTest.expect.equality(#child.api.nvim_list_wins(), wins + 1)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), vim.env.NOTES_DIR .. "/split.md.gpg")
		end)

		it("keeps the current window when no window config is given", function()
			helpers.encrypt_file(vim.env.NOTES_DIR .. "/current.md.gpg", "Current window\n")

			local wins = #child.api.nvim_list_wins()

			MiniTest.expect.equality(child.lua_get([[ M.open({ path = "current.md.gpg" }) ]]), true)
			MiniTest.expect.equality(#child.api.nvim_list_wins(), wins)
		end)

		it("reuses the buffer when the note is already open", function()
			helpers.encrypt_file(vim.env.NOTES_DIR .. "/reused.md.gpg", "Reused\n")

			child.lua_get([[ M.open({ path = "reused.md.gpg" }) ]])
			local bufnr = child.api.nvim_get_current_buf()

			MiniTest.expect.equality(child.lua_get([[ M.open({ path = "reused.md.gpg" }) ]]), true)
			MiniTest.expect.equality(child.api.nvim_get_current_buf(), bufnr)
		end)

		it("opens the default capture file when no path is given", function()
			helpers.encrypt_file(vim.env.NOTES_DIR .. "/inbox.md.gpg", "Inbox\n")

			child.lua([[
				vim.g.memo_default_capture_file = "inbox.md.gpg"
				require("memo.config").setup()
				M.open()
			]])

			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), vim.env.NOTES_DIR .. "/inbox.md.gpg")
		end)

		it("opens vim.g.memo_default_capture_file when no path is given", function()
			helpers.encrypt_file(vim.env.NOTES_DIR .. "/quick.gpg", "Quick\n")

			child.lua([[
				vim.g.memo_default_capture_file = "quick.gpg"
				require("memo.config").setup()
				M.open()
			]])

			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), vim.env.NOTES_DIR .. "/quick.gpg")
		end)

		it("errors when no path is given and the default is empty", function()
			child.lua([[
				vim.g.memo_default_capture_file = ""
				require("memo.config").setup()
				M.open()
			]])

			MiniTest.expect.equality(
				child.cmd_capture("messages"):find("MemoOpen: a note path is required", 1, true) ~= nil,
				true
			)
		end)

		it("errors when the path is outside the notes dir", function()
			local outside = vim.env.HOME .. "/outside.md"

			MiniTest.expect.equality(child.lua_get([[ M.open({ path = ... }) ]], { outside }), false)
			MiniTest.expect.equality(
				child.cmd_capture("messages"):find("note path must be inside the notes directory", 1, true) ~= nil,
				true
			)
		end)

		it("errors when the note does not exist", function()
			MiniTest.expect.equality(child.lua_get([[ M.open({ path = "missing.md" }) ]]), false)
			MiniTest.expect.equality(child.cmd_capture("messages"):find("note not found", 1, true) ~= nil, true)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), "")
		end)
	end)
end)
