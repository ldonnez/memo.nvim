local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

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

	describe("is_in_dir", function()
		it("returns true when path is inside dir", function()
			MiniTest.expect.equality(util.is_in_dir("/tmp/memo_test/sub/note.gpg", "/tmp/memo_test"), true)
		end)

		it("returns true when dir ends with a slash", function()
			MiniTest.expect.equality(util.is_in_dir("/tmp/memo_test/note.gpg", "/tmp/memo_test/"), true)
		end)

		it("returns false when path is the dir itself", function()
			MiniTest.expect.equality(util.is_in_dir("/tmp/memo_test", "/tmp/memo_test"), false)
		end)

		it("returns false when path is outside dir", function()
			MiniTest.expect.equality(util.is_in_dir("/tmp/memo_test_other/note.gpg", "/tmp/memo_test"), false)
		end)

		it("returns false when path escapes dir via ..", function()
			MiniTest.expect.equality(util.is_in_dir("/tmp/memo_test/../outside/note.gpg", "/tmp/memo_test"), false)
		end)

		it("returns false for a sibling sharing the dir prefix", function()
			MiniTest.expect.equality(util.is_in_dir("/tmp/memo_test_evil/note.gpg", "/tmp/memo_test"), false)
		end)
	end)

	describe("get_notes_dir", function()
		it("defaults to the home notes dir", function()
			vim.g.memo_notes_dir = nil
			MiniTest.expect.equality(util.get_notes_dir(), vim.fn.expand("~/notes"))
		end)

		it("returns vim.g.memo_notes_dir when set", function()
			vim.g.memo_notes_dir = "/tmp/memo-custom-notes"
			MiniTest.expect.equality(util.get_notes_dir(), "/tmp/memo-custom-notes")
			vim.g.memo_notes_dir = nil
		end)
	end)

	describe("get_scratch_dir", function()
		it("defaults to the nvim data dir", function()
			vim.g.memo_scratch_dir = nil
			MiniTest.expect.equality(
				util.get_scratch_dir(),
				vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "memo-scratch")
			)
		end)

		it("returns vim.g.memo_scratch_dir when set", function()
			vim.g.memo_scratch_dir = "/tmp/memo-custom-scratch"
			MiniTest.expect.equality(util.get_scratch_dir(), "/tmp/memo-custom-scratch")
			vim.g.memo_scratch_dir = nil
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
			MiniTest.expect.equality(messages, string.format("'%s' binary not found", cmd))
		end)
	end)

	describe("load_plugin", function()
		it("returns module when already loaded", function()
			local result = util.load_plugin("memo.utils", "memo.nvim")

			MiniTest.expect.equality(type(result), "table")
		end)

		it("returns module when only import_name is passed", function()
			local result = util.load_plugin("memo.utils")

			MiniTest.expect.equality(type(result), "table")
		end)
	end)
end)
