local helpers = require("tests.helpers")
local cleanup_test_env = require("tests.helpers").cleanup_test_env
local child = helpers.new_child_neovim()

describe("utils", function()
	local util = require("memo.utils")

	before_each(function()
		child.restart({ "-u", "scripts/minimal_init.lua" })
		-- Load tested plugin
		child.lua([[M = require('memo.utils')]])
	end)

	after_each(function()
		child.stop()
	end)

	describe("get_extension", function()
		it("returns asc", function()
			MiniTest.expect.equality(util.get_extension("test.md.asc"), "asc")
		end)

		it("returns gpg", function()
			MiniTest.expect.equality(util.get_extension("test.md.gpg"), "gpg")
		end)

		it("returns nil for another extension", function()
			MiniTest.expect.equality(util.get_extension("test.md"), nil)
		end)

		it("returns nil for no extension", function()
			MiniTest.expect.equality(util.get_extension("test"), nil)
		end)
	end)

	describe("strip_extension", function()
		it("strips .asc", function()
			MiniTest.expect.equality(util.strip_extension("test.md.asc"), "test.md")
		end)

		it("strips .gpg", function()
			MiniTest.expect.equality(util.strip_extension("test.md.gpg"), "test.md")
		end)

		it("keeps another extension", function()
			MiniTest.expect.equality(util.strip_extension("test.md"), "test.md")
		end)
	end)

	describe("is_in_dir", function()
		it("returns true when path is inside dir", function()
			MiniTest.expect.equality(util.is_in_dir("/tmp/memo_test/sub/note.gpg", "/tmp/memo_test"), true)
		end)

		it("returns true when dir ends with a slash", function()
			MiniTest.expect.equality(util.is_in_dir("/tmp/memo_test/note.gpg", "/tmp/memo_test/"), true)
		end)

		it("returns false when path is the dir itself", function()
			MiniTest.expect.equality(util.is_in_dir("/tmp/memo_test", "/tmp/memo_test"), false)
		end)

		it("returns false when path is outside dir", function()
			MiniTest.expect.equality(util.is_in_dir("/tmp/memo_test_other/note.gpg", "/tmp/memo_test"), false)
		end)

		it("returns false when path escapes dir via ..", function()
			MiniTest.expect.equality(util.is_in_dir("/tmp/memo_test/../outside/note.gpg", "/tmp/memo_test"), false)
		end)

		it("returns false for a sibling sharing the dir prefix", function()
			MiniTest.expect.equality(util.is_in_dir("/tmp/memo_test_evil/note.gpg", "/tmp/memo_test"), false)
		end)
	end)

	describe("file_exists", function()
		it("returns true for a readable file", function()
			local path = vim.fn.tempname()
			helpers.write_file(path, "content")

			MiniTest.expect.equality(util.file_exists(path), true)

			vim.fn.delete(path)
		end)

		it("returns false for a missing file", function()
			MiniTest.expect.equality(util.file_exists(vim.fn.tempname() .. "/nope.md.gpg"), false)
		end)

		it("returns false for a directory", function()
			MiniTest.expect.equality(util.file_exists(vim.fn.tempname()), false)
		end)
	end)

	describe("file_has_content", function()
		it("returns true for a file with content", function()
			local path = vim.fn.tempname()
			helpers.write_file(path, "content")

			MiniTest.expect.equality(util.file_has_content(path), true)

			vim.fn.delete(path)
		end)

		it("returns false for an empty file", function()
			local path = vim.fn.tempname()
			helpers.write_file(path, "")

			MiniTest.expect.equality(util.file_has_content(path), false)

			vim.fn.delete(path)
		end)

		it("returns false for a missing file", function()
			MiniTest.expect.equality(util.file_has_content(vim.fn.tempname()), false)
		end)
	end)

	describe("build_note_path", function()
		local notes_dir = "/tmp/memo_test_notes"
		local original_notes_dir

		before_each(function()
			original_notes_dir = vim.g.memo_notes_dir
			vim.g.memo_notes_dir = notes_dir
			require("memo.config").setup()
		end)

		after_each(function()
			vim.g.memo_notes_dir = original_notes_dir
			require("memo.config").setup()
		end)

		it("builds a full path inside the notes dir", function()
			MiniTest.expect.equality(util.build_note_path("note.md"), notes_dir .. "/note.md.asc")
		end)

		it("keeps a name that already ends with .asc", function()
			MiniTest.expect.equality(util.build_note_path("note.md.asc"), notes_dir .. "/note.md.asc")
		end)

		it("keeps a name that already ends with .gpg", function()
			MiniTest.expect.equality(util.build_note_path("note.md.gpg"), notes_dir .. "/note.md.gpg")
		end)

		it("builds a full path for a nested name", function()
			MiniTest.expect.equality(
				util.build_note_path("journals/2026-01-01.md"),
				notes_dir .. "/journals/2026-01-01.md.asc"
			)
		end)

		it("blocks path traversal with ..", function()
			MiniTest.expect.equality(util.build_note_path("../escape.md"), "")
		end)

		it("blocks absolute paths", function()
			MiniTest.expect.equality(util.build_note_path("/etc/passwd"), "")
		end)

		it("blocks path traversal with nested ..", function()
			MiniTest.expect.equality(util.build_note_path("subdir/../../escape.md"), "")
		end)

		it("returns empty string for empty name", function()
			MiniTest.expect.equality(util.build_note_path(""), "")
		end)
	end)
	end)

	describe("resolve_note_path", function()
		local notes_dir = "/tmp/memo_test_notes"
		local original_notes_dir

		before_each(function()
			cleanup_test_env()
			original_notes_dir = vim.g.memo_notes_dir
			vim.g.memo_notes_dir = notes_dir
			require("memo.config").setup()
		end)

		after_each(function()
			vim.g.memo_notes_dir = original_notes_dir
			require("memo.config").setup()
		end)

		it("resolves a relative path against the notes dir", function()
			MiniTest.expect.equality(util.resolve_note_path("note.md"), notes_dir .. "/note.md.asc")
		end)

		it("keeps a relative path that already ends with .asc", function()
			MiniTest.expect.equality(util.resolve_note_path("note.md.asc"), notes_dir .. "/note.md.asc")
		end)

		it("keeps a relative path that already ends with .gpg", function()
			MiniTest.expect.equality(util.resolve_note_path("note.md.gpg"), notes_dir .. "/note.md.gpg")
		end)

		it("resolves a nested relative path", function()
			MiniTest.expect.equality(
				util.resolve_note_path("journals/2026-01-01.md"),
				notes_dir .. "/journals/2026-01-01.md.asc"
			)
		end)

		it("keeps an absolute path inside the notes dir", function()
			MiniTest.expect.equality(util.resolve_note_path(notes_dir .. "/abs.md"), notes_dir .. "/abs.md.asc")
		end)

		it("expands a leading tilde", function()
			local home_notes = vim.fn.expand("~") .. "/memo_test_notes"
			vim.g.memo_notes_dir = home_notes
			require("memo.config").setup()

			MiniTest.expect.equality(util.resolve_note_path("~/memo_test_notes/t.md"), home_notes .. "/t.md.asc")
		end)

		it("returns nil for a relative path escaping the notes dir", function()
			MiniTest.expect.equality(util.resolve_note_path("../escape.md"), nil)
		end)

		it("returns nil for an absolute path outside the notes dir", function()
			MiniTest.expect.equality(util.resolve_note_path("/tmp/elsewhere/note.md"), nil)
		end)

		it("returns nil for a sibling directory sharing the notes dir prefix", function()
			MiniTest.expect.equality(util.resolve_note_path(notes_dir .. "_evil/note.md"), nil)
		end)

		it("returns nil for the notes dir itself", function()
			MiniTest.expect.equality(util.resolve_note_path(notes_dir), nil)
		end)

		it("returns nil for an empty path", function()
			MiniTest.expect.equality(util.resolve_note_path(""), nil)
		end)

		it("uses default extension when no extension provided and no legacy file", function()
			MiniTest.expect.equality(util.resolve_note_path("legacy.md"), notes_dir .. "/legacy.md.asc")
		end)

		it("does not fall back when user provides non-existent extension", function()
			helpers.write_file(notes_dir .. "/note.md.gpg", "secret")
			-- User provides .asc but only .gpg exists - no fallback, returns .asc path
			MiniTest.expect.equality(util.resolve_note_path("note.md.asc"), notes_dir .. "/note.md.asc")
		end)
	end)

	describe("prompt_note_path", function()
		it("returns the entered path", function()
			local original_input = vim.fn.input
			vim.fn.input = function()
				return "typed.md"
			end

			MiniTest.expect.equality(util.prompt_note_path("/tmp/notes/default.md.asc", "MemoTest"), "typed.md")

			vim.fn.input = original_input
		end)

		it("returns the default when input returns it unchanged", function()
			local original_input = vim.fn.input
			vim.fn.input = function(_, default)
				return default
			end

			MiniTest.expect.equality(
				util.prompt_note_path("/tmp/notes/default.md.asc", "MemoTest"),
				"/tmp/notes/default.md.asc"
			)

			vim.fn.input = original_input
		end)

		it("returns nil for an empty path", function()
			local original_input = vim.fn.input
			vim.fn.input = function()
				return ""
			end

			MiniTest.expect.equality(util.prompt_note_path("/tmp/notes/default.md.asc", "MemoTest"), nil)

			vim.fn.input = original_input
		end)
	end)

	describe("confirm", function()
		local original_confirm

		before_each(function()
			original_confirm = vim.fn.confirm
		end)

		after_each(function()
			vim.fn.confirm = original_confirm
		end)

		it("returns true when the user confirms", function()
			vim.fn.confirm = function()
				return 1
			end

			MiniTest.expect.equality(util.confirm("Overwrite?", "MemoTest"), true)
		end)

		it("returns false and warns when the user declines", function()
			vim.fn.confirm = function()
				return 2
			end

			MiniTest.expect.equality(util.confirm("Overwrite?", "MemoTest"), false)

			local messages = vim.api.nvim_exec2("messages", { output = true }).output
			MiniTest.expect.equality(messages:find("MemoTest: aborted", 1, true) ~= nil, true)
		end)
	end)

	describe("ensure_directories", function()
		it("returns true when the directory already exists", function()
			local dir = vim.fn.tempname() .. "_exists"
			vim.fn.mkdir(dir, "p")

			MiniTest.expect.equality(util.ensure_directories(dir), true)

			vim.fn.delete(dir, "rf")
		end)

		it("creates nested directories and returns true", function()
			local dir = vim.fn.tempname() .. "/a/b/c"

			MiniTest.expect.equality(util.ensure_directories(dir), true)
			MiniTest.expect.equality(vim.fn.isdirectory(dir), 1)

			vim.fn.delete(dir, "rf")
		end)

		it("returns false when the directory cannot be created", function()
			local blocked = vim.fn.tempname()
			local dir = blocked .. "/sub"
			helpers.write_file(blocked, "not a directory")

			MiniTest.expect.equality(util.ensure_directories(dir), false)

			vim.fn.delete(blocked)
		end)
	end)

	describe("check_exec", function()
		it("returns true when binary exists", function()
			local result = util.check_exec("git")

			MiniTest.expect.equality(result, true)
		end)

		it("returns false and show message when binary does not exist", function()
			local cmd = "i-do-not-exst"
			local result = child.lua_get("M.check_exec(...)", { cmd })
			local messages = child.cmd_capture("messages")

			MiniTest.expect.equality(result, false)
			MiniTest.expect.equality(messages, string.format("'%s' binary not found", cmd))
		end)
	end)

	describe("load_plugin", function()
		it("returns module when already loaded", function()
			local result = util.load_plugin("memo.utils", "memo.nvim")

			MiniTest.expect.equality(type(result), "table")
		end)

		it("returns module when only import_name is passed", function()
			local result = util.load_plugin("memo.utils")

			MiniTest.expect.equality(type(result), "table")
		end)
	end)

	describe("resolve_selection", function()
		before_each(function()
			child.cmd("normal! gg")
			child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha beta gamma', 'delta epsilon' })")
		end)

		it("returns nil when not in visual mode", function()
			child.cmd("normal! gg")
			local result = child.lua_get("M.resolve_selection() == nil")
			MiniTest.expect.equality(result, true)
		end)

		it("returns the charwise selection", function()
			child.cmd("normal! gg")
			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })

			local lines = child.lua_get("M.resolve_selection()")
			MiniTest.expect.equality(lines, { "beta" })
		end)

		it("returns the multi-line visual selection", function()
			child.cmd("normal! gg")
			child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha', 'beta', 'gamma', 'delta' })")
			child.api.nvim_win_set_cursor(0, { 2, 0 })
			child.cmd("normal! V")
			child.api.nvim_win_set_cursor(0, { 3, 4 })

			local lines = child.lua_get("M.resolve_selection()")
			MiniTest.expect.equality(lines, { "beta", "gamma" })
		end)

		it("returns the selection when made backwards", function()
			child.cmd("normal! gg")
			child.api.nvim_win_set_cursor(0, { 1, 9 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 6 })

			local lines = child.lua_get("M.resolve_selection()")
			MiniTest.expect.equality(lines, { "beta" })
		end)

		it("returns the charwise range from the '< and '> marks when opts.range is set", function()
			child.cmd("normal! gg")
			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })
			child.api.nvim_input("<Esc>")

			local lines = child.lua_get("M.resolve_selection(0, { range = 1 })")
			MiniTest.expect.equality(lines, { "beta" })
		end)

		it("returns the multi-line range from the '< and '> marks when opts.range is set", function()
			child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha', 'beta', 'gamma', 'delta' })")
			child.cmd("normal! gg")
			child.api.nvim_win_set_cursor(0, { 2, 0 })
			child.cmd("normal! V")
			child.api.nvim_win_set_cursor(0, { 3, 4 })
			child.api.nvim_input("<Esc>")

			local lines = child.lua_get("M.resolve_selection(0, { range = 1 })")
			MiniTest.expect.equality(lines, { "beta", "gamma" })
		end)

		it("falls back to opts.line1 and line2 when the '< and '> marks are not in the buffer", function()
			local other = child.api.nvim_create_buf(false, true)
			child.api.nvim_buf_set_lines(other, 0, -1, false, { "other one", "other two" })
			child.lua(string.format([[vim.fn.setpos("'<", { %d, 1, 1, 0 })]], other))
			child.lua(string.format([[vim.fn.setpos("'>", { %d, 2, 1, 0 })]], other))
			child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'x y', 'delta epsilon' })")

			local lines = child.lua_get("M.resolve_selection(0, { range = 1, line1 = 2, line2 = 2 })")
			MiniTest.expect.equality(lines, { "delta epsilon" })
		end)
	end)

	describe("drop_buffer_with_error", function()
		it("shows the message and throws the buffer away", function()
			local bufnr = child.lua([[
				local bufnr = vim.api.nvim_create_buf(true, false)
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "content" })

				M.drop_buffer_with_error(bufnr, "Decryption failed: nope")

				return bufnr
			]])

			child.wait_until(function()
				return not child.api.nvim_buf_is_valid(bufnr)
			end)

			MiniTest.expect.equality(child.api.nvim_buf_is_valid(bufnr), false)
			MiniTest.expect.equality(child.cmd_capture("messages"), "Decryption failed: nope")
		end)

		it("shows the message even when the buffer is already gone", function()
			local result = child.lua([[
				local bufnr = vim.api.nvim_create_buf(true, false)
				vim.api.nvim_buf_delete(bufnr, { force = true })

				M.drop_buffer_with_error(bufnr, "Decryption failed: nope")

				return "survived"
			]])

			MiniTest.expect.equality(result, "survived")
		end)
	end)
end)
