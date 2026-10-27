local message = require("memo.message")
local note_io = require("memo.note_io")
local utils = require("memo.utils")
local gpg = require("memo.gpg")
local selection = require("memo.selection")

local M = {}

---@class MemoArchiveOpts
---@field range? integer Command range indicator from a user command
---@field line1? integer First line of the command range
---@field line2? integer Last line of the command range

---Returns the companion archive path, preserving the note's content and encryption extensions.
---@param path string
---@return string
local function archive_path(path)
	local extension = utils.get_extension(path) or "asc"
	local content_path = utils.strip_extension(path)
	local stem, content_extension = content_path:match("^(.*)(%.[^./]+)$")

	return (stem or content_path) .. ".archive" .. (content_extension or "") .. "." .. extension
end

---@param path string
---@param lines string[]
---@param bufnr integer
---@param source_path string
---@param after fun(): boolean, string?
---@return boolean success
---@return string? err
local function append_to_archive(path, lines, bufnr, source_path, after)
	local existed = utils.file_exists(path)
	local has_content = utils.file_has_content(path)

	if not existed and vim.fn.getftype(path) ~= "" then
		return false, ("archive path is not a file: %s"):format(path)
	end

	local existing, read_err = note_io.read_lines(path, bufnr)

	if not existing then
		return false, read_err
	end

	vim.list_extend(existing, lines)

	-- A new archive follows the source note's mode. Existing archives retain
	-- their mode in gpg.encrypt, which detects it before replacing the file.
	local mode = not has_content and gpg.get_encryption_mode(source_path) or nil

	return note_io.write_lines(path, existing, bufnr, { mode = mode }, after)
end

---@param opts? MemoArchiveOpts
---@return boolean
function M.archive(opts)
	local config = require("memo.config")
	local bufnr = vim.api.nvim_get_current_buf()
	local name = vim.api.nvim_buf_get_name(bufnr)

	if name == "" then
		message.error("MemoArchive: current buffer has no file name")
		return false
	end

	local path = vim.fn.fnamemodify(name, ":p")
	local stat = vim.uv.fs_stat(path)

	if (stat and stat.type ~= "file") or not utils.is_in_dir(path, config.notes_dir) then
		message.error("MemoArchive: current buffer is not a note in %s", config.notes_dir)
		return false
	end

	local selected_lines, selection_range = selection.resolve(bufnr, opts)

	if not selected_lines or not selection_range then
		message.error("MemoArchive: select the text to archive")
		return false
	end

	if #selected_lines == 0 then
		return false
	end

	local archive_file = archive_path(path)

	if not utils.ensure_directories(vim.fs.dirname(archive_file)) then
		return false
	end

	local relative_path = vim.fs.relpath(vim.fn.resolve(config.notes_dir), vim.fn.resolve(path)) or path
	local entry = {
		"",
		"---",
		"",
		"Archived: " .. os.date("%Y-%m-%dT%H:%M:%S%z"),
		"Source: " .. relative_path,
		"",
	}
	vim.list_extend(entry, selected_lines)

	local success, err = append_to_archive(archive_file, entry, bufnr, path, function()
		vim.cmd("normal! \27")
		selection.delete_selection(bufnr, selection_range)
		return true
	end)

	if not success then
		if err then
			message.error("MemoArchive: %s", err)
		end

		return false
	end

	message.info("Archived lines to %s", archive_file)
	return true
end

return M
