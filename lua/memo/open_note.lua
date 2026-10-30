local M = {}

---@class MemoOpenOpts
---@field path? string note path, relative to the notes dir or absolute inside
---it. Defaults to `g:memo_default_refile_target`.
---@field window? MemoWindowConfig opens the note in a split, the current window
---is kept when omitted

---Opens an existing encrypted note, which is decrypted on open.
---@param opts? MemoOpenOpts
---@return boolean success
function M.open(opts)
	local config = require("memo.config")
	local message = require("memo.message")
	local utils = require("memo.utils")
	local window = require("memo.window")

	local open_opts = opts or {}
	local path = open_opts.path or config.refile_target

	if path == "" then
		message.error("MemoOpen: a note path is required, or set g:memo_default_refile_target")
		return false
	end

	local note_path = utils.resolve_note_path(path)

	if not note_path then
		return false
	end

	-- Checked here because `:edit` on a missing file succeeds and leaves an
	-- empty buffer, which would look like an empty note.
	if not utils.file_exists(note_path) then
		message.error("MemoOpen: note not found (%s)", note_path)
		return false
	end

	window.open(open_opts.window)
	vim.cmd("silent edit " .. vim.fn.fnameescape(note_path))

	return true
end

return M
