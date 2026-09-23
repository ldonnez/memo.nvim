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

	describe("get_gpg_path", function()
		it("adds .gpg to given path", function()
			local result = util.get_gpg_path("test.md")

			MiniTest.expect.equality(result, "test.md.gpg")
		end)

		it("does not add .gpg when path already is .gpg", function()
			local result = util.get_gpg_path("test.md.gpg")

			MiniTest.expect.equality(result, "test.md.gpg")
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
			child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha beta gamma', 'delta epsilon' })")
		end)

		it("returns nil when not in visual mode", function()
			child.cmd("normal! gg")
			local result = child.lua_get("M.resolve_selection() == nil")

			MiniTest.expect.equality(result, true)
		end)

		it("returns the characterwise visual selection", function()
			child.cmd("normal! gg")
			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })

			local lines = child.lua_get("M.resolve_selection()")
			MiniTest.expect.equality(lines, { "beta" })
		end)

		it("returns the selection spanning multiple lines", function()
			child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha', 'beta', 'gamma', 'delta' })")
			child.cmd("normal! gg")
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
	end)
end)
