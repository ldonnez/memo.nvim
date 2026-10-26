local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("selection", function()
	before_each(function()
		child.restart({ "-u", "scripts/minimal_init.lua" })
		child.lua([[
			S = require("memo.selection")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha beta gamma", "delta epsilon" })
		]])
	end)

	after_each(function()
		child.stop()
	end)

	it("returns nil when not in visual mode", function()
		child.cmd("normal! gg")
		local result = child.lua_get("S.resolve() == nil")
		MiniTest.expect.equality(result, true)
	end)

	it("returns nil for a blockwise selection", function()
		child.lua([[
			vim.api.nvim_feedkeys(
				vim.api.nvim_replace_termcodes("<C-v>", true, false, true),
				"nx",
				false
			)
		]])

		MiniTest.expect.equality(child.lua_get("S.resolve()"), vim.NIL)
	end)

	it("returns the charwise selection", function()
		child.cmd("normal! gg")
		child.api.nvim_win_set_cursor(0, { 1, 6 })
		child.cmd("normal! v")
		child.api.nvim_win_set_cursor(0, { 1, 9 })

		local lines = child.lua_get("S.resolve()")
		MiniTest.expect.equality(lines, { "beta" })
	end)

	it("returns the multi-line visual selection", function()
		child.cmd("normal! gg")
		child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha', 'beta', 'gamma', 'delta' })")
		child.api.nvim_win_set_cursor(0, { 2, 0 })
		child.cmd("normal! V")
		child.api.nvim_win_set_cursor(0, { 3, 4 })

		local lines = child.lua_get("S.resolve()")
		MiniTest.expect.equality(lines, { "beta", "gamma" })
	end)

	it("returns whole lines when a linewise selection ends at a line start", function()
		child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha', 'beta', 'gamma', 'delta' })")
		child.cmd("normal! gg")
		child.api.nvim_win_set_cursor(0, { 2, 0 })
		child.cmd("normal! V")
		child.api.nvim_win_set_cursor(0, { 3, 0 })

		local lines = child.lua_get("S.resolve()")
		MiniTest.expect.equality(lines, { "beta", "gamma" })
	end)


	it("reports the active visual selection range", function()
		child.cmd("normal! gg")
		child.api.nvim_win_set_cursor(0, { 1, 6 })
		child.cmd("normal! v")
		child.api.nvim_win_set_cursor(0, { 1, 9 })

		local selection = child.lua_get("select(2, S.resolve())")
		MiniTest.expect.equality(selection.linewise, false)
		MiniTest.expect.equality(selection.start[2], 1)
		MiniTest.expect.equality(selection.start[3], 7)
		MiniTest.expect.equality(selection.finish[2], 1)
		MiniTest.expect.equality(selection.finish[3], 10)
	end)

	it("reports the active linewise selection as linewise", function()
		child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha', 'beta', 'gamma', 'delta' })")
		child.cmd("normal! gg")
		child.api.nvim_win_set_cursor(0, { 2, 0 })
		child.cmd("normal! V")
		child.api.nvim_win_set_cursor(0, { 3, 0 })

		local selection = child.lua_get("select(2, S.resolve())")
		MiniTest.expect.equality(selection.linewise, true)
		MiniTest.expect.equality(selection.start[2], 2)
		MiniTest.expect.equality(selection.finish[2], 3)
	end)

	it("returns the selection when made backwards", function()
		child.cmd("normal! gg")
		child.api.nvim_win_set_cursor(0, { 1, 9 })
		child.cmd("normal! v")
		child.api.nvim_win_set_cursor(0, { 1, 6 })

		local lines = child.lua_get("S.resolve()")
		MiniTest.expect.equality(lines, { "beta" })
	end)

	it("uses the explicit command range instead of visual marks", function()
		child.lua([[
			vim.fn.setpos("'<", { 0, 1, 6, 0 })
			vim.fn.setpos("'>", { 0, 1, 9, 0 })
		]])

		local lines = child.lua_get("S.resolve(0, { range = 1, line1 = 2, line2 = 2 })")
		MiniTest.expect.equality(lines, { "delta epsilon" })
	end)

	it("returns the explicit multi-line command range", function()
		child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha', 'beta', 'gamma', 'delta' })")
		local lines = child.lua_get("S.resolve(0, { range = 1, line1 = 2, line2 = 3 })")

		MiniTest.expect.equality(lines, { "beta", "gamma" })
	end)

	it("uses an explicit line range even if visual marks match it", function()
		child.api.nvim_win_set_cursor(0, { 1, 6 })
		child.lua([[
			vim.api.nvim_feedkeys(
				vim.api.nvim_replace_termcodes("v3l<Esc>", true, false, true),
				"xt",
				false
			)
		]])

		local lines = child.lua_get("S.resolve(0, { range = 1, line1 = 1, line2 = 1 })")
		local selection = child.lua_get("select(2, S.resolve(0, { range = 1, line1 = 1, line2 = 1 }))")

		MiniTest.expect.equality(lines, { "alpha beta gamma" })
		MiniTest.expect.equality(selection.linewise, true)
		MiniTest.expect.equality(selection.start[3], 1)
		MiniTest.expect.equality(selection.finish[3], 1)
	end)

	it("uses whole lines when a command range overlaps a characterwise selection", function()
		child.api.nvim_win_set_cursor(0, { 1, 6 })
		child.lua([[
			vim.api.nvim_feedkeys(
				vim.api.nvim_replace_termcodes("v3l<Esc>", true, false, true),
				"xt",
				false
			)
		]])

		local lines = child.lua_get("S.resolve(0, { range = 1, line1 = 1, line2 = 1 })")
		local selection = child.lua_get("select(2, S.resolve(0, { range = 1, line1 = 1, line2 = 1 }))")

		MiniTest.expect.equality(lines, { "alpha beta gamma" })
		MiniTest.expect.equality(selection.linewise, true)
		MiniTest.expect.equality(selection.start[3], 1)
		MiniTest.expect.equality(selection.finish[3], 1)
	end)

	it("reports an explicit command range as linewise regardless of visual marks", function()
		child.lua([[
			vim.fn.setpos("'<", { 0, 1, 6, 0 })
			vim.fn.setpos("'>", { 0, 1, 9, 0 })
		]])

		local selection = child.lua_get("select(2, S.resolve(0, { range = 1, line1 = 1, line2 = 1 }))")
		MiniTest.expect.equality(selection.linewise, true)
		MiniTest.expect.equality(selection.start[2], 1)
		MiniTest.expect.equality(selection.finish[2], 1)
	end)

	it("reports an explicit multi-line command range as linewise", function()
		local selection = child.lua_get("select(2, S.resolve(0, { range = 1, line1 = 2, line2 = 3 }))")

		MiniTest.expect.equality(selection.linewise, true)
		MiniTest.expect.equality(selection.start[2], 2)
		MiniTest.expect.equality(selection.finish[2], 3)
	end)

	it("falls back to opts.line1 and line2 when the '< and '> marks are not in the buffer", function()
		local other = child.api.nvim_create_buf(false, true)
		child.api.nvim_buf_set_lines(other, 0, -1, false, { "other one", "other two" })
		child.lua(string.format([[vim.fn.setpos("'<", { %d, 1, 1, 0 })]], other))
		child.lua(string.format([[vim.fn.setpos("'>", { %d, 2, 1, 0 })]], other))
		child.lua("vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'x y', 'delta epsilon' })")

		local lines = child.lua_get("S.resolve(0, { range = 1, line1 = 2, line2 = 2 })")
		MiniTest.expect.equality(lines, { "delta epsilon" })
	end)

	it("reports the explicit command range as linewise", function()
		local selection = child.lua_get("select(2, S.resolve(0, { range = 1, line1 = 1, line2 = 2 }))")

		MiniTest.expect.equality(selection.linewise, true)
		MiniTest.expect.equality(selection.start, { 0, 1, 1, 0 })
		MiniTest.expect.equality(selection.finish, { 0, 2, 1, 0 })
	end)

	it("returns nil when an explicit line range is missing line numbers", function()
		local lines = child.lua_get("S.resolve(0, { range = 1 })")

		MiniTest.expect.equality(lines, vim.NIL)
	end)

	it("ignores stale visual marks when an explicit range differs", function()
		child.lua([[
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "old selection", "range two", "range three", "last" })
			vim.fn.setpos("'<", { 0, 1, 1, 0 })
			vim.fn.setpos("'>", { 0, 1, 4, 0 })
		]])

		local lines = child.lua_get("S.resolve(0, { range = 1, line1 = 2, line2 = 3 })")
		local selection = child.lua_get("select(2, S.resolve(0, { range = 1, line1 = 2, line2 = 3 }))")

		MiniTest.expect.equality(lines, { "range two", "range three" })
		MiniTest.expect.equality(selection.linewise, true)
	end)

	it("prefers an explicit line range over an active block-wise selection", function()
		child.lua([[
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-v>j", true, false, true), "nx", false)
		]])

		local lines = child.lua_get("S.resolve(0, { range = 1, line1 = 1, line2 = 2 })")

		MiniTest.expect.equality(lines, { "alpha beta gamma", "delta epsilon" })
	end)
	it("deletes a charwise selection", function()
		child.lua([[
			S.delete_selection(0, {
				start = { 0, 1, 7, 0 },
				finish = { 0, 1, 10, 0 },
				linewise = false,
			})
		]])

		MiniTest.expect.equality(child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)"), {
			"alpha  gamma",
			"delta epsilon",
		})
	end)

	it("deletes a backwards charwise selection", function()
		child.lua([[
			S.delete_selection(0, {
				start = { 0, 1, 10, 0 },
				finish = { 0, 1, 7, 0 },
				linewise = false,
			})
		]])

		MiniTest.expect.equality(child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)"), {
			"alpha  gamma",
			"delta epsilon",
		})
	end)

	it("deletes a multi-line charwise selection", function()
		child.lua([[
			S.delete_selection(0, {
				start = { 0, 1, 7, 0 },
				finish = { 0, 2, 5, 0 },
				linewise = false,
			})
		]])

		MiniTest.expect.equality(child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)"), {
			"alpha  epsilon",
		})
	end)



	it("deletes multibyte characters as a whole character", function()
		child.lua([[
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a🙂bc" })
			S.delete_selection(0, {
				start = { 0, 1, 2, 0 },
				finish = { 0, 1, 2, 0 },
				linewise = false,
			})
		]])

		MiniTest.expect.equality(child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)"), { "abc" })
	end)


	it("deletes a linewise selection", function()
		child.lua([[
			S.delete_selection(0, {
				start = { 0, 1, 1, 0 },
				finish = { 0, 1, 1, 0 },
				linewise = true,
			})
		]])

		MiniTest.expect.equality(child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)"), {
			"delta epsilon",
		})
	end)

	it("deletes a backwards linewise selection", function()
		child.lua([[
			S.delete_selection(0, {
				start = { 0, 2, 1, 0 },
				finish = { 0, 1, 1, 0 },
				linewise = true,
			})
		]])

		MiniTest.expect.equality(child.lua_get("vim.api.nvim_buf_get_lines(0, 0, -1, false)"), { "" })
	end)

end)
