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

---@class MemoRefilePadding
---@field top? integer blank lines before the inserted content
---@field bottom? integer blank lines after the inserted content

---@class MemoNoteInsertOpts
---@field prepend? boolean Insert before existing content instead of after it
---@field padding? MemoRefilePadding Blank lines around the inserted content
---@field mode? "key"|"passphrase" Encryption mode for a missing or empty destination
---@field target_header? string Insert below this exact header, creating it when missing
---@field after? fun(): boolean, string? Called after writing, before finalizing the write

---@param lines string[]
---@param from_start boolean
---@return integer
local function edge_blank_count(lines, from_start)
	local count = 0
	local index = from_start and 1 or #lines
	local step = from_start and 1 or -1

	while lines[index] == "" do
		count = count + 1
		index = index + step
	end

	return count
end

---@param lines string[]
---@param count integer
---@param from_start boolean
---@return integer
local function missing_padding(lines, count, from_start)
	return math.max(0, count - edge_blank_count(lines, from_start))
end

---Blank lines needed between two adjacent blocks, so they stay separated.
---@param existing string[]
---@param inserted string[]
---@param existing_before boolean true when the existing content comes first
---@return integer
local function separator_padding(existing, inserted, existing_before)
	local existing_edge = edge_blank_count(existing, not existing_before)
	local inserted_edge = edge_blank_count(inserted, existing_before)

	return math.max(0, 1 - existing_edge - inserted_edge)
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

	if #lines == 0 then
		return true
	end

	local stat = vim.uv.fs_stat(path)

	if (stat and stat.type ~= "file") or (not stat and vim.fn.getftype(path) ~= "") then
		return false, ("destination is not a regular file: %s"):format(path)
	end

	local existing, err = M.read_lines(path, bufnr)

	if not existing then
		return false, err
	end

	local has_content = stat ~= nil and stat.type == "file" and stat.size > 0
	local mode = not has_content and opts.mode or nil
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

	if has_target_header then
		local insert_after = header_idx or 0
		local prefix = vim.list_slice(existing, 1, insert_after)
		local remaining = vim.list_slice(existing, insert_after + 1)

		vim.list_extend(merged, prefix)
		vim.list_extend(merged, block)

		if #remaining > 0 and #block > 0 then
			append_blank_lines(merged, separator_padding(remaining, block, false))
		end

		vim.list_extend(merged, remaining)
	elseif opts.prepend then
		append_blank_lines(merged, missing_padding(lines, padding.top or 0, true))
		vim.list_extend(merged, lines)

		local bottom_padding = math.max(
			missing_padding(lines, padding.bottom or 0, false),
			(#existing > 0 and #lines > 0) and separator_padding(existing, lines, false) or 0
		)

		append_blank_lines(merged, bottom_padding)
		vim.list_extend(merged, existing)
	else
		local top_padding = math.max(
			missing_padding(lines, padding.top or 0, true),
			(#existing > 0 and #lines > 0) and separator_padding(existing, lines, true) or 0
		)

		vim.list_extend(merged, existing)
		append_blank_lines(merged, top_padding)
		vim.list_extend(merged, lines)
		append_blank_lines(merged, missing_padding(lines, padding.bottom or 0, false))
	end

	return M.write_lines(path, merged, bufnr, { mode = mode }, opts.after)
end

return M
