local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("sync", function()
	before_each(function()
		child.restart({ "-u", "scripts/minimal_init.lua" })
	end)

	after_each(function()
		child.stop()
	end)

	---Replaces `vim.system` so the sync outcome is controlled without the CLI.
	---@param code integer
	local function stub_exit_code(code)
		child.lua(
			[[
      local exit_code = ...
      vim.system = function()
        return { wait = function() return { code = exit_code } end }
      end
    ]],
			{ code }
		)
	end

	it("returns true and reports completion when the sync succeeds", function()
		stub_exit_code(0)

		MiniTest.expect.equality(child.lua_get([[ require("memo.sync").sync_git() ]]), true)
		MiniTest.expect.equality(child.cmd_capture("messages"), "Sync complete: git")
	end)

	it("returns false and reports an error when the sync fails", function()
		stub_exit_code(1)

		MiniTest.expect.equality(child.lua_get([[ require("memo.sync").sync_git() ]]), false)
		MiniTest.expect.equality(child.cmd_capture("messages"), "Something went wrong syncing git")
	end)
end)
