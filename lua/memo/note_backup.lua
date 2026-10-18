local message = require("memo.message")
local utils = require("memo.utils")

local M = {}

---A note backed up while a replacement is prepared.
---The copy lives next to the note and keeps the note extension.
---@class MemoNoteBackup
---@field path string the note being replaced
---@field backup_path? string where the note is saved, nil until `protect` runs
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

---Keeps a copy of the note so a replacement can be undone. A note that is not
---on disk has nothing to keep, which is not a failure. Reports `false` only
---when a note exists and its copy cannot be made.
---@private
---@return boolean ready
function NoteBackup:save()
	if not utils.file_exists(self.path) then
		return true
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

---Puts the kept note back over `path`, replacing whatever the replacement left
---there. The rename replaces an existing destination on every supported
---platform (POSIX `rename`, Windows `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING`),
---so the original is never missing between steps. Reports `false` when there is
---nothing to restore or the rename cannot land.
---@private
---@return boolean restored
function NoteBackup:restore()
	if not self.backup_path then
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
---@private
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

---Keeps the note, removes it, then runs `action` in its place, so the
---destructive part of a replacement can raise without leaving the note
---missing. Removing the note first is also what makes a passphrase-protected
---overwrite use the fresh-note confirmation flow. `action` returns the same
---`success, err` pair as the write it performs: an ordinary failure puts the
---original back before the failure is returned, an exception puts it back
---before being re-raised, and a success drops the kept copy. A recovery that
---itself fails is reported in place of the operation's own error, which
---`restore` has already logged. Reports `false` when the note cannot be kept
---or removed.
---@param action fun(): boolean, string?
---@return boolean success
---@return string? err
function NoteBackup:protect(action)
	if not self:save() then
		return false
	end

	if self.backup_path and vim.fn.delete(self.path) ~= 0 then
		-- The note is still on disk, so the kept copy is redundant.
		self:discard()
		return false, ("could not remove existing note (%s)"):format(self.path)
	end

	local ok, result, err = pcall(action)

	if not ok then
		-- A raise shifts the action's return values, so `result` is the error
		-- value here and `err` is nil.
		if self.backup_path and not self:restore() then
			error(("the replacement raised %s and the original could not be restored"):format(tostring(result)), 0)
		end

		error(result, 0)
	end

	if not result then
		if self.backup_path and not self:restore() then
			return false, "the replacement failed and the original could not be restored"
		end

		return false, err
	end

	self:discard()

	return true
end

return M
