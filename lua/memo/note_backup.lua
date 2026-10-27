local message = require("memo.message")
local utils = require("memo.utils")

local M = {}

---@param reason string
---@param err string?
---@return string
local function with_error(reason, err)
	return err and ("%s: %s"):format(reason, err) or reason
end

---A note backed up while a replacement is prepared.
---The copy lives next to the note and keeps the note extension.
---@class MemoNoteBackup
---@field path string the note being replaced
---@field backup_path? string the kept copy, nil before `protect` or after it finishes
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

	-- UV_FS_COPYFILE_EXCL (1) fails if the destination already exists.
	-- Do not remove the target on failure: it may be a pre-existing file that
	-- caused the exclusive copy to fail.
	if not vim.uv.fs_copyfile(self.path, target, 1) then
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
---@return string? err
function NoteBackup:restore()
	if not self.backup_path then
		return false, "there is no backup to restore"
	end

	if not vim.uv.fs_rename(self.backup_path, self.path) then
		return false, ("the original remains at %s"):format(self.backup_path)
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
		return false
	end

	self.backup_path = nil

	return true
end

---Runs `action` while the note is kept. A failure puts the original back before
---being returned; a raise puts it back before being re-raised. On success the
---kept note stays for the caller to commit or roll back.
---@private
---@param action fun(): boolean, string?
---@return boolean success
---@return string? err
function NoteBackup:run(action)
	local ok, result, err = pcall(action)

	if not ok then
		-- A raise shifts the action's return values, so `result` is the error
		-- value here and `err` is nil.
		if self.backup_path then
			local restored, restore_err = self:restore()

			if not restored then
				error(
					with_error(
						("the replacement raised %s and the original could not be restored"):format(tostring(result)),
						restore_err
					),
					0
				)
			end
		elseif utils.file_exists(self.path) and vim.fn.delete(self.path) ~= 0 then
			error(("the replacement raised %s and its partial file could not be removed"):format(tostring(result)), 0)
		end

		error(result, 0)
	end

	if not result then
		if self.backup_path then
			local restored, restore_err = self:restore()

			if not restored then
				return false,
					with_error(
						("the replacement failed (%s) and the original could not be restored"):format(
							err or "unknown error"
						),
						restore_err
					)
			end
		elseif utils.file_exists(self.path) and vim.fn.delete(self.path) ~= 0 then
			return false, err or ("could not remove partial file (%s)"):format(self.path)
		end

		return false, err
	end

	return true
end

---Keeps a copy of the note while `action` replaces it. `action` returns the
---same `success, err` pair as the write it performs: an ordinary failure puts
---the original back before the failure is returned, an exception puts it back
---before being re-raised, and a success drops the kept copy. A recovery that
---itself fails is reported in place of the operation's own error. Reports
---`false` when the note cannot be kept.
---@param action fun(): boolean, string?
---@return boolean success
---@return string? err
function NoteBackup:protect(action)
	if not self:save() then
		return false
	end

	local success, err = self:run(action)

	if not success then
		return false, err
	end

	if not self:discard() then
		message.warn("Memo: note was written but its backup could not be removed: %s", self.backup_path)
		return true, "note was written but its backup could not be removed"
	end

	return true
end

return M
