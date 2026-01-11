local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("config", function()
	before_each(function()
		helpers.setup_test_env()

		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})
	end)

	after_each(function()
		helpers.cleanup_test_env()
		child.stop()
	end)

	it("correctly loads default notes_dir", function()
		child.lua([[ require('memo.config').setup() ]])
		local result_dir = child.lua([[ return require('memo.config').notes_dir ]])

		MiniTest.expect.equality(result_dir, vim.env.NOTES_DIR)
	end)

	it("errors when notes dir does not exist", function()
		local notes_dir = vim.env.HOME .. "/i-do-not-exist"

		child.lua(string.format(
			[[
        require('memo.config').setup({ notes_dir = %q })
    ]],
			notes_dir
		))
		local messages = child.cmd_capture("messages")

		MiniTest.expect.equality(messages, string.format("Directory '%s' does not exist", notes_dir))
	end)

	it("correctly loads given notes_dir", function()
		local notes_dir = vim.env.HOME .. "/my-notes"
		vim.fn.mkdir(notes_dir, "p")

		child.lua(string.format(
			[[
        require('memo.config').setup({ notes_dir = %q })
    ]],
			notes_dir
		))

		local result = child.lua([[ return require('memo.config').notes_dir ]])
		MiniTest.expect.equality(result, notes_dir)
	end)
end)
