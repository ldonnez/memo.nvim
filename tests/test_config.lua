local child = MiniTest.new_child_neovim()

describe("config", function()
	setup(function()
		child.restart({ "-u", "scripts/minimal_init.lua" })

		-- Load tested plugin
		child.lua([[M = require("memo.config")]])
	end)

	teardown(function()
		child.stop()
	end)

	describe("notes_dir", function()
		it("defaults to the home notes dir", function()
			local result = child.lua_get("M.notes_dir()")

			MiniTest.expect.equality(result, vim.fn.expand("~/notes"))
		end)

		it("uses vim.g.memo_notes_dir when set", function()
			child.lua([[
				vim.g.memo_notes_dir = "/tmp/memo-custom-notes"
			]])

			local result = child.lua_get("M.notes_dir()")

			MiniTest.expect.equality(result, "/tmp/memo-custom-notes")
		end)
	end)

	describe("scratch_dir", function()
		it("defaults to the nvim data dir", function()
			local result = child.lua_get("M.scratch_dir()")

			MiniTest.expect.equality(result, vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "memo-scratch"))
		end)

		it("uses vim.g.memo_scratch_dir when set", function()
			child.lua([[
				vim.g.memo_scratch_dir = "/tmp/memo-scratch"
			]])

			local result = child.lua_get("M.scratch_dir()")

			MiniTest.expect.equality(result, "/tmp/memo-scratch")
		end)
	end)

	describe("ignore_patterns", function()
		it("contains default ignore patterns", function()
			local result = child.lua_get("M.ignore_patterns()")

			MiniTest.expect.equality(result, {
				"**/.git/**",
				"**/.githooks/**",
				"**/.gitignore",
				"**/.gitattributes",
				"**/.gitmodules",
				"**/.ignore",
			})
		end)

		it("merges vim.g.memo_ignore_patterns with defaults", function()
			child.lua([[
				vim.g.memo_ignore_patterns = {
					"**/.env",
					"**/tmp/**",
				}
			]])

			local result = child.lua_get("M.ignore_patterns()")

			MiniTest.expect.equality(result, {
				"**/.git/**",
				"**/.githooks/**",
				"**/.gitignore",
				"**/.gitattributes",
				"**/.gitmodules",
				"**/.ignore",
				"**/.env",
				"**/tmp/**",
			})
		end)
	end)
end)
