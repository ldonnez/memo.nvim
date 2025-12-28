local child = MiniTest.new_child_neovim()

describe("config", function()
	local TEST_HOME = vim.fn.resolve("/tmp/memo.nvim")

	before_each(function()
		vim.env.HOME = TEST_HOME

		vim.fn.mkdir(TEST_HOME, "p")

		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})
	end)

	after_each(function()
		vim.fn.delete(TEST_HOME, "rf")
		child.stop()
	end)

	it("correctly loads default notes_dir", function()
		vim.fn.mkdir(TEST_HOME .. "/notes", "p")

		child.lua([[ require('memo.config').setup() ]])
		local result_dir = child.lua([[ return require('memo.config').notes_dir ]])

		MiniTest.expect.equality(result_dir, TEST_HOME .. "/notes")
	end)

	it("errors when notes dir does not exist", function()
		local notes_dir = TEST_HOME .. "/i-do-not-exist"

		child.lua(string.format(
			[[
        require('memo.config').setup({ notes_dir = %q })
    ]],
			notes_dir
		))
		local messages = child.cmd_capture("messages")

		MiniTest.expect.equality(messages, string.format("Memo: Directory '%s' does not exist.", notes_dir))
	end)

	it("correctly loads given notes_dir", function()
		local notes_dir = TEST_HOME .. "/my-notes"
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
