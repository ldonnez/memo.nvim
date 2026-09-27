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

		it("refuses to overwrite an existing note", function()
			child.lua_get([[ new_note.create({ path = "existing.md" }) ]])

			MiniTest.expect.equality(child.lua_get([[ new_note.create({ path = "existing.md" }) ]]), false)
		end)

		it("refuses a path outside the notes dir", function()
			MiniTest.expect.equality(child.lua_get([[ new_note.create({ path = "../escape.md" }) ]]), false)
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
