local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("pickers.fzf_lua", function()
	before_each(function()
		child.restart({ "-u", "scripts/minimal_init.lua" })
		-- Load tested plugin
		child.lua([[M = require('memo.pickers.fzf_lua')]])
	end)

	after_each(function()
		child.stop()
	end)

	describe("collect_todos", function()
		it("returns all TODOs in the buffer", function()
			local lines = {
				"- [ ] Todo item",
				"- [x] Done item",
				"  * [X] Capitalized done",
				"Not a todo",
			}
			child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
			local result = child.lua([[return M.collect_todos(0, "all")]])

			MiniTest.expect.equality(#result, 3)
			MiniTest.expect.equality(result[1].lnum, 1)
			MiniTest.expect.equality(result[1].raw, "- [ ] Todo item")
			MiniTest.expect.equality(result[2].raw, "- [x] Done item")
			MiniTest.expect.equality(result[3].raw, "  * [X] Capitalized done")
		end)

		it("returns only TODO items in the buffer", function()
			local lines = {
				"- [ ] Todo item",
				"- [x] Done item",
				"  * [X] Capitalized done",
				"Not a todo",
			}
			child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
			local result = child.lua([[return M.collect_todos(0, "todo")]])

			MiniTest.expect.equality(#result, 1)
			MiniTest.expect.equality(result[1].lnum, 1)
			MiniTest.expect.equality(result[1].raw, "- [ ] Todo item")
		end)

		it("returns only DONE items in the buffer", function()
			local lines = {
				"- [ ] Todo item",
				"- [x] Done item",
				"  * [X] Capitalized done",
				"Not a todo",
			}
			child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
			local result = child.lua([[return M.collect_todos(0, "done")]])

			MiniTest.expect.equality(#result, 2)
			MiniTest.expect.equality(result[1].lnum, 2)
			MiniTest.expect.equality(result[1].raw, "- [x] Done item")
			MiniTest.expect.equality(result[2].raw, "  * [X] Capitalized done")
		end)

		it("returns only DONE in the buffer", function()
			local lines = {
				"- [ ] Todo item",
				"- [x] Done item",
				"  * [X] Capitalized done",
				"Not a todo",
			}
			child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
			local result = child.lua([[return M.collect_todos(0, "done")]])

			MiniTest.expect.equality(#result, 2)
			MiniTest.expect.equality(result[1].lnum, 2)
			MiniTest.expect.equality(result[1].raw, "- [x] Done item")
			MiniTest.expect.equality(result[2].raw, "  * [X] Capitalized done")
		end)

		it("returns emtpy table when no todos found", function()
			local lines = {
				"test",
				"bar",
				"baz",
				"Not a todo",
			}
			child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
			local result = child.lua([[return M.collect_todos(0, "done")]])

			MiniTest.expect.equality(#result, 0)
		end)

		it("respects indentation and different markers (*, +, -)", function()
			local lines = {
				"  - [ ] Indented",
				"* [ ] Asterisk",
				"+ [ ] Plus sign",
			}

			child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
			local result = child.lua([[return M.collect_todos(0, "todo")]])

			MiniTest.expect.equality(#result, 3)
		end)
	end)
end)
