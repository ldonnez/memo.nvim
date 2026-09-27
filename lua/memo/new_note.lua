local M = {}

---@class MemoNewNoteOpts
---@field path? string note path, relative to the notes dir or absolute inside it
---@field template? string body template, supports `os.date` formats and a `|`
---cursor marker. Defaults to `g:memo_new_note_template`. Ignored when a range
---or visual selection is given.
---@field range? integer
---@field line1? integer
---@field line2? integer

---Default note path used when no path is given. Like `save_as_note` this is a
---full path, so the prompt makes it obvious where the note will be created.
---@return string
function M.default_path()
	return require("memo.utils").build_note_path(os.date("%Y-%m-%d.md"))
end

---Creates a new encrypted note and opens it in the current window.
---When a visual selection is active (or the command is given a range, e.g.
---`:'<,'>MemoNewNote`), the selected lines seed the note instead of the
---template.
---@param opts? MemoNewNoteOpts
---@return boolean success
function M.create(opts)
	local new_opts = opts or {}
	local config = require("memo.config")
	local message = require("memo.message")
	local utils = require("memo.utils")
	local Template = require("memo.note_template")

	local path = new_opts.path
	if not path or path == "" then
		path = M.default_path()
	end

	local gpg_path = utils.resolve_note_path(path)

	if not gpg_path then
		message.error("MemoNewNote: note path must be inside the notes directory (%s)", config.notes_dir)
		return false
	end

	local overwriting = utils.file_has_content(gpg_path)

	if overwriting and not utils.confirm("Note already exists. Overwrite?", "MemoNewNote") then
		return false
	end

	if not utils.ensure_directories(vim.fs.dirname(gpg_path)) then
		return false
	end

	-- The existing note is discarded instead of opened: a note opened from disk
	-- comes back decrypted and read-only, and its async decrypt would race with
	-- writing the template into the buffer.
	if overwriting and vim.fn.delete(gpg_path) ~= 0 then
		message.error("MemoNewNote: could not remove existing note (%s)", gpg_path)
		return false
	end

	-- Resolved before editing, because the selection belongs to the buffer the
	-- command was invoked from.
	local source_bufnr = vim.api.nvim_get_current_buf()
	local selected = utils.resolve_selection(source_bufnr, new_opts)

	local initial_lines, cursor_pos
	if selected then
		if table.concat(selected, "\n"):gsub("%s+", "") == "" then
			message.warn("MemoNewNote: aborted, selection is empty")
			return false
		end

		initial_lines = selected
		cursor_pos = { #selected, 0 }
	else
		local template = new_opts.template or config.new_note_template
		initial_lines, cursor_pos = Template.new({ template = template }):resolve_template()
	end

	-- Opening a note that does not exist yet yields an empty buffer, which the
	-- BufWriteCmd handler encrypts on the first write below.
	vim.cmd("silent edit " .. vim.fn.fnameescape(gpg_path))

	local bufnr = vim.api.nvim_get_current_buf()

	if #initial_lines > 0 then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, initial_lines)
	end

	vim.bo[bufnr].modified = true
	vim.cmd("silent write")

	if vim.api.nvim_get_current_buf() == bufnr then
		vim.api.nvim_win_set_cursor(0, cursor_pos)
	end

	return true
end

return M
