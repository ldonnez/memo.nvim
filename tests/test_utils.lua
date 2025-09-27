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

	describe("base_name", function()
		it("returns base name of file", function()
			local util = require("memo.utils")
			local result = util.base_name("test.md.gpg")

			MiniTest.expect.equality(result, "test.md")
		end)
	end)

	describe("get_conflicting_buffer", function()
		it("returns conflicting buffer number", function()
			child.lua([[
    vim.cmd("enew")
    vim.api.nvim_buf_set_name(0, "note.txt")
  ]])
			local conflict = child.lua([[ return M.get_conflicting_buffer("note.txt") ]])
			MiniTest.expect.equality(conflict, 1)
		end)

		it("returns nil when buffer does not exist", function()
			local conflict = child.lua([[ return M.get_conflicting_buffer("nope.txt") ]])
			MiniTest.expect.equality(conflict, vim.NIL)
		end)
	end)

	describe("handle_conflict", function()
		it("returns base name of file", function()
			local bufs = child.lua([[
	   local existing = vim.api.nvim_create_buf(true, false)
	   local new = vim.api.nvim_create_buf(true, false)

	   return { existing = existing, new = new }
	 ]])

			local existing = bufs.existing
			local new = bufs.new

			child.lua(string.format([[ vim.cmd("b %d") ]], new))
			child.lua(string.format([[ M.handle_conflict(%d, %d) ]], existing, new))

			local current_buf = child.lua([[ return vim.api.nvim_get_current_buf() ]])
			MiniTest.expect.equality(current_buf, existing)

			local new_exists = child.lua(string.format(
				[[
	   return vim.api.nvim_buf_is_valid(%d)
	 ]],
				new
			))

			MiniTest.expect.equality(new_exists, false)
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

	describe("in_dir", function()
		it("returns true when given path is in dir", function()
			local util = require("memo.utils")
			local result = util.in_dir("~/notes", "~/notes/test")

			MiniTest.expect.equality(result, true)
		end)

		it("returns false when given path is not in dir", function()
			local util = require("memo.utils")
			local result = util.in_dir("~/notes", "~/test")

			MiniTest.expect.equality(result, false)
		end)
	end)
end)
