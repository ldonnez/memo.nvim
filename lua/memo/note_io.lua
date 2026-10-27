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

return M
