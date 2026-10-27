local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("archive", function()
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
			M.encryption_modes = {}
			memo = require("memo")

			local crypto = require("memo.crypto")

			M.real_get_encryption_mode = require("memo.gpg").get_encryption_mode
		M.real_encrypt_from_stdin = crypto.encrypt_from_stdin
			M.real_decrypt_to_stdout = crypto.decrypt_to_stdout

			crypto.encrypt_from_stdin = function(target, lines, _, opts)
				M.encryption_modes[#M.encryption_modes + 1] = opts.mode
				vim.fn.writefile(lines, target)
				return true
			end
			crypto.decrypt_to_stdout = function(target)
				return { stdout = table.concat(vim.fn.readfile(target), "\n") .. "\n" }
			end
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

	it("refuses to archive an unnamed buffer", function()
		child.lua([[
			vim.cmd("cd " .. vim.fn.fnameescape(vim.env.NOTES_DIR))
			local bufnr = vim.api.nvim_create_buf(true, false)
			vim.api.nvim_set_current_buf(bufnr)
			vim.bo[bufnr].modifiable = true
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "archive me" })
		]])

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), false)
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "archive me" })
		MiniTest.expect.equality(vim.fn.filereadable(path("note.archive.md.asc")), 0)
	end)

	it("refuses to archive a directory buffer", function()
		child.lua([[
			local bufnr = vim.api.nvim_create_buf(true, false)
			vim.api.nvim_buf_set_name(bufnr, vim.env.NOTES_DIR)
			vim.api.nvim_set_current_buf(bufnr)
			vim.bo[bufnr].modifiable = true
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "archive me" })
		]])

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), false)
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "archive me" })
	end)

	it("moves selected lines to an encrypted companion archive and preserves their order", function()
		local bufnr = buffer("note.md", { "# Note", "keep this", "archive one", "archive two", "keep this too" })

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 3, line2 = 4 })"), true)
		MiniTest.expect.equality(
			child.api.nvim_buf_get_lines(bufnr, 0, -1, false),
			{ "# Note", "keep this", "keep this too" }
		)

		local archived = vim.fn.readfile(path("note.archive.md.asc"))
		MiniTest.expect.equality(vim.tbl_contains(archived, "archive one"), true)
		MiniTest.expect.equality(vim.tbl_contains(archived, "archive two"), true)
		MiniTest.expect.equality(vim.tbl_contains(archived, "Source: note.md"), true)
		MiniTest.expect.equality(
			--- @diagnostic disable-next-line: need-check-nil, param-type-mismatch
			archived[4]:match("^Archived: %d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d[+-]%d%d%d%d$") ~= nil,
			true
		)
	end)

	it("archives only the active character-wise selection", function()
		local bufnr = buffer("note.md", { "keep archive word tail" })

		child.lua([[
			vim.api.nvim_win_set_cursor(0, { 1, 5 })
			vim.keymap.set("x", "<leader>ma", function()
				M.archive()
			end)
			vim.api.nvim_feedkeys(
				vim.api.nvim_replace_termcodes("v6l<leader>ma", true, false, true),
				"xt",
				false
			)
		]])

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "keep  word tail" })
		MiniTest.expect.equality(child.lua_get("vim.fn.mode()"), "n")
		local archived = vim.fn.readfile(path("note.archive.md.asc"))
		MiniTest.expect.equality(vim.tbl_contains(archived, "archive"), true)
		MiniTest.expect.equality(vim.tbl_contains(archived, "keep archive word tail"), false)
	end)

	it("archives the active visual selection when called without options", function()
		local bufnr = buffer("note.md", { "keep", "archive one", "archive two", "keep too" })

		child.lua([[
			vim.keymap.set("x", "<leader>ma", function()
				M.archive()
			end)
			vim.api.nvim_feedkeys(
				vim.api.nvim_replace_termcodes("jVj<leader>ma", true, false, true),
				"xt",
				false
			)
		]])

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "keep", "keep too" })
		MiniTest.expect.equality(child.lua_get("vim.fn.mode()"), "n")
		local archived = vim.fn.readfile(path("note.archive.md.asc"))
		MiniTest.expect.equality(vim.tbl_contains(archived, "archive one"), true)
		MiniTest.expect.equality(vim.tbl_contains(archived, "archive two"), true)
	end)

	it("encrypts archives for plaintext notes and preserves the content extension", function()
		buffer("note.txt", { "archive me" })

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), true)
		MiniTest.expect.equality(vim.fn.filereadable(path("note.archive.txt.asc")), 1)
		MiniTest.expect.equality(child.lua_get("M.encryption_modes[1]"), "key")
	end)

	it("appends entries without overwriting an existing archive", function()
		local bufnr = buffer("note.md", { "first", "second" })
		helpers.write_file(path("note.archive.md.asc"), "older entry\n")

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), true)

		local archived = vim.fn.readfile(path("note.archive.md.asc"))
		MiniTest.expect.equality(archived[1], "older entry")
		MiniTest.expect.equality(archived[2], "")
		MiniTest.expect.equality(archived[3], "---")
		MiniTest.expect.equality(archived[4], "")
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "second" })
	end)

	it("aborts cleanly when decrypting an existing archive is cancelled", function()
		local bufnr = buffer("note.md", { "keep", "archive me" })
		local archive_path = path("note.archive.md.asc")
		helpers.write_file(archive_path, "older entry\n")
		child.lua([[
			require("memo.crypto").decrypt_to_stdout = function()
				return nil, nil
			end
		]])

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 2, line2 = 2 })"), false)
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "keep", "archive me" })
		MiniTest.expect.equality(vim.fn.readfile(archive_path), { "older entry" })
	end)

	it("uses the source buffer for archive passphrase caching", function()
		local bufnr = buffer("note.md", { "keep", "archive me" })
		helpers.write_file(path("note.archive.md.asc"), "older entry\n")
		child.lua(
			[[
			local crypto = require("memo.crypto")
			local bufnr = ...
			vim.b[bufnr].memo_symmetric_passphrase = "source-passphrase"
			crypto.decrypt_to_stdout = function(_, archive_bufnr)
				M.decrypt_bufnr = archive_bufnr
				return { stdout = "older entry\n" }
			end
			crypto.encrypt_from_stdin = function(_, _, archive_bufnr)
				M.encrypt_bufnr = archive_bufnr
				return true
			end
			]],
			{ bufnr }
		)
		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 2, line2 = 2 })"), true)
		MiniTest.expect.equality(child.lua_get("M.decrypt_bufnr == ...", { bufnr }), true)
		MiniTest.expect.equality(child.lua_get("M.encrypt_bufnr == ...", { bufnr }), true)
		MiniTest.expect.equality(
			child.lua("local bufnr = ...; return vim.b[bufnr].memo_symmetric_passphrase", { bufnr }),
			"source-passphrase"
		)
	end)

	it("writes entries in the archive layout", function()
		buffer("note.md", { "archive one" })

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), true)

		local archived = vim.fn.readfile(path("note.archive.md.asc"))
		MiniTest.expect.equality(archived[1], "")
		MiniTest.expect.equality(archived[2], "---")
		MiniTest.expect.equality(archived[3], "")
		MiniTest.expect.equality(
			--- @diagnostic disable-next-line: need-check-nil, param-type-mismatch
			archived[4]:match("^Archived: %d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d[+-]%d%d%d%d$") ~= nil,
			true
		)
		MiniTest.expect.equality(archived[5], "Source: note.md")
		MiniTest.expect.equality(archived[6], "")
		MiniTest.expect.equality(archived[7], "archive one")
		MiniTest.expect.equality(archived[#archived], "archive one")
	end)

	it("does not remove source lines when the archive cannot be written", function()
		local bufnr = buffer("note.md", { "keep", "archive me" })
		vim.fn.mkdir(path("note.archive.md.asc"), "p")

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 2, line2 = 2 })"), false)
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "keep", "archive me" })
	end)

	it("treats an explicit line range as linewise after a blockwise selection", function()
		local bufnr = buffer("note.md", { "keep one", "archive one", "archive two", "keep two" })

		child.lua([[
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			vim.api.nvim_feedkeys(
				vim.api.nvim_replace_termcodes("<C-v>j<Esc>", true, false, true),
				"xt",
				false
			)
		]])

		MiniTest.expect.equality(child.lua_get("vim.fn.visualmode()"), string.char(22))
		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 2, line2 = 3 })"), true)
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "keep one", "keep two" })

		local archived = vim.fn.readfile(path("note.archive.md.asc"))
		MiniTest.expect.equality(vim.tbl_contains(archived, "archive one"), true)
		MiniTest.expect.equality(vim.tbl_contains(archived, "archive two"), true)
		MiniTest.expect.equality(vim.tbl_contains(archived, "keep one"), false)
	end)

	it("removes a partial new archive when encryption raises", function()
		local bufnr = buffer("note.md", { "keep", "archive me" })

		child.lua([[
			local crypto = require("memo.crypto")
			crypto.encrypt_from_stdin = function(target)
				vim.fn.writefile({ "partial ciphertext" }, target)
				error("simulated encryption failure")
			end
		]])

		child.lua([[
			local ok = pcall(function()
				M.archive({ range = 1, line1 = 2, line2 = 2 })
			end)
			assert(not ok)
		]])
		MiniTest.expect.equality(vim.fn.filereadable(path("note.archive.md.asc")), 0)
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "keep", "archive me" })
	end)

	it("restores an existing archive when encryption raises", function()
		local bufnr = buffer("note.md", { "keep", "archive me" })
		helpers.write_file(path("note.archive.md.asc"), "original archive\n")

		child.lua([[
			local crypto = require("memo.crypto")
			crypto.encrypt_from_stdin = function(target)
				vim.fn.writefile({ "partial ciphertext" }, target)
				error("simulated encryption failure")
			end
		]])

		child.lua([[
			local ok = pcall(function()
				M.archive({ range = 1, line1 = 2, line2 = 2 })
			end)
			assert(not ok)
		]])
		MiniTest.expect.equality(vim.fn.readfile(path("note.archive.md.asc")), { "original archive" })
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "keep", "archive me" })
	end)

	it("refuses to archive a buffer outside the notes directory", function()
		local bufnr = child.lua([[
			local bufnr = vim.api.nvim_create_buf(true, false)
			vim.api.nvim_buf_set_name(bufnr, vim.env.HOME .. "/outside.md")
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep", "archive me" })
			vim.api.nvim_set_current_buf(bufnr)
			return bufnr
		]])

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 2, line2 = 2 })"), false)
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "keep", "archive me" })
		MiniTest.expect.equality(vim.fn.filereadable(vim.env.HOME .. "/outside.archive.md.asc"), 0)
	end)

	it("uses the existing crypto API for encrypted archives", function()
		local bufnr = buffer("note.md.asc", { "keep", "archive me" })

		child.lua([[
			local crypto = require("memo.crypto")

			crypto.encrypt_from_stdin = function(target, lines)
				vim.fn.writefile(lines, target)
				return true
			end
			crypto.decrypt_to_stdout = function(target)
				return { stdout = table.concat(vim.fn.readfile(target), "\n") .. "\n" }
			end
		]])

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 2, line2 = 2 })"), true)
		MiniTest.expect.equality(vim.fn.readfile(path("note.archive.md.asc"))[7], "archive me")
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "keep" })
	end)

	it("encrypts and decrypts a key-encrypted archive across multiple appends", function()
		local bufnr = buffer("note.md", { "first archived entry" })

		child.lua([[
			local crypto = require("memo.crypto")
			crypto.encrypt_from_stdin = M.real_encrypt_from_stdin
			crypto.decrypt_to_stdout = M.real_decrypt_to_stdout
		]])

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), true)
		child.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "second archived entry" })
		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), true)

		local decrypted = helpers.decrypt_file(path("note.archive.md.asc"))

		MiniTest.expect.equality(decrypted.code, 0)
		MiniTest.expect.equality(helpers.is_symmetric_file(path("note.archive.md.asc")), false)
		local stdout = assert(decrypted.stdout)
		MiniTest.expect.equality(stdout:find("first archived entry", 1, true) ~= nil, true)
		MiniTest.expect.equality(stdout:find("second archived entry", 1, true) ~= nil, true)
	end)

	it("preserves symmetric encryption when appending to an archive", function()
		local passphrase = "archive-integration-passphrase"
		helpers.encrypt_symmetric_file(path("note.md.asc"), "source note", passphrase)
		local bufnr = buffer("note.md.asc", { "first archived entry" })

		child.lua([[
			local crypto = require("memo.crypto")
			local gpg = require("memo.gpg")
			crypto.encrypt_from_stdin = M.real_encrypt_from_stdin
			crypto.decrypt_to_stdout = M.real_decrypt_to_stdout
			gpg.get_encryption_mode = M.real_get_encryption_mode
			gpg.prompt_passphrase = function()
				return "archive-integration-passphrase"
			end
		]])

		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), true)
		child.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "second archived entry" })
		MiniTest.expect.equality(child.lua_get("M.archive({ range = 1, line1 = 1, line2 = 1 })"), true)

		local archive = path("note.archive.md.asc")
		local decrypted = helpers.decrypt_symmetric_file(archive, passphrase)

		MiniTest.expect.equality(decrypted.code, 0)
		MiniTest.expect.equality(helpers.is_symmetric_file(archive), true)
		local stdout = assert(decrypted.stdout)
		MiniTest.expect.equality(stdout:find("first archived entry", 1, true) ~= nil, true)
		MiniTest.expect.equality(stdout:find("second archived entry", 1, true) ~= nil, true)
	end)

	it("restores the archive when removing the source selection fails", function()
		local bufnr = buffer("note.md", { "keep", "archive me" })
		local archive_file = path("note.archive.md.asc")
		helpers.write_file(archive_file, "original archive\n")

		child.lua([[
			require("memo.selection").delete_selection = function()
				error("source deletion failed")
			end
			M.archive_raised = not pcall(function()
				M.archive({ range = 1, line1 = 2, line2 = 2 })
			end)
		]])

		MiniTest.expect.equality(child.lua_get("M.archive_raised"), true)
		MiniTest.expect.equality(vim.fn.readfile(archive_file), { "original archive" })
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "keep", "archive me" })
	end)
end)
