local message = require("memo.message")
local utils = require("memo.utils")

local M = {}

---A note backed up while a replacement is prepared.
---The copy lives next to the note and keeps the note extension.
---@class MemoNoteBackup
---@field path string the note being replaced
---@field backup_path? string where the note is saved, nil until `save` runs
local NoteBackup = {}

NoteBackup.__index = NoteBackup

---The sibling path the note is kept at, built from the note's own name and a
---timestamp so the extension is preserved and the backup is unique
---(e.g. "note.md.asc" -> "note.md.memo-backup-1728657133456789.asc").
---@param path string
---@return string
local function backup_path_for(path)
	local stem = utils.strip_extension(path)
	local extension = utils.get_extension(path)
	local timestamp = tostring(vim.uv.hrtime())

	if extension then
		return ("%s.memo-backup-%s.%s"):format(stem, timestamp, extension)
	end

	return ("%s.memo-backup-%s"):format(stem, timestamp)
end

---@param path string the note to protect while it is replaced
---@return MemoNoteBackup
function M.new(path)
	local self = setmetatable({}, NoteBackup)

	self.path = path
	self.backup_path = nil

	return self
end

---Copies the note. A note that is not on disk has nothing to keep, so
---this reports `false` rather than creating an empty backup.
---@return boolean saved
function NoteBackup:save()
	if not utils.file_exists(self.path) then
		return false
	end

	local target = backup_path_for(self.path)

	if not vim.uv.fs_copyfile(self.path, target) then
		-- A partial target can be left behind; drop it so it is not mistaken
		-- for a note. The original is still in place at this point.
		if utils.file_exists(target) and vim.fn.delete(target) ~= 0 then
			message.warn("Memo: could not remove incomplete backup %s", target)
		end

		message.error("Memo: could not back up %s", self.path)
		return false
	end

	self.backup_path = target

	return true
end

---Puts the kept note back over `path`, dropping whatever the replacement left
---there. A partial replacement is removed first so the restore always lands
---the original bytes. Reports `false` when there is nothing to restore.
---@return boolean restored
function NoteBackup:restore()
	if not self.backup_path then
		return false
	end

	-- The rename cannot land while the replacement is still there, so a failed
	-- removal is reported before it is attempted: the original is intact at the
	-- backup path.
	if utils.file_exists(self.path) and vim.fn.delete(self.path) ~= 0 then
		message.error("Memo: could not remove replacement; original remains at %s", self.backup_path)
		return false
	end

	if not vim.uv.fs_rename(self.backup_path, self.path) then
		message.error("Memo: could not restore %s; original remains at %s", self.path, self.backup_path)
		return false
	end

	self.backup_path = nil

	return true
end

---Drops the kept note once the replacement is in place. Reports `false` and
---keeps the path when the copy cannot be removed.
---@return boolean discarded
function NoteBackup:discard()
	if not self.backup_path then
		return true
	end

	if utils.file_exists(self.backup_path) and vim.fn.delete(self.backup_path) ~= 0 then
		message.warn("Memo: could not remove backup %s", self.backup_path)
		return false
	end

	self.backup_path = nil

	return true
end

return M
