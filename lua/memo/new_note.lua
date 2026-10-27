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

--- Remove an already-loaded buffer before replacing its note.
---@param path string
---@return boolean success
local function cleanup_existing_buffer(path)
	local bufnr = vim.fn.bufnr(path)

	if bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) then
		return true
	end

	local ok, err = pcall(vim.api.nvim_buf_delete, bufnr, { force = false })

	if not ok then
		require("memo.message").error("MemoNewNote: could not close existing buffer (%s): %s", path, err)
		return false
	end

	return true
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
	local selection = require("memo.selection")
	local note_io = require("memo.note_io")
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

	-- Resolved before editing: the selection belongs to the source buffer. The
	-- check comes before the existing note is touched, so an empty selection
	-- cannot cost the note it was meant to replace.
	local source_bufnr = vim.api.nvim_get_current_buf()
	local selected = selection.resolve(source_bufnr, new_opts)

	if selected and table.concat(selected, "\n"):gsub("%s+", "") == "" then
		message.warn("MemoNewNote: aborted, selection is empty")
		return false
	end

	-- Prepared before the original is touched: a template that raises cannot
	-- cost the note it was meant to replace.
	local note_template = Template.new({ template = new_opts.template })
	local initial_lines, cursor_pos = note_template:initial_content(selected)

	-- A cancelled passphrase prompt or failed write leaves the original restorable.

	if not cleanup_existing_buffer(note_path) then
		return false
	end

	local success, err = note_io.protect(note_path, function()
		-- Remove the old ciphertext only after its backup is secured. Editing
		-- the now-missing path lets the normal note autocmd prepare the buffer.
		if utils.file_exists(note_path) and vim.fn.delete(note_path) ~= 0 then
			return false, "could not remove existing note"
		end

		local win = window.open(new_opts.window)

		vim.api.nvim_win_call(win, function()
			vim.cmd("edit " .. vim.fn.fnameescape(note_path))
		end)

		local bufnr = vim.api.nvim_win_get_buf(win)

		if #initial_lines > 0 then
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, initial_lines)
		end

		-- The requested mode determines a new note's encryption.
		local crypto = require("memo.crypto")
		local mode = new_opts.encryption and new_opts.encryption.mode
		local written, write_err = crypto.encrypt_from_stdin(note_path, initial_lines, bufnr, {
			mode = mode,
			confirm = overwriting,
		})

		if not written then
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end

			return false, write_err
		end

		vim.bo[bufnr].modified = false

		-- Record the content just written so the first `:w` is a no-op instead
		-- of re-encrypting the note it was created from.
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		vim.b[bufnr].hash = vim.fn.sha256(table.concat(lines, "\n"))

		-- Only when the note is still in `win`: an autocmd may have moved it.
		if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
			vim.api.nvim_win_set_cursor(win, cursor_pos)
		end

		return true
	end)

	if not success then
		-- A dismissed prompt has no reason: a cancellation, nothing to report.
		if err then
			message.error("MemoNewNote: %s", err)
		end

		return false
	end

	return true
end

return M
