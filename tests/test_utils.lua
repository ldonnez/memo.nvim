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

	describe("get_gpg_path", function()
		it("adds .gpg to given path", function()
			local util = require("memo.utils")
			local result = util.get_gpg_path("test.md")

			MiniTest.expect.equality(result, "test.md.gpg")
		end)

		it("does not add .gpg when path already is .gpg", function()
			local util = require("memo.utils")
			local result = util.get_gpg_path("test.md.gpg")

			MiniTest.expect.equality(result, "test.md.gpg")
		end)
	end)

	describe("merge_memo_content", function()
		it("inserts new content after the second line", function()
			local util = require("memo.utils")
			local existing = { "Header", "---", "Old Note 1", "Old Note 2" }
			local new_lines = { "New Thought" }

			local result = util.merge_content(existing, new_lines)

			-- Expected structure:
			-- 1: Header (Existing[1])
			-- 2: ---    (Existing[2])
			-- 3: New Thought (New)
			-- 4: "" (Separator)
			-- 5: Old Note 1 (Existing[3])
			-- 6: Old Note 2 (Existing[4])

			MiniTest.expect.equality(#result, 6)
			MiniTest.expect.equality(result[1], "Header")
			MiniTest.expect.equality(result[2], "---")
			MiniTest.expect.equality(result[3], "New Thought")
			MiniTest.expect.equality(result[4], "")
			MiniTest.expect.equality(result[5], "Old Note 1")
		end)

		it("handles empty existing files gracefully", function()
			local util = require("memo.utils")
			-- Even if the file is empty, it should ensure line 1 and 2 exist
			local existing = {}
			local new_lines = { "First Note" }

			local result = util.merge_content(existing, new_lines)

			MiniTest.expect.equality(result[1], "")
			MiniTest.expect.equality(result[2], "")
			MiniTest.expect.equality(result[3], "First Note")
			MiniTest.expect.equality(result[4], "")
		end)

		it("preserves multi-line new content", function()
			local util = require("memo.utils")
			local existing = { "Title", "====", "Bottom" }
			local new_lines = { "Line A", "Line B" }

			local result = util.merge_content(existing, new_lines)

			-- Title, ====, Line A, Line B, "", Bottom
			MiniTest.expect.equality(result[3], "Line A")
			MiniTest.expect.equality(result[4], "Line B")
			MiniTest.expect.equality(result[5], "")
			MiniTest.expect.equality(result[6], "Bottom")
		end)
	end)

	describe("to_lines", function()
		it("splits a basic string into lines", function()
			local util = require("memo.utils")
			local input = "Line 1\nLine 2"
			local result = util.to_lines(input)

			MiniTest.expect.equality(#result, 2)
			MiniTest.expect.equality(result[1], "Line 1")
			MiniTest.expect.equality(result[2], "Line 2")
		end)

		it("removes the trailing empty line caused by a final newline", function()
			local util = require("memo.utils")
			local input = "Line 1\nLine 2\n"
			local result = util.to_lines(input)

			-- Without the cleanup, length would be 3
			MiniTest.expect.equality(#result, 2)
			MiniTest.expect.equality(result[1], "Line 1")
			MiniTest.expect.equality(result[2], "Line 2")
		end)

		it("handles an empty string", function()
			local util = require("memo.utils")
			local result = util.to_lines("")

			MiniTest.expect.equality(#result, 0)
		end)

		it("handles nil gracefully", function()
			local util = require("memo.utils")
			local result = util.to_lines(nil)

			MiniTest.expect.equality(#result, 0)
		end)

		it("preserves internal empty lines", function()
			local util = require("memo.utils")
			local input = "Line 1\n\nLine 3\n"
			local result = util.to_lines(input)

			MiniTest.expect.equality(#result, 3)
			MiniTest.expect.equality(result[2], "")
			MiniTest.expect.equality(result[3], "Line 3")
		end)
	end)

	describe("apply_gpg_opts", function()
		it("correctly sets buffer-local security options", function()
			local util = require("memo.utils")
			local bufnr = vim.api.nvim_create_buf(false, true)

			util.apply_gpg_opts(bufnr)

			local swap = vim.api.nvim_get_option_value("swapfile", { buf = bufnr })
			local undo = vim.api.nvim_get_option_value("undofile", { buf = bufnr })
			local shada = vim.api.nvim_get_option_value("shadafile", {})
			local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })

			MiniTest.expect.equality(swap, false)
			MiniTest.expect.equality(undo, false)
			MiniTest.expect.equality(shada, "NONE")
			MiniTest.expect.equality(buftype, "acwrite")

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end)
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
