local child = MiniTest.new_child_neovim()

describe("capture_template", function()
	before_each(function()
		child.restart({ "-u", "scripts/minimal_init.lua" })
		-- Load tested plugin
		child.lua([[M = require('memo.capture_template')]])
	end)

	after_each(function()
		child.stop()
	end)

	describe("resolve", function()
		it("resolves basic templates and markers", function()
			local config = { template = "## Title\n|" }
			local capture_template = require("memo.capture_template")
			local lines, cursor = capture_template.resolve(config)

			MiniTest.expect.equality(lines, { "## Title", "" })
			MiniTest.expect.equality(cursor, { 2, 0 })
		end)

		it("sets default template with empty config", function()
			local config = {}
			local capture_template = require("memo.capture_template")
			local lines, cursor = capture_template.resolve(config)

			MiniTest.expect.equality(lines, { "" })
			MiniTest.expect.equality(cursor, { 1, 0 })
		end)

		it("sets empty string when tempale is empty", function()
			local config = { template = "" }
			local capture_template = require("memo.capture_template")
			local lines, cursor = capture_template.resolve(config)

			MiniTest.expect.equality(lines, { "" })
			MiniTest.expect.equality(cursor, { 1, 0 })
		end)

		it("places cursor correctly with empty spaces in template", function()
			local capture_template = require("memo.capture_template")
			local opts = { template = "- [ ] |" }
			local lines, pos = capture_template.resolve(opts)

			MiniTest.expect.equality(lines[1], "- [ ] ")
			MiniTest.expect.equality(pos[2], 6)
		end)
	end)

	describe("merge", function()
		it("injects content under a specific target header with prepended newline (default)", function()
			local existing = { "# Inbox", "", "Previous Note" }
			local new_lines = { "## 2024-01-01", "New Content" }
			local config = { target_header = "# Inbox" }
			local capture_template = require("memo.capture_template")

			local result = capture_template.merge(existing, new_lines, config)

			MiniTest.expect.equality(result[1], "# Inbox")
			MiniTest.expect.equality(result[2], "## 2024-01-01")
			MiniTest.expect.equality(result[3], "New Content")
			MiniTest.expect.equality(result[4], "Previous Note")
			MiniTest.expect.equality(result[5], nil)
		end)

		it("ignores partial matches for target_header", function()
			local existing = { "# Inbox is here", "", "Previous Note" }
			local new_lines = { "## 2024-01-01", "New Content" }
			local config = { target_header = "# Inbox" }
			local capture_template = require("memo.capture_template")

			local result = capture_template.merge(existing, new_lines, config)

			MiniTest.expect.equality(result[1], "# Inbox")
			MiniTest.expect.equality(result[2], "## 2024-01-01")
			MiniTest.expect.equality(result[3], "New Content")
			MiniTest.expect.equality(result[4], "")
			MiniTest.expect.equality(result[5], "# Inbox is here")
			MiniTest.expect.equality(result[6], "")
			MiniTest.expect.equality(result[7], "Previous Note")
			MiniTest.expect.equality(result[8], nil)
		end)

		it("prepends to first header if duplicate target header exists", function()
			local existing = { "# Inbox", "", "Second Note", "# Inbox", "", "First Note" }
			local new_lines = { "New Content" }
			local config = { target_header = "# Inbox" }
			local capture_template = require("memo.capture_template")

			local result = capture_template.merge(existing, new_lines, config)

			MiniTest.expect.equality(result[1], "# Inbox")
			MiniTest.expect.equality(result[2], "New Content")
			MiniTest.expect.equality(result[3], "Second Note")
			MiniTest.expect.equality(result[4], "# Inbox")
			MiniTest.expect.equality(result[6], "First Note")
			MiniTest.expect.equality(result[7], nil)
		end)

		it("injects content under a specific target header with 2 new lines", function()
			local existing = { "# Inbox", "", "Previous Note" }
			local new_lines = { "## 2024-01-01", "New Content" }
			local config = { target_header = "# Inbox", header_padding = 2 }
			local capture_template = require("memo.capture_template")

			local result = capture_template.merge(existing, new_lines, config)

			MiniTest.expect.equality(result[1], "# Inbox")
			MiniTest.expect.equality(result[2], "")
			MiniTest.expect.equality(result[3], "")
			MiniTest.expect.equality(result[4], "## 2024-01-01")
			MiniTest.expect.equality(result[5], "New Content")
			MiniTest.expect.equality(result[6], "Previous Note")
			MiniTest.expect.equality(result[7], nil)
		end)

		it("prepends target header if it does not exist in empty file", function()
			local existing = {}
			local new_lines = { "New Content" }
			local config = { target_header = "# Inbox" }
			local capture_template = require("memo.capture_template")

			local result = capture_template.merge(existing, new_lines, config)

			MiniTest.expect.equality(result[1], "# Inbox")
			MiniTest.expect.equality(result[2], "New Content")
			MiniTest.expect.equality(result[3], nil)
		end)

		it("prepends target header if it does not exist in existing file", function()
			local existing = { "# test", "existing content" }
			local new_lines = { "New Content" }
			local config = { target_header = "# Inbox" }
			local capture_template = require("memo.capture_template")

			local result = capture_template.merge(existing, new_lines, config)

			MiniTest.expect.equality(result[1], "# Inbox")
			MiniTest.expect.equality(result[2], "New Content")
			MiniTest.expect.equality(result[3], "")
			MiniTest.expect.equality(result[4], "# test")
			MiniTest.expect.equality(result[5], "existing content")
			MiniTest.expect.equality(result[6], nil)
		end)

		it("injects content under a specific target header with no extra new lines", function()
			local existing = { "# Inbox", "", "Previous Note" }
			local new_lines = { "## 2024-01-01", "New Content" }
			local config = { target_header = "# Inbox", header_padding = 0 }
			local capture_template = require("memo.capture_template")

			local result = capture_template.merge(existing, new_lines, config)

			MiniTest.expect.equality(result[1], "# Inbox")
			MiniTest.expect.equality(result[2], "## 2024-01-01")
			MiniTest.expect.equality(result[3], "New Content")
			MiniTest.expect.equality(result[4], "Previous Note")
			MiniTest.expect.equality(result[5], nil)
		end)

		it("injects content at top of file without target header in config", function()
			local existing = { "# Inbox", "", "Previous Note" }
			local new_lines = { "New Content" }
			local config = {}
			local capture_template = require("memo.capture_template")

			local result = capture_template.merge(existing, new_lines, config)

			MiniTest.expect.equality(result[1], "New Content")
			MiniTest.expect.equality(result[2], "# Inbox")
			MiniTest.expect.equality(result[3], "")
			MiniTest.expect.equality(result[4], "Previous Note")
			MiniTest.expect.equality(result[5], nil)
		end)
	end)
end)
