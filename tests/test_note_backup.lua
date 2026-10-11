local helpers = require("tests.helpers")

describe("note_backup", function()
	local NoteBackup = require("memo.note_backup")
	local dir = ""

	before_each(function()
		dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
	end)

	after_each(function()
		vim.fn.delete(dir, "rf")
	end)

	local function path(name)
		return dir .. "/" .. name
	end

	--- @param file string
	--- @return string[]
	local function read(file)
		return vim.fn.readfile(file)
	end

	describe("save", function()
		it("keeps a copy of the note next to it", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			local saved = backup:save()
			local kept = backup.backup_path --[[@as string]]

			MiniTest.expect.equality(saved, true)
			MiniTest.expect.equality(vim.fn.filereadable(kept), 1)
			MiniTest.expect.equality(read(kept), read(note))
			MiniTest.expect.equality(vim.fn.fnamemodify(kept, ":h"), dir)
		end)

		it("keeps the note extension on the copy", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			backup:save()
			local kept = backup.backup_path --[[@as string]]

			MiniTest.expect.equality(kept:sub(-4), ".asc")
		end)

		it("keeps the other note extension on the copy", function()
			local note = path("note.md.gpg")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			backup:save()
			local kept = backup.backup_path --[[@as string]]

			MiniTest.expect.equality(kept:sub(-4), ".gpg")
		end)

		it("backs up an empty note", function()
			local note = path("empty.md.asc")
			helpers.write_file(note, "")

			local backup = NoteBackup.new(note)
			backup:save()
			local kept = backup.backup_path --[[@as string]]

			MiniTest.expect.equality(vim.fn.filereadable(kept), 1)
		end)

		it("does nothing for a missing note", function()
			local backup = NoteBackup.new(path("missing.md.asc"))

			MiniTest.expect.equality(backup:save(), false)
			MiniTest.expect.equality(backup.backup_path, nil)
		end)

		it("gives each backup its own path", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local first = NoteBackup.new(note)
			local second = NoteBackup.new(note)
			first:save()
			second:save()

			MiniTest.expect.equality(first.backup_path ~= second.backup_path, true)
		end)
	end)

	describe("restore", function()
		it("puts the original back over a changed note", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			backup:save()

			helpers.write_file(note, "replacement body\n")
			local restored = backup:restore()

			MiniTest.expect.equality(restored, true)
			MiniTest.expect.equality(read(note), { "original body" })
			MiniTest.expect.equality(backup.backup_path, nil)
		end)

		it("puts the original back when the replacement removed the note", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			backup:save()
			vim.fn.delete(note)

			MiniTest.expect.equality(backup:restore(), true)
			MiniTest.expect.equality(vim.fn.filereadable(note), 1)
			MiniTest.expect.equality(read(note), { "original body" })
		end)

		it("does nothing without a saved note", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "current body\n")

			local backup = NoteBackup.new(note)

			MiniTest.expect.equality(backup:restore(), false)
			MiniTest.expect.equality(read(note), { "current body" })
		end)

		it("can be safely called multiple times (idempotent)", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			backup:save()
			helpers.write_file(note, "replacement body\n")

			-- First restore succeeds
			MiniTest.expect.equality(backup:restore(), true)

			-- Second restore returns false safely without crashing or throwing
			MiniTest.expect.equality(backup:restore(), false)
			MiniTest.expect.equality(read(note), { "original body" })
		end)
	end)

	describe("discard", function()
		it("drops the copy and keeps the replacement", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			backup:save()
			local kept = backup.backup_path --[[@as string]]

			helpers.write_file(note, "replacement body\n")
			backup:discard()

			MiniTest.expect.equality(vim.fn.filereadable(kept), 0)
			MiniTest.expect.equality(read(note), { "replacement body" })
			--- @diagnostic disable-next-line: preferred-local-alias
			MiniTest.expect.equality(backup.backup_path, nil)
		end)

		it("does nothing without a saved note", function()
			local backup = NoteBackup.new(path("note.md.asc"))

			backup:discard()

			MiniTest.expect.equality(backup.backup_path, nil)
		end)

		it("can be safely called multiple times (idempotent)", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			backup:save()

			-- First discard succeeds
			MiniTest.expect.equality(backup:discard(), true)

			-- Second discard returns true safely (since backup_path is already nil)
			MiniTest.expect.equality(backup:discard(), true)
		end)
	end)
end)
