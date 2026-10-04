local child = MiniTest.new_child_neovim()

local function setup_child()
	child.restart({ "-u", "scripts/minimal_init.lua" })
	child.lua([[M = require("memo.config")]])
end

describe("config", function()
	teardown(function()
		child.stop()
	end)

	describe("notes_dir", function()
		before_each(function()
			setup_child()
		end)

		it("defaults to the home notes dir", function()
			local result = child.lua_get("M.notes_dir")

			MiniTest.expect.equality(result, vim.fn.expand("~/notes"))
		end)

		it("uses vim.g.memo_notes_dir when set", function()
			child.lua([[
      vim.g.memo_notes_dir = "/tmp/memo-custom-notes"
    	M.setup()
      ]])

			local result = child.lua_get("M.notes_dir")

			MiniTest.expect.equality(result, "/tmp/memo-custom-notes")
		end)
	end)

	describe("scratch_dir", function()
		before_each(function()
			setup_child()
		end)

		it("defaults to the nvim data dir", function()
			local result = child.lua_get("M.scratch_dir")

			MiniTest.expect.equality(result, vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "memo-scratch"))
		end)

		it("uses vim.g.memo_scratch_dir when set", function()
			child.lua([[
        vim.g.memo_scratch_dir = "/tmp/memo-scratch"
        M.setup()
      ]])

			local result = child.lua_get("M.scratch_dir")

			MiniTest.expect.equality(result, "/tmp/memo-scratch")
		end)
	end)

	describe("capture_file", function()
		before_each(function()
			setup_child()
		end)

		it("defaults to the inbox", function()
			local result = child.lua_get("M.capture_file")

			MiniTest.expect.equality(result, "inbox.md.asc")
		end)

		it("uses vim.g.memo_default_capture_file when set", function()
			child.lua([[
        vim.g.memo_default_capture_file = "quick/inbox.asc"
       	M.setup()
      ]])

			local result = child.lua_get("M.capture_file")

			MiniTest.expect.equality(result, "quick/inbox.asc")
		end)
	end)

	describe("extension", function()
		before_each(function()
			setup_child()
		end)

		it("defaults to asc", function()
			local result = child.lua_get("M.extension")

			MiniTest.expect.equality(result, "asc")
		end)

		it("uses vim.g.memo_extension when set", function()
			child.lua([[
        vim.g.memo_extension = "gpg"
       	M.setup()
      ]])

			local result = child.lua_get("M.extension")

			MiniTest.expect.equality(result, "gpg")
		end)
	end)

	describe("supported_extensions", function()
		before_each(function()
			setup_child()
		end)

		it("reads both asc and gpg notes", function()
			local result = child.lua_get("M.supported_extensions")

			MiniTest.expect.equality(result, { "asc", "gpg" })
		end)

		it("reads the extension new notes are written with", function()
			child.lua([[
        vim.g.memo_extension = "pgp"
        M.setup()
      ]])

			local result = child.lua_get("M.supported_extensions")

			MiniTest.expect.equality(result, { "asc", "gpg", "pgp" })
		end)

		it("does not repeat an extension it already reads", function()
			child.lua([[
        vim.g.memo_extension = "gpg"
        M.setup()
      ]])

			local result = child.lua_get("M.supported_extensions")

			MiniTest.expect.equality(result, { "asc", "gpg" })
		end)
	end)

	describe("ignore_patterns", function()
		before_each(function()
			setup_child()
		end)

		it("contains default ignore patterns", function()
			local result = child.lua_get("M.ignore_patterns")

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
        M.setup()
			]])

			local result = child.lua_get("M.ignore_patterns")

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
