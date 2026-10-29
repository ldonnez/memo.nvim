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
---@field prepend? boolean Insert before existing content instead of after it
---@field padding? MemoRefilePadding Blank lines around the inserted content
---@field mode? "key"|"passphrase" Encryption mode for a missing or empty destination
---@field target_header? string Insert below this exact header, creating it when missing
---@field after? fun(): boolean, string? Called after writing, before finalizing the write

---@param lines string[]
---@param count integer
---@param from_start boolean
---@return integer
local function missing_padding(lines, count, from_start)
	local existing = 0
	local index = from_start and 1 or #lines
	local step = from_start and 1 or -1

	while lines[index] == "" do
		existing = existing + 1
		index = index + step
	end

	return math.max(0, count - existing)
end

---@param target string[]
---@param count integer
local function append_blank_lines(target, count)
	for _ = 1, count do
		table.insert(target, "")
	end
end

---Inserts lines into a note, preserving the existing encryption mode and
---restoring the original if writing or the follow-up callback fails.
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
	local target_header = opts.target_header or ""
	local has_target_header = target_header ~= ""
	local merged = {}
	local header_idx

	if has_target_header then
		for i, line in ipairs(existing) do
			if line == target_header then
				header_idx = i
				break
			end
		end
	end

	local block = {}

	if has_target_header and not header_idx then
		table.insert(block, target_header)
	end

	if has_target_header then
		append_blank_lines(block, missing_padding(lines, padding.top or 0, true))
	end

	vim.list_extend(block, lines)
	append_blank_lines(block, missing_padding(lines, padding.bottom or 0, false))

	if header_idx then
		vim.list_extend(merged, vim.list_slice(existing, 1, header_idx))
		vim.list_extend(merged, block)
		local remaining = vim.list_slice(existing, header_idx + 1)

		if
			#lines > 0
			and #remaining > 0
			and remaining[1] ~= ""
			and lines[#lines] ~= ""
			and (padding.bottom or 0) == 0
		then
			table.insert(merged, "")
		end

		vim.list_extend(merged, remaining)
	elseif has_target_header then
		if #existing > 0 and #lines > 0 and lines[#lines] ~= "" and (padding.bottom or 0) == 0 then
			table.insert(block, "")
		end

		vim.list_extend(merged, block)
		vim.list_extend(merged, existing)
	elseif opts.prepend then
		append_blank_lines(merged, missing_padding(lines, padding.top or 0, true))
		vim.list_extend(merged, lines)

		local bottom_padding = math.floor(
			math.max(
				missing_padding(lines, padding.bottom or 0, false),
				#existing > 0 and #lines > 0 and 1 - (#lines[#lines] == "" and 1 or 0) - (existing[1] == "" and 1 or 0)
					or 0
			)
		)

		append_blank_lines(merged, bottom_padding)
		vim.list_extend(merged, existing)
	else
		local top_padding = math.floor(
			math.max(
				missing_padding(lines, padding.top or 0, true),
				#existing > 0
						and #lines > 0
						and 1 - (existing[#existing] == "" and 1 or 0) - (#lines[1] == "" and 1 or 0)
					or 0
			)
		)

		vim.list_extend(merged, existing)
		append_blank_lines(merged, top_padding)
		vim.list_extend(merged, lines)
		append_blank_lines(merged, missing_padding(lines, padding.bottom or 0, false))
	end

	return M.write_lines(path, merged, bufnr, { mode = mode }, opts.after)
end

return M
