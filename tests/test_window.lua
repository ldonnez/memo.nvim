local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("window", function()
	before_each(function()
		child.restart({ "-u", "scripts/minimal_init.lua" })
		-- Load tested plugin
		child.lua([[M = require("memo.window")]])
	end)

	after_each(function()
		child.stop()
	end)

	---The screen the defaults are a share of, which is not the size of the
	---current window once a test has opened a split.
	local function screen_size()
		local lines = child.api.nvim_get_option_value("lines", { scope = "global" })
		local columns = child.api.nvim_get_option_value("columns", { scope = "global" })

		return lines, columns
	end

	describe("open", function()
		it("keeps the current window when no config is given", function()
			local win = child.lua_get([[ M.open(nil) ]])

			MiniTest.expect.equality(win, child.api.nvim_get_current_win())
			MiniTest.expect.equality(#child.api.nvim_list_wins(), 1)
		end)

		it("returns the window it opened", function()
			local win = child.lua_get([[ M.open({ split = "vsplit" }) ]])

			MiniTest.expect.equality(win, child.api.nvim_get_current_win())
		end)

		it("opens a horizontal split of half the screen by default", function()
			local lines, columns = screen_size()
			local wins = #child.api.nvim_list_wins()

			local win = child.lua_get([[ M.open({}) ]])

			MiniTest.expect.equality(#child.api.nvim_list_wins(), wins + 1)
			MiniTest.expect.equality(child.api.nvim_win_get_height(win), math.floor(lines / 2))
			MiniTest.expect.equality(child.api.nvim_win_get_width(win), columns)
		end)

		it("opens a vertical split of half the screen width by default", function()
			local _, columns = screen_size()

			local win = child.lua_get([[ M.open({ split = "vsplit" }) ]])

			MiniTest.expect.equality(child.api.nvim_win_get_width(win), math.floor(columns / 2))
		end)

		it("takes the given share of the screen", function()
			local lines = screen_size()

			local win = child.lua_get([[ M.open({ size = 0.25 }) ]])

			MiniTest.expect.equality(child.api.nvim_win_get_height(win), math.floor(lines / 4))
		end)

		it("falls back to the default share for a size of 0 or less", function()
			local lines = screen_size()

			local win = child.lua_get([[ M.open({ size = 0 }) ]])

			MiniTest.expect.equality(child.api.nvim_win_get_height(win), math.floor(lines / 2))
		end)

		it("never opens a window bigger than the screen", function()
			local lines = screen_size()

			local win = child.lua_get([[ M.open({ size = 3 }) ]])

			-- The window it split from keeps a row, so a full share cannot be
			-- reached exactly.
			MiniTest.expect.equality(child.api.nvim_win_get_height(win) >= math.floor(lines / 2), true)
			MiniTest.expect.equality(child.api.nvim_win_get_height(win) <= lines, true)
		end)

		it("opens the window at the given position", function()
			-- Positions are zero based, so the top row is 0.
			local top = child.lua_get([[ M.open({ position = "topleft" }) ]])
			MiniTest.expect.equality(child.api.nvim_win_get_position(top)[1], 0)

			local bottom = child.lua_get([[ M.open({ position = "botright" }) ]])
			MiniTest.expect.equality(child.api.nvim_win_get_position(bottom)[1] > 0, true)
		end)

		it("opens a tab", function()
			local tabs = child.lua_get([[ #vim.api.nvim_list_tabpages() ]])

			child.lua_get([[ M.open({ split = "tab" }) ]])

			MiniTest.expect.equality(child.lua_get([[ #vim.api.nvim_list_tabpages() ]]), tabs + 1)
		end)

		it("ignores the size for a tab", function()
			local _, columns = screen_size()

			local win = child.lua_get([[ M.open({ split = "tab", size = 0.25 }) ]])

			MiniTest.expect.equality(child.api.nvim_win_get_width(win), columns)
		end)

		it("opens the tab after the current one whatever the position", function()
			local win = child.lua_get([[ M.open({ split = "tab", position = "topleft" }) ]])
			local tab = child.api.nvim_win_get_tabpage(win)

			MiniTest.expect.equality(child.api.nvim_tabpage_get_number(tab), 2)
		end)
	end)
end)
