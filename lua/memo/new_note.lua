local M = {}

---@class MemoNewNoteOpts
---@field path? string note path, relative to the notes dir or absolute inside
---it. Prompts for one, defaulting to today's date, when omitted.
---@field template? string body template, supports `os.date` formats and a `|`
---cursor marker. A range or visual selection is inserted at that marker, and
---becomes the whole note when the template has none.
---@field range? integer
---@field line1? integer
---@field line2? integer
---@field encryption? GpgEncryptOpts how to encrypt, "key" when omitted
---@field window? MemoWindowConfig opens the note in a split, the current
---window is kept when omitted

---Default note path used when no path is given. Like `save_as_note` this is a
---full path, so the prompt makes it obvious where the note will be created.
---@return string
local function default_path()
	return require("memo.utils").build_note_path(os.date("%Y-%m-%d.md"))
end

---Creates a new encrypted note and opens it in the current window.
---When a visual selection is active (or the command is given a range, e.g.
---`:'<,'>MemoNewNote`), the selected lines are inserted at the template's `|`
---marker instead of replacing the template.
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
		-- Prompted here rather than in the command, so the Lua API behaves the
		-- same way.
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

	-- The existing note is discarded instead of opened: a note opened from disk
	-- comes back decrypted and read-only, and its async decrypt would race with
	-- writing the template into the buffer.
	if overwriting and vim.fn.delete(note_path) ~= 0 then
		message.error("MemoNewNote: could not remove existing note (%s)", note_path)
		return false
	end

	-- Resolved before editing, because the selection belongs to the buffer the
	-- command was invoked from.
	local source_bufnr = vim.api.nvim_get_current_buf()
	local selected = utils.resolve_selection(source_bufnr, new_opts)

	if selected and table.concat(selected, "\n"):gsub("%s+", "") == "" then
		message.warn("MemoNewNote: aborted, selection is empty")
		return false
	end

	local note_template = Template.new({ template = new_opts.template })
	local initial_lines, cursor_pos, has_cursor_marker = note_template:resolve_template()

	if selected then
		if has_cursor_marker then
			initial_lines, cursor_pos = note_template:insert_at_cursor(selected)
		else
			-- Without a marker there is nowhere to insert into, so the
			-- selection becomes the whole note.
			initial_lines, cursor_pos = selected, { #selected, 0 }
		end
	end

	-- After the selection is resolved: it belongs to the window the call was
	-- made from, and a split would replace that window.
	local win = window.open(new_opts.window)

	-- Opening a note that does not exist yet yields an empty buffer, which the
	-- BufWriteCmd handler encrypts on the first write below.
	vim.cmd("silent edit " .. vim.fn.fnameescape(note_path))

	local bufnr = vim.api.nvim_get_current_buf()

	if #initial_lines > 0 then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, initial_lines)
	end

	-- A new note has no file to read the mode from, so the intent rides along on
	-- the buffer until the first write has encrypted it.
	local enc_mode = new_opts.encryption and new_opts.encryption.mode
	if enc_mode then
		vim.b[bufnr].memo_encryption_mode = enc_mode
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
