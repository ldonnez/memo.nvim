local helpers = require("tests.helpers")

--- @diagnostic disable: access-invisible

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

		it("has nothing to keep for a missing note", function()
			local backup = NoteBackup.new(path("missing.md.asc"))

			MiniTest.expect.equality(backup:save(), true)
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

	describe("protect", function()
		it("removes the note, runs the action and drops the copy", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			local kept ---@type string
			local removed ---@type boolean

			local success, err = backup:protect(function()
				kept = backup.backup_path --[[@as string]]
				removed = vim.fn.filereadable(note) == 0
				helpers.write_file(note, "replacement body\n")
				return true
			end)

			MiniTest.expect.equality(success, true)
			MiniTest.expect.equality(err, nil)
			MiniTest.expect.equality(removed, true)
			MiniTest.expect.equality(vim.fn.filereadable(kept), 0)
			MiniTest.expect.equality(read(note), { "replacement body" })
		end)

		it("puts the original back when the action fails", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			local success, err = backup:protect(function()
				return false, "encryption failed"
			end)

			MiniTest.expect.equality(success, false)
			MiniTest.expect.equality(err, "encryption failed")
			MiniTest.expect.equality(read(note), { "original body" })
			MiniTest.expect.equality(backup.backup_path, nil)
		end)

		it("puts the original back when the action raises", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			local ok, err = pcall(function()
				backup:protect(function()
					error("boom")
				end)
			end)

			MiniTest.expect.equality(ok, false)
			MiniTest.expect.equality(tostring(err):find("boom") ~= nil, true)
			MiniTest.expect.equality(read(note), { "original body" })
		end)

		it("keeps the note and drops the copy when it cannot be removed", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			backup:save()
			local kept = backup.backup_path --[[@as string]]

			-- A directory cannot be removed by the plain delete protect uses.
			vim.fn.delete(note)
			vim.fn.mkdir(note, "p")

			local success, err = backup:protect(function()
				error("should not run")
			end)

			MiniTest.expect.equality(success, false)
			MiniTest.expect.equality(err, ("could not remove existing note (%s)"):format(note))
			MiniTest.expect.equality(vim.fn.isdirectory(note), 1)
			MiniTest.expect.equality(vim.fn.filereadable(kept), 0)
		end)

		it("reports a failed recovery in place of the operation's error", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			backup.restore = function()
				return false
			end

			local success, err = backup:protect(function()
				return false, "encryption failed"
			end)

			MiniTest.expect.equality(success, false)
			MiniTest.expect.equality(err, "the replacement failed and the original could not be restored")
		end)

		it("keeps the original exception when the recovery fails", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "original body\n")

			local backup = NoteBackup.new(note)
			backup.restore = function()
				return false
			end

			local ok, err = pcall(function()
				backup:protect(function()
					error("boom")
				end)
			end)

			MiniTest.expect.equality(ok, false)
			MiniTest.expect.equality(tostring(err):find("boom") ~= nil, true)
			MiniTest.expect.equality(tostring(err):find("could not be restored") ~= nil, true)
		end)

		it("removes a partial new file when the action raises", function()
			local note = path("new.md.asc")
			local backup = NoteBackup.new(note)

			local ok = pcall(function()
				backup:protect(function()
					helpers.write_file(note, "partial body\\n")
					error("boom")
				end)
			end)

			MiniTest.expect.equality(ok, false)
			MiniTest.expect.equality(vim.fn.filereadable(note), 0)
		end)

		it("runs the action when there is nothing to keep", function()
			local note = path("note.md.asc")

			local backup = NoteBackup.new(note)

			local success = backup:protect(function()
				helpers.write_file(note, "fresh body\n")
				return true
			end)

			MiniTest.expect.equality(success, true)
			MiniTest.expect.equality(read(note), { "fresh body" })
		end)
	end)
end)
