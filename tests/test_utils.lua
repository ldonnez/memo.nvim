local child = MiniTest.new_child_neovim()

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

	describe("harden_buffer", function()
		it("correctly sets buffer-local security options", function()
			local bufnr = vim.api.nvim_create_buf(false, true)

			util.harden_buffer(bufnr)

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
