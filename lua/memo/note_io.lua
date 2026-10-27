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

---Runs an operation while keeping an existing note recoverable if it fails.
---The operation writes directly to the destination and returns the same
---success, error pair as a note write.
---@param path string
---@param action fun(): boolean, string?
---@return boolean success
---@return string? err
function M.protect(path, action)
	return NoteBackup.new(path):protect(action)
end

---Encrypts and writes lines, restoring the original note if the write fails.
---Resolve the encryption mode before calling this function when it depends on
---the existing file, since the write may change its contents.
---@param path string
---@param lines string[]
---@param bufnr integer?
---@param opts? GpgEncryptOpts
---@return boolean success
---@return string? err
function M.write_lines(path, lines, bufnr, opts)
	return M.protect(path, function()
		return crypto.encrypt_from_stdin(path, lines, bufnr, opts)
	end)
end

return M
