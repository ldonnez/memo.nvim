local crypto = require("memo.crypto")
local message = require("memo.message")

local M = {}

---Saves the current buffer as a note in the notes dir.
---Prompts for the note path (defaulting to `<notes_dir>/<name>.gpg`) so it is
---clear where the note will be stored, encrypts the buffer contents and writes
---it there. A relative path is resolved against `<notes_dir>`; the resolved
---path must stay inside `<notes_dir>`. The buffer is left open afterward.
---When a visual selection is active (or the command is invoked with a range,
---e.g. `:'<,'>MemoSaveAsNote`), only the selected lines are saved.
---@param opts? { range?: integer, line1?: integer, line2?: integer }
---@return boolean success
function M.create(opts)
	local utils = require("memo.utils")
	local config = require("memo.config")
	local bufnr = vim.api.nvim_get_current_buf()
	local notes_dir = config.notes_dir
	local current = vim.api.nvim_buf_get_name(bufnr)

	local default_name = vim.fn.fnamemodify(current, ":t"):gsub("%.gpg$", "")
	local default_path = utils.build_note_path(default_name)
	local target = utils.prompt_note_path(default_path, "MemoSaveAsNote")

	if not target then
		return false
	end

	local gpg_path = utils.resolve_note_path(target)

	if not gpg_path then
		message.error("MemoSaveAsNote: note path must be inside the notes directory (%s)", notes_dir)
		return false
	end

	if utils.file_exists(gpg_path) and not utils.confirm("Note already exists. Overwrite?", "MemoSaveAsNote") then
		return false
	end

	if not utils.ensure_directories(vim.fs.dirname(gpg_path)) then
		return false
	end

	local lines = utils.resolve_selection(bufnr, opts) or vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local result = crypto.encrypt_from_stdin(gpg_path, lines)

	if result.code ~= 0 then
		message.error("MemoSaveAsNote: encryption failed")
		return false
	end

	message.info("Saved note: %s", gpg_path)
	return true
end

return M
