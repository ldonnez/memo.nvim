local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("archive encryption integration", function()
	local passphrase = "archive-integration-passphrase"

	setup(function()
		helpers.setup_test_env()
		helpers.create_gpg_key("archive-integration@example.com")
	end)

	teardown(function()
		helpers.cleanup_test_env()
	end)

	before_each(function()
		vim.fn.delete(vim.env.NOTES_DIR, "rf")
		vim.fn.mkdir(vim.env.NOTES_DIR, "p")

		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		child.lua([[
			vim.g.memo_notes_dir = vim.env.NOTES_DIR
			require("memo.config").setup()
			M = require("memo.archive")
		]])
	end)

	after_each(function()
		child.stop()
	end)

	local function path(name)
		return vim.env.NOTES_DIR .. "/" .. name
	end

	local function buffer(name, lines)
		return child.lua(
			[[
				local name, lines = ...
				local bufnr = vim.api.nvim_create_buf(true, false)
				vim.api.nvim_buf_set_name(bufnr, name)
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
				vim.api.nvim_set_current_buf(bufnr)
				return bufnr
			]],
			{ path(name), lines }
		)
	end

	it("encrypts and decrypts a key-encrypted archive across multiple appends", function()
		local bufnr = buffer("note.md", { "first archived entry" })

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), true)
		child.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "second archived entry" })
		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), true)

		local archive = path("note.archive.md.asc")
		local decrypted = helpers.decrypt_file(archive)

		MiniTest.expect.equality(decrypted.code, 0)
		MiniTest.expect.equality(helpers.is_symmetric_file(archive), false)
		MiniTest.expect.equality(decrypted.stdout:find("first archived entry", 1, true) ~= nil, true)
		MiniTest.expect.equality(decrypted.stdout:find("second archived entry", 1, true) ~= nil, true)
	end)

	it("preserves symmetric encryption when appending to an archive", function()
		helpers.encrypt_symmetric_file(path("note.md.asc"), "source note", passphrase)
		local bufnr = buffer("note.md.asc", { "first archived entry" })

		child.lua(
			[[
				local passphrase = ...
				require("memo.gpg").prompt_passphrase = function()
					return passphrase
				end
			]],
			{ passphrase }
		)

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), true)
		child.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "second archived entry" })
		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), true)

		local archive = path("note.archive.md.asc")
		local decrypted = helpers.decrypt_symmetric_file(archive, passphrase)

		MiniTest.expect.equality(decrypted.code, 0)
		MiniTest.expect.equality(helpers.is_symmetric_file(archive), true)
		MiniTest.expect.equality(decrypted.stdout:find("first archived entry", 1, true) ~= nil, true)
		MiniTest.expect.equality(decrypted.stdout:find("second archived entry", 1, true) ~= nil, true)
	end)
end)
