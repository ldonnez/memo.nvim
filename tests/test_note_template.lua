describe("note_template", function()
	local Template = require("memo.note_template")

	describe("resolve_template", function()
		it("resolves basic templates and markers", function()
			local config = { template = "## Title\n|" }
			local note_template = Template.new(config)
			local lines, cursor = note_template:resolve_template()

			MiniTest.expect.equality(lines, { "## Title", "" })
			MiniTest.expect.equality(cursor, { 2, 0 })
		end)

		it("sets default template with empty config", function()
			local config = {}
			local note_template = Template.new(config)
			local lines, cursor = note_template:resolve_template()

			MiniTest.expect.equality(lines, { "" })
			MiniTest.expect.equality(cursor, { 1, 0 })
		end)

		it("sets empty string when tempale is empty", function()
			local config = { template = "" }
			local note_template = Template.new(config)
			local lines, cursor = note_template:resolve_template()

			MiniTest.expect.equality(lines, { "" })
			MiniTest.expect.equality(cursor, { 1, 0 })
		end)

		it("places cursor correctly with empty spaces in template", function()
			local config = { template = "- [ ] |" }
			local note_template = Template.new(config)
			local lines, pos = note_template:resolve_template()

			MiniTest.expect.equality(lines[1], "- [ ] ")
			MiniTest.expect.equality(pos[2], 6)
		end)
	end)
end)
