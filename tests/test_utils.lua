local child = MiniTest.new_child_neovim()

describe("utils", function()
	before_each(function()
		child.restart({ "-u", "scripts/minimal_init.lua" })
		-- Load tested plugin
		child.lua([[M = require('memo.utils')]])
	end)

	after_each(function()
		child.stop()
	end)

	describe("check_exec", function()
		it("returns true when binary exists", function()
			local util = require("memo.utils")
			local result = util.check_exec("git")

			MiniTest.expect.equality(result, true)
		end)

		it("returns false and show message when binary does not exist", function()
			local cmd = "i-do-not-exst"
			local result = child.lua(string.format(
				[[
        return M.check_exec(%q)
    ]],
				cmd
			))
			local messages = child.cmd_capture("messages")

			MiniTest.expect.equality(result, false)
			MiniTest.expect.equality(messages, string.format("Memo.nvim: '%s' binary not found", cmd))
		end)
	end)
end)
