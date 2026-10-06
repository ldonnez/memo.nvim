local crypto = require("memo.crypto")
local message = require("memo.message")

local M = {}

---Saves the current buffer as a note in the notes dir.
---Prompts for the note path (defaulting to `<notes_dir>/<name>.asc`) so it is
---clear where the note will be stored, encrypts the buffer contents and writes
---it there. A relative path is resolved against `<notes_dir>`; the resolved
---path must stay inside `<notes_dir>`. The buffer is left open afterward.
---When a visual selection is active (or the command is invoked with a range,
---e.g. `:'<,'>MemoSaveAsNote`), only the selected lines are saved.
---@class MemoSaveAsNoteOpts
---@field range? integer
---@field line1? integer
---@field line2? integer
---@field encryption? GpgEncryptOpts how to encrypt a new note, "key" when
---omitted. A note that already exists is left the way it was encrypted

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

	if utils.file_exists(note_path) and not utils.confirm("Note already exists. Overwrite?", "MemoSaveAsNote") then
		return false
	end

	if not utils.ensure_directories(vim.fs.dirname(note_path)) then
		return false
	end

	local lines = utils.resolve_selection(bufnr, opts) or vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- No buffer: the one being saved is not the note's, and a passphrase kept
	-- there would be reused for the next note saved from it.
	local mode = opts and opts.encryption and opts.encryption.mode
	local result = crypto.encrypt_from_stdin(note_path, lines, nil, { mode = mode })

	if result.code ~= 0 then
		local err = (result.stderr and result.stderr ~= "") and result.stderr or "encryption failed"
		message.error("MemoSaveAsNote: %s", err)
		return false
	end

	message.info("Saved note: %s", note_path)
	return true
end

return M
