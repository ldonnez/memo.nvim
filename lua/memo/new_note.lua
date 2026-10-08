local M = {}

---@class MemoNewNoteOpts
---@field path? string note path inside the notes dir, prompts for one when
---omitted
---@field template? string body template with a `|` cursor marker; a range or
---visual selection is inserted there, or becomes the whole note
---@field range? integer
---@field line1? integer
---@field line2? integer
---@field encryption? GpgEncryptOpts how to encrypt, "key" when omitted
---@field window? MemoWindowConfig opens the note in a split, current window
---when omitted

---Default note path used when no path is given.
---@return string
local function default_path()
	return require("memo.utils").build_note_path(os.date("%Y-%m-%d.md"))
end

---Creates a new encrypted note and opens it in the current window.
---A range or visual selection is inserted at the template's `|` marker.
---@param opts? MemoNewNoteOpts
---@return boolean success
function M.create(opts)
	local new_opts = opts or {}
	local config = require("memo.config")
	local message = require("memo.message")
	local utils = require("memo.utils")
	local Template = require("memo.note_template")
	local window = require("memo.window")

	local path = new_opts.path

	if not path or path == "" then
		-- Prompted here so the Lua API behaves like the command.
		path = utils.prompt_note_path(default_path(), "MemoNewNote")

		if not path then
			return false
		end
	end

	local note_path = utils.resolve_note_path(path)

	if not note_path then
		message.error("MemoNewNote: note path must be inside the notes directory (%s)", config.notes_dir)
		return false
	end

	local overwriting = utils.file_has_content(note_path)

	if overwriting and not utils.confirm("Note already exists. Overwrite?", "MemoNewNote") then
		return false
	end

	if not utils.ensure_directories(vim.fs.dirname(note_path)) then
		return false
	end

	-- Discarded rather than opened: a note read from disk comes back decrypted
	-- and read-only, and its decrypt would race with writing the template.
	if overwriting and vim.fn.delete(note_path) ~= 0 then
		message.error("MemoNewNote: could not remove existing note (%s)", note_path)
		return false
	end

	-- Resolved before editing: the selection belongs to the source buffer.
	local source_bufnr = vim.api.nvim_get_current_buf()
	local selected = utils.resolve_selection(source_bufnr, new_opts)

	if selected and table.concat(selected, "\n"):gsub("%s+", "") == "" then
		message.warn("MemoNewNote: aborted, selection is empty")
		return false
	end

	local note_template = Template.new({ template = new_opts.template })
	local initial_lines, cursor_pos = note_template:initial_content(selected)

	-- Opened after the selection is resolved: a split would replace the source
	-- window.
	local win = window.open(new_opts.window)

	-- A new note opens as an empty buffer, encrypted by the first write below.
	vim.cmd("silent edit " .. vim.fn.fnameescape(note_path))

	local bufnr = vim.api.nvim_get_current_buf()

	if #initial_lines > 0 then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, initial_lines)
	end

	-- A new note has no file to read the mode from, so its write handler
	-- carries the mode of the first write in a closure.
	local enc_mode = new_opts.encryption and new_opts.encryption.mode
	if enc_mode then
		require("memo.autocmd_callbacks").register_write(bufnr, enc_mode)
	end

	vim.bo[bufnr].modified = true
	vim.cmd("silent write")

	-- Only when the note is still in `win`: an autocmd may have moved it.
	if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
		vim.api.nvim_win_set_cursor(win, cursor_pos)
	end

	return true
end

return M
