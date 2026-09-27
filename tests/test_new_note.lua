local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("new_note", function()
	local gpg_key_password = "test"

	setup(function()
		helpers.setup_test_env()
		helpers.create_gpg_key("mock-password@example.com", gpg_key_password)
		helpers.cache_gpg_password(gpg_key_password)
	end)

	teardown(function()
		helpers.cleanup_test_env()
		helpers.kill_gpg_agent()
	end)

	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		child.lua(
			[[
    vim.g.memo_notes_dir = ...

    new_note = require("memo.new_note")
  ]],
			{ vim.env.NOTES_DIR }
		)
	end)

	after_each(function()
		child.stop()
	end)

	describe("default_path", function()
		it("defaults to today's date inside the notes dir", function()
			MiniTest.expect.equality(
				child.lua_get([[ new_note.default_path() ]]),
				vim.env.NOTES_DIR .. "/" .. os.date("%Y-%m-%d.md") .. ".gpg"
			)
		end)
	end)

	describe("create", function()
		it("creates an encrypted note and opens it", function()
			local created = child.lua_get([[ new_note.create({ path = "inbox.md" }) ]])

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/inbox.md.gpg"), 1)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/inbox.md"), 0)

			local decrypted = helpers.decrypt_file(vim.env.NOTES_DIR .. "/inbox.md.gpg")
			MiniTest.expect.equality(decrypted.code, 0)
		end)

		it("falls back to the default path when none is given", function()
			local created = child.lua_get([[ new_note.create() ]])
			local default_path = vim.env.NOTES_DIR .. "/" .. os.date("%Y-%m-%d.md") .. ".gpg"

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(child.fn.filereadable(default_path), 1)
		end)

		it("creates notes in nested directories", function()
			local created = child.lua_get([[ new_note.create({ path = "journals/2026-01-01.md" }) ]])

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/journals/2026-01-01.md.gpg"), 1)
		end)

		it("fills the note with the template", function()
			child.lua_get([[ new_note.create({ path = "templated.md", template = "# %Y\n\n|" }) ]])

			MiniTest.expect.equality(helpers.decrypt_file(vim.env.NOTES_DIR .. "/templated.md.gpg").code, 0)

			child.lua([[ vim.cmd("silent edit " .. vim.env.NOTES_DIR .. "/templated.md.gpg") ]])
			child.wait_until(function()
				return child.lua_get("vim.b.decrypting") == false
			end, 10000)

			MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "# " .. os.date("%Y"), "", "" })
		end)

		it("places the cursor at the template marker", function()
			child.lua_get([[ new_note.create({ path = "cursor.md", template = "# title\nbody| here\n" }) ]])

			local cursor = child.api.nvim_win_get_cursor(0)
			MiniTest.expect.equality(cursor[1], 2)
			MiniTest.expect.equality(cursor[2], 4)
		end)

		it("uses the configured template", function()
			child.lua([[ vim.g.memo_new_note_template = "from config| here" ]])
			child.lua([[ require("memo.config").setup() ]])
			child.lua_get([[ new_note.create({ path = "configured.md" }) ]])

			local cursor = child.api.nvim_win_get_cursor(0)
			MiniTest.expect.equality(cursor[1], 1)
			MiniTest.expect.equality(cursor[2], 11)
		end)

		it("asks before overwriting an existing note and keeps it when declined", function()
			local existing = vim.env.NOTES_DIR .. "/existing.md.gpg"
			helpers.encrypt_file(existing, "old content\n")

			child.lua("vim.fn.confirm = function() return 2 end")

			MiniTest.expect.equality(child.lua_get([[ new_note.create({ path = "existing.md" }) ]]), false)
			MiniTest.expect.equality(child.cmd_capture("messages"), "MemoNewNote: aborted")

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout:find("old content") ~= nil, true)
		end)

		it("overwrites an existing note when the user confirms", function()
			local existing = vim.env.NOTES_DIR .. "/existing.md.gpg"
			helpers.encrypt_file(existing, "old content\n")

			child.lua("vim.fn.confirm = function() return 1 end")
			child.lua([[ vim.g.memo_new_note_template = "fresh| content" ]])
			child.lua([[ require("memo.config").setup() ]])

			MiniTest.expect.equality(child.lua_get([[ new_note.create({ path = "existing.md" }) ]]), true)

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout, "fresh content\n")
		end)

		it("refuses a path outside the notes dir", function()
			MiniTest.expect.equality(child.lua_get([[ new_note.create({ path = "../escape.md" }) ]]), false)
		end)
	end)

	describe("range selection", function()
		local function open_source()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.api.nvim_buf_set_lines(0, 0, -1, false, {
				"alpha beta gamma",
				"delta epsilon",
			})

			return source
		end

		it("seeds the note with a characterwise visual selection via the user command", function()
			open_source()

			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })

			child.lua("vim.fn.input = function() return 'visual' end")
			child.type_keys(":", "MemoNewNote", "<CR>")

			local note = vim.env.NOTES_DIR .. "/visual.gpg"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "beta\n")
		end)

		it("seeds the note with a linewise range via the user command", function()
			open_source()

			child.cmd("2,2normal! V")
			child.lua("vim.fn.input = function() return 'linewise' end")
			child.type_keys(":", "MemoNewNote", "<CR>")

			local note = vim.env.NOTES_DIR .. "/linewise.gpg"
			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "delta epsilon\n")
		end)

		it("inserts a range selection at the template cursor position", function()
			open_source()

			child.lua([[ vim.g.memo_new_note_template = "## Notes\n- | (kept)" ]])
			child.lua([[ require("memo.config").setup() ]])
			child.lua("vim.fn.input = function() return 'ranged' end")

			child.lua_get([[ new_note.create({ path = "ranged.md", range = 2, line1 = 2, line2 = 2 }) ]])

			local result = helpers.decrypt_file(vim.env.NOTES_DIR .. "/ranged.md.gpg")
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "## Notes\n- delta epsilon (kept)\n")

			local cursor = child.api.nvim_win_get_cursor(0)
			MiniTest.expect.equality(cursor[1], 2)
			MiniTest.expect.equality(cursor[2], 15)
		end)

		it("uses the selection as the whole note when the template has no marker", function()
			open_source()

			child.lua([[ vim.g.memo_new_note_template = "## Notes" ]])
			child.lua([[ require("memo.config").setup() ]])
			child.lua("vim.fn.input = function() return 'unmarked' end")

			child.lua_get([[ new_note.create({ path = "unmarked.md", range = 2, line1 = 2, line2 = 2 }) ]])

			local result = helpers.decrypt_file(vim.env.NOTES_DIR .. "/unmarked.md.gpg")
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "delta epsilon\n")
		end)

		it("inserts a visual selection at the template cursor position", function()
			open_source()

			child.lua([[ vim.g.memo_new_note_template = "## Notes\n- | (kept)" ]])
			child.lua([[ require("memo.config").setup() ]])
			child.lua("vim.fn.input = function() return 'fromvisual' end")

			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })
			child.type_keys(":", "MemoNewNote", "<CR>")

			local result = helpers.decrypt_file(vim.env.NOTES_DIR .. "/fromvisual.gpg")
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "## Notes\n- beta (kept)\n")
		end)

		it("prefers an explicit template over the configured one for a selection", function()
			open_source()

			child.lua([[ vim.g.memo_new_note_template = "config|" ]])
			child.lua([[ require("memo.config").setup() ]])
			child.lua("vim.fn.input = function() return 'explicit' end")

			child.lua_get(
				[[ new_note.create({ path = "explicit.md", range = 2, line1 = 2, line2 = 2, template = "call | arg" }) ]]
			)

			local result = helpers.decrypt_file(vim.env.NOTES_DIR .. "/explicit.md.gpg")
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "call delta epsilon arg\n")
		end)

		it("places the cursor at the end of the selection", function()
			open_source()

			child.cmd("2,2normal! V")
			child.lua("vim.fn.input = function() return 'cursor' end")
			child.type_keys(":", "MemoNewNote", "<CR>")

			local cursor = child.api.nvim_win_get_cursor(0)
			MiniTest.expect.equality(cursor[1], 1)
			MiniTest.expect.equality(cursor[2], 0)
		end)

		it("aborts without creating a note when the selection is blank", function()
			open_source()

			-- select the single space between "alpha" and "beta" (getregion is
			-- inclusive, so both endpoints have to be the same column)
			child.api.nvim_win_set_cursor(0, { 1, 5 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 5 })

			child.lua("vim.fn.input = function() return 'blank' end")
			child.type_keys(":", "MemoNewNote", "<CR>")

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/blank.gpg"), 0)
			MiniTest.expect.equality(child.cmd_capture("messages"), "MemoNewNote: aborted, selection is empty")
		end)
	end)

	describe("nested note autocmds", function()
		it("decrypts a nested note when opened", function()
			vim.fn.mkdir(vim.env.NOTES_DIR .. "/journals", "p")
			helpers.encrypt_file(vim.env.NOTES_DIR .. "/journals/nested.md.gpg", "nested body\n")

			child.lua([[ vim.cmd("silent edit " .. vim.env.NOTES_DIR .. "/journals/nested.md.gpg") ]])
			child.wait_until(function()
				return child.lua_get("vim.b.decrypting") == false
			end, 10000)

			MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "nested body" })
		end)
	end)
end)
