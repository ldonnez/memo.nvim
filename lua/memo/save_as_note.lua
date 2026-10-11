local crypto = require("memo.crypto")
local message = require("memo.message")
local NoteBackup = require("memo.note_backup")

local M = {}

---Saves the current buffer as a note in the notes dir.
---Prompts for the note path (defaulting to `<notes_dir>/<name>.asc`), encrypts
---the buffer contents and writes it there. A relative path is resolved against
---`<notes_dir>` and must stay inside it. The buffer is left open afterward.
---A range or visual selection saves only the selected lines.
---@class MemoSaveAsNoteOpts
---@field range? integer
---@field line1? integer
---@field line2? integer
---@field encryption? GpgEncryptOpts how to encrypt a new note, "key" when
---omitted; an existing note keeps the way it was encrypted

---@param opts? MemoSaveAsNoteOpts
---@return boolean success
function M.create(opts)
	local utils = require("memo.utils")
	local config = require("memo.config")
	local bufnr = vim.api.nvim_get_current_buf()
	local notes_dir = config.notes_dir
	local current = vim.api.nvim_buf_get_name(bufnr)

	local default_name = utils.strip_extension(vim.fn.fnamemodify(current, ":t"))
	local default_path = utils.build_note_path(default_name)
	local target = utils.prompt_note_path(default_path, "MemoSaveAsNote")

	if not target then
		return false
	end

	local note_path = utils.resolve_note_path(target)

	if not note_path then
		message.error("MemoSaveAsNote: note path must be inside the notes directory (%s)", notes_dir)
		return false
	end

	local overwriting = utils.file_has_content(note_path)

	if overwriting and not utils.confirm("Note already exists. Overwrite?", "MemoSaveAsNote") then
		return false
	end

	if not utils.ensure_directories(vim.fs.dirname(note_path)) then
		return false
	end

	local lines = utils.resolve_selection(bufnr, opts) or vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- The existing note is backed up until the replacement has been encrypted:
	-- a failed or cancelled encryption leaves it restorable.
	local backup = NoteBackup.new(note_path)

	if overwriting and not backup:save() then
		message.error("MemoSaveAsNote: could not back up existing note (%s)", note_path)
		return false
	end

	-- Delete the existing note before encryption (like new_note does).
	-- This is necessary so a passphrase-protected overwrite uses the same
	-- confirmation flow as a fresh note.
	if overwriting and vim.fn.delete(note_path) ~= 0 then
		backup:restore()
		message.error("MemoSaveAsNote: could not remove existing note (%s)", note_path)
		return false
	end

	-- No buffer: a passphrase kept here would be reused for the next note.
	local mode = opts and opts.encryption and opts.encryption.mode
	local result = crypto.encrypt_from_stdin(note_path, lines, nil, { mode = mode })

	if result.code ~= 0 then
		backup:restore()

		local err = (result.stderr and result.stderr ~= "") and result.stderr or "encryption failed"
		message.error("MemoSaveAsNote: %s", err)
		return false
	end

	backup:discard()

	message.info("Saved note: %s", note_path)
	return true
end

return M
