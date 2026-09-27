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
			MiniTest.expect.equality(pos, { 1, 6 })
		end)
	end)

	describe("insert_at_cursor", function()
		it("inserts a single line where the marker was", function()
			local note_template = Template.new({ template = "## Agenda\n- |" })
			local lines, cursor = note_template:insert_at_cursor({ "todo item" })

			MiniTest.expect.equality(lines, { "## Agenda", "- todo item" })
			MiniTest.expect.equality(cursor, { 2, 11 })
		end)

		it("keeps the text that follows the marker on the same line", function()
			local note_template = Template.new({ template = "## Agenda\n- | tail" })
			local lines, cursor = note_template:insert_at_cursor({ "todo item" })

			MiniTest.expect.equality(lines, { "## Agenda", "- todo item tail" })
			MiniTest.expect.equality(cursor, { 2, 11 })
		end)

		it("starts a new line after multi-line content", function()
			local note_template = Template.new({ template = "## Agenda\n- | tail" })
			local lines, cursor = note_template:insert_at_cursor({ "first", "second" })

			MiniTest.expect.equality(lines, { "## Agenda", "- first", "second", " tail" })
			MiniTest.expect.equality(cursor, { 3, 6 })
		end)

		it("inserts multi-line content on consecutive rows", function()
			local note_template = Template.new({ template = "## Agenda\n- |" })
			local lines, cursor = note_template:insert_at_cursor({ "first", "second", "third" })

			MiniTest.expect.equality(lines, { "## Agenda", "- first", "second", "third" })
			MiniTest.expect.equality(cursor, { 4, 5 })
		end)

		it("inserts into the middle of a multi-line template", function()
			local note_template = Template.new({ template = "before |\nafter" })
			local lines, cursor = note_template:insert_at_cursor({ "content" })

			MiniTest.expect.equality(lines, { "before content", "after" })
			MiniTest.expect.equality(cursor, { 1, 14 })
		end)

		it("returns the template unchanged without content", function()
			local note_template = Template.new({ template = "## Agenda\n- |" })
			local lines, cursor = note_template:insert_at_cursor({})

			MiniTest.expect.equality(lines, { "## Agenda", "- " })
			MiniTest.expect.equality(cursor, { 2, 2 })
		end)

		it("returns the template unchanged when it has no marker", function()
			local note_template = Template.new({ template = "## Agenda" })
			local lines, cursor = note_template:insert_at_cursor({ "todo item" })

			MiniTest.expect.equality(lines, { "## Agenda" })
			MiniTest.expect.equality(cursor, { 1, 0 })
		end)

		it("leaves the resolved template of the instance untouched", function()
			local note_template = Template.new({ template = "## Agenda\n- |" })
			note_template:insert_at_cursor({ "todo item" })

			local lines, cursor = note_template:resolve_template()
			MiniTest.expect.equality(lines, { "## Agenda", "- " })
			MiniTest.expect.equality(cursor, { 2, 2 })
		end)
	end)
end)
