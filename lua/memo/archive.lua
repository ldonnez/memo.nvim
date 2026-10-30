local message = require("memo.message")
local note_io = require("memo.note_io")
local utils = require("memo.utils")
local gpg = require("memo.gpg")
local selection = require("memo.selection")
local Template = require("memo.note_template")

local M = {}

---@class MemoArchiveOpts
---@field range? integer Command range indicator from a user command
---@field line1? integer First line of the command range
---@field line2? integer Last line of the command range
---@field template? string Entry template; `${cursor}` marks where archived lines are inserted

---Returns the companion archive path, preserving the note's content and encryption extensions.
---@param path string
---@return string
local function archive_path(path)
	local extension = utils.get_extension(path) or "asc"
	local content_path = utils.strip_extension(path)
	local stem, content_extension = content_path:match("^(.*)(%.[^./]+)$")

	return (stem or content_path) .. ".archive" .. (content_extension or "") .. "." .. extension
end

---@param template_text? string
---@param bufnr integer
---@param selection_range MemoSelection
---@param selected_lines string[]
---@return string[]
local function archive_entry(template_text, bufnr, selection_range, selected_lines)
	if template_text == nil or template_text == "" then
		return selected_lines
	end

	local template = Template.for_buffer({
		template = template_text,
		bufnr = bufnr,
		selection = selection_range,
	})
	local template_lines, cursor_pos, has_cursor_marker = template:resolve_template()

	if has_cursor_marker then
		local entry = template:insert_at_cursor(selected_lines, template_lines, cursor_pos, has_cursor_marker)
		return entry
	end

	return vim.list_extend(template_lines, selected_lines)
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

	if not vim.bo[bufnr].modifiable then
		message.error("MemoArchive: current buffer is not modifiable")
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

	local source_changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
	local archive_file = archive_path(path)

	if not utils.ensure_directories(vim.fs.dirname(archive_file)) then
		return false
	end

	local template_text = opts and opts.template
	if template_text == "" then
		template_text = nil
	end

	local entry = archive_entry(template_text, bufnr, selection_range, selected_lines)
	local has_content = utils.file_has_content(archive_file)

	if template_text and has_content then
		while entry[1] == "" do
			table.remove(entry, 1)
		end
	end

	local success, err = note_io.insert_lines(archive_file, entry, bufnr, {
		mode = not has_content and gpg.get_encryption_mode(path) or nil,
		after = function()
			if
				not vim.api.nvim_buf_is_valid(bufnr)
				or vim.api.nvim_buf_get_changedtick(bufnr) ~= source_changedtick
			then
				return false, "source buffer changed while archiving"
			end

			vim.cmd("normal! \27")
			selection.delete_selection(bufnr, selection_range)
			return true
		end,
	})

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
