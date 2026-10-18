local helpers = require("tests.helpers")
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

	describe("get_filetype", function()
		it("detects markdown from the name without .asc", function()
			MiniTest.expect.equality(util.get_filetype("note.md.asc"), "markdown")
		end)

		it("detects markdown from the name without .gpg", function()
			MiniTest.expect.equality(util.get_filetype("note.md.gpg"), "markdown")
		end)

		it("detects lua from the name without the note extension", function()
			MiniTest.expect.equality(util.get_filetype("config.lua.asc"), "lua")
		end)

		it("detects text from the name without the note extension", function()
			MiniTest.expect.equality(util.get_filetype("note.txt.gpg"), "text")
		end)

		it("returns nil when only the note extension is left", function()
			MiniTest.expect.equality(util.get_filetype("note.asc"), nil)
		end)

		it("returns nil for a name without an extension", function()
			MiniTest.expect.equality(util.get_filetype("note"), nil)
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

	describe("is_armored_gpg", function()
		it("returns true for an armored PGP message", function()
			local path = vim.fn.tempname()
			helpers.write_file(path, "-----BEGIN PGP MESSAGE-----\n\nciphertext\n")

			MiniTest.expect.equality(util.is_armored_gpg(path), true)

			vim.fn.delete(path)
		end)

		it("returns false for a plaintext file", function()
			local path = vim.fn.tempname()
			helpers.write_file(path, "just a plain note\n")

			MiniTest.expect.equality(util.is_armored_gpg(path), false)

			vim.fn.delete(path)
		end)

		it("returns false for an empty file", function()
			local path = vim.fn.tempname()
			helpers.write_file(path, "")

			MiniTest.expect.equality(util.is_armored_gpg(path), false)

			vim.fn.delete(path)
		end)

		it("returns false for a missing file", function()
			MiniTest.expect.equality(util.is_armored_gpg(vim.fn.tempname() .. "/nope.md.gpg"), false)
		end)

		it("returns false for a directory", function()
			local dir = vim.fn.tempname()
			vim.fn.mkdir(dir, "p")

			MiniTest.expect.equality(util.is_armored_gpg(dir), false)

			vim.fn.delete(dir, "rf")
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

	describe("resolve_note_file", function()
		it("returns empty string for empty path", function()
			MiniTest.expect.equality(util.resolve_note_file(""), "")
		end)

		it("returns empty string for directory path (ends with /)", function()
			MiniTest.expect.equality(util.resolve_note_file("notes/"), "")
			MiniTest.expect.equality(util.resolve_note_file("/home/user/notes/"), "")
		end)

		it("returns path with extension when supported extension provided", function()
			MiniTest.expect.equality(util.resolve_note_file("note.md.asc"), "note.md.asc")
			MiniTest.expect.equality(util.resolve_note_file("note.md.gpg"), "note.md.gpg")
		end)

		it("appends default extension when no extension provided", function()
			MiniTest.expect.equality(util.resolve_note_file("note.md"), "note.md.asc")
		end)
	end)

	describe("resolve_note_file with a custom extension", function()
		local original_extension

		before_each(function()
			original_extension = vim.g.memo_extension
			vim.g.memo_extension = "pgp"
			require("memo.config").setup()
		end)

		after_each(function()
			vim.g.memo_extension = original_extension
			require("memo.config").setup()
		end)

		it("appends the configured extension exactly once", function()
			local once = util.resolve_note_file("note.md")

			MiniTest.expect.equality(once, "note.md.pgp")
			MiniTest.expect.equality(util.resolve_note_file(once), once)
			MiniTest.expect.equality(util.get_extension(once), "pgp")
		end)
	end)

	describe("resolve_note_path", function()
		local notes_dir = "/tmp/memo_test_notes"
		local original_notes_dir

		before_each(function()
			helpers.setup_test_env()
			original_notes_dir = vim.g.memo_notes_dir
			vim.g.memo_notes_dir = notes_dir
			require("memo.config").setup()
		end)

		after_each(function()
			helpers.cleanup_test_env()
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

		it("uses the default extension when none is provided", function()
			MiniTest.expect.equality(util.resolve_note_path("note.md"), notes_dir .. "/note.md.asc")
		end)

		it("keeps the extension that was provided", function()
			helpers.write_file(notes_dir .. "/note.md.gpg", "secret")
			-- The given extension wins, even when only the other one is on disk.
			MiniTest.expect.equality(util.resolve_note_path("note.md.asc"), notes_dir .. "/note.md.asc")
		end)

		it("drops a trailing slash from the notes dir", function()
			vim.g.memo_notes_dir = notes_dir .. "/"
			require("memo.config").setup()

			MiniTest.expect.equality(util.resolve_note_path("note.md"), notes_dir .. "/note.md.asc")
		end)

		it("accepts a note reached through a symlinked notes dir", function()
			local real = "/tmp/memo_test_notes_real_" .. tostring(vim.uv.hrtime())
			local link = real .. "_link"
			vim.fn.mkdir(real, "p")
			vim.uv.fs_symlink(real, link)

			vim.g.memo_notes_dir = link
			require("memo.config").setup()

			MiniTest.expect.equality(util.resolve_note_path("note.md"), link .. "/note.md.asc")

			vim.fn.delete(link)
			vim.fn.delete(real, "rf")
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

			-- The error is deferred so it is safe inside an autocmd; let the
			-- scheduler run before inspecting the messages.
			vim.wait(1000, function()
				local messages = vim.api.nvim_exec2("messages", { output = true }).output
				return messages:find("Error creating directory", 1, true) ~= nil
			end)

			local messages = vim.api.nvim_exec2("messages", { output = true }).output
			MiniTest.expect.equality(messages:find("Error creating directory", 1, true) ~= nil, true)
			MiniTest.expect.equality(messages:find(dir, 1, true) ~= nil, true)

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

		it("returns nil for a missing module instead of the error string", function()
			local result = util.load_plugin("memo.definitely.missing")

			MiniTest.expect.equality(result, nil)
		end)

		it("returns nil for a missing module when the packadd fallback runs", function()
			child.lua([[
        local original_has = vim.fn.has
        vim.fn.has = function(name)
          if name == "nvim-0.12" then
            return 1
          end
          return original_has(name)
        end
      ]])

			local result = child.lua_get([[ M.load_plugin("memo.definitely.missing") == nil ]])

			MiniTest.expect.equality(result, true)
		end)

		it("returns the module when the packadd retry succeeds", function()
			child.lua([[
        local original_has = vim.fn.has
        local original_cmd = vim.cmd
        vim.fn.has = function(name)
          if name == "nvim-0.12" then
            return 1
          end
          return original_has(name)
        end
        vim.cmd = setmetatable({}, {
          __index = function()
            return function() end
          end,
        })
        vim.cmd.packadd = function()
          package.loaded["memo.fake.plugin"] = { files = "here" }
        end
      ]])

			local result = child.lua_get([[ M.load_plugin("memo.fake.plugin") ]])

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

	describe("file_signature", function()
		it("returns a signature for an existing file", function()
			local path = vim.fn.tempname()
			helpers.write_file(path, "content")

			MiniTest.expect.equality(type(util.file_signature(path)), "string")

			vim.fn.delete(path)
		end)

		it("returns nil for a missing file", function()
			MiniTest.expect.equality(util.file_signature(vim.fn.tempname()), nil)
		end)

		it("returns the same signature when the file has not changed", function()
			local path = vim.fn.tempname()
			helpers.write_file(path, "content")

			local first = util.file_signature(path)
			local second = util.file_signature(path)

			MiniTest.expect.equality(second, first)

			vim.fn.delete(path)
		end)

		it("returns a different signature when the file size changes", function()
			local path = vim.fn.tempname()
			helpers.write_file(path, "content")

			local before = util.file_signature(path)

			helpers.write_file(path, "updated content with a different size")

			local after = util.file_signature(path)

			MiniTest.expect.no_equality(after, before)

			vim.fn.delete(path)
		end)
	end)
end)
