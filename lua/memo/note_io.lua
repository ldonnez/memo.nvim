local crypto = require("memo.crypto")
local NoteBackup = require("memo.note_backup")
local utils = require("memo.utils")

local M = {}

---Decrypts a note into lines. A missing or empty file has no content and does
---not need to be decrypted. A cancelled prompt returns nil, nil; failures
---return nil and the decryption error.
---@param path string
---@param bufnr integer?
---@return string[]? lines
---@return string? err
function M.read_lines(path, bufnr)
	if not utils.file_has_content(path) then
		return {}
	end

	local result, err = crypto.decrypt_to_stdout(path, bufnr)

	if not result then
		return nil, err
	end

	local output = result.stdout or ""
	local lines = vim.split(output, "\n", { plain = true })

	if output:sub(-1) == "\n" then
		table.remove(lines)
	end

	return lines
end

---Encrypts and writes lines, restoring the original note if anything fails.
---`after` runs before the kept copy is dropped; returning false or raising
---restores the original note instead. Existing files retain their encryption
---mode through gpg.encrypt unless `force_mode` is set.
---@param path string
---@param lines string[]
---@param bufnr integer?
---@param opts? GpgEncryptOpts
---@param after? fun(): boolean, string?
---@return boolean success
---@return string? err
function M.write_lines(path, lines, bufnr, opts, after)
	local backup = NoteBackup.new(path)

	return backup:protect(function()
		local written, err = crypto.encrypt_from_stdin(path, lines, bufnr, opts)

		if not written then
			return false, err
		end

		if after then
			return after()
		end

		return true
	end)
end

---@class MemoNoteInsertOpts
---@field mode? "passphrase"|"key" encryption mode for a missing or empty destination
---@field prepend? boolean Insert before existing content instead of after it
---@field padding? MemoRefilePadding Blank lines around the inserted content
---@field after? fun(): boolean, string? Called after writing, before finalizing the write

---Inserts lines into a note and restores the original if writing or `after`
---fails. A requested encryption mode is used only for a missing or empty note.
---@param path string
---@param lines string[]
---@param bufnr integer?
---@param opts? MemoNoteInsertOpts
---@return boolean success
---@return string? err
function M.insert_lines(path, lines, bufnr, opts)
	opts = opts or {}

	local stat = vim.uv.fs_stat(path)

	if (stat and stat.type ~= "file") or (not stat and vim.fn.getftype(path) ~= "") then
		return false, ("destination is not a regular file: %s"):format(path)
	end

	local existing, err = M.read_lines(path, bufnr)

	if not existing then
		return false, err
	end

	local mode = not utils.file_has_content(path) and opts.mode or nil
	local padding = opts.padding or {}
	local top_padding = padding.top or 0
	local bottom_padding = padding.bottom or 0

	if not opts.prepend and opts.padding and #existing > 0 and #lines > 0 then
		top_padding = math.max(1, top_padding)
	end

	local inserted = {}

	for _ = 1, top_padding do
		inserted[#inserted + 1] = ""
	end

	vim.list_extend(inserted, lines)

	for _ = 1, bottom_padding do
		inserted[#inserted + 1] = ""
	end

	if opts.prepend then
		vim.list_extend(inserted, existing)
		existing = inserted
	else
		vim.list_extend(existing, inserted)
	end

	return M.write_lines(path, existing, bufnr, { mode = mode }, opts.after)
end

return M
