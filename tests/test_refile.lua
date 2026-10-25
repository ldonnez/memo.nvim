local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("refile", function()
	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		child.lua(
			[[
			vim.g.memo_notes_dir = ...
			require("memo.config").setup()

			local crypto = require("memo.crypto")
			crypto.decrypt_to_stdout = function(path)
				return { code = 0, stdout = table.concat(vim.fn.readfile(path), "\n") .. "\n" }
			end
			crypto.encrypt_from_stdin = function(path, lines)
				vim.fn.writefile(lines, path)
				return true
			end

			require("memo.utils").prompt_note_path = function()
				return "destination.md"
			end

			M = require("memo.refile")
			]],
			{ vim.env.NOTES_DIR }
		)
	end)

	after_each(function()
		child.stop()
	end)

	setup(function()
		helpers.setup_test_env()
	end)

	teardown(function()
		helpers.cleanup_test_env()
	end)

	it("appends the selection and removes it from the source after writing", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "before", "move me", "after" })

		local destination = vim.env.NOTES_DIR .. "/destination.md.asc"
		vim.fn.writefile({ "existing" }, destination)

		child.lua([[ M.create({ range = 1, line1 = 2, line2 = 2 }) ]])
		child.cmd("write")

		MiniTest.expect.equality(vim.fn.readfile(destination), { "existing", "", "move me" })
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "before", "after" })
	end)

	it("does not remove the source selection when the destination write fails", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "keep me" })

		child.lua([[
			require("memo.crypto").encrypt_from_stdin = function()
				return false, "write failed"
			end
			M.create({ range = 1, line1 = 1, line2 = 1 })
		]])
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "keep me" })
		MiniTest.expect.equality(child.api.nvim_buf_is_valid(child.api.nvim_get_current_buf()), true)
	end)
end)
