local M = {}

---@class MemoNewNoteOpts
---@field path? string note path, relative to the notes dir or absolute inside it
---@field template? string body template, supports `os.date` formats and a `|`
---cursor marker. Defaults to `g:memo_new_note_template`.

---Default note path used when no path is given. Like `save_as_note` this is a
---full path, so the prompt makes it obvious where the note will be created.
---@return string
function M.default_path()
	return require("memo.utils").build_note_path(os.date("%Y-%m-%d.md"))
end

---@param gpg_path string
---@return boolean
local function exists(gpg_path)
	return vim.fn.filereadable(gpg_path) == 1 and vim.fn.getfsize(gpg_path) > 0
end

---Creates a new encrypted note and opens it in the current window.
---@param opts? MemoNewNoteOpts
---@return boolean success
function M.create(opts)
	local new_opts = opts or {}
	local config = require("memo.config")
	local message = require("memo.message")
	local utils = require("memo.utils")
	local Template = require("memo.capture_template")

	local path = new_opts.path
	if not path or path == "" then
		path = M.default_path()
	end

	local gpg_path = utils.resolve_note_path(path)

	if not gpg_path then
		message.error("MemoNewNote: note path must be inside the notes directory (%s)", config.notes_dir)
		return false
	end

	if exists(gpg_path) then
		message.error("MemoNewNote: note already exists (%s)", gpg_path)
		return false
	end

	if not utils.ensure_directories(vim.fs.dirname(gpg_path)) then
		return false
	end

	local template = new_opts.template or config.new_note_template
	local template_lines, cursor_pos = Template.new({ template = template }):resolve_template()

	-- Opening a note that does not exist yet yields an empty buffer, which the
	-- BufWriteCmd handler encrypts on the first write below.
	vim.cmd("silent edit " .. vim.fn.fnameescape(gpg_path))

	local bufnr = vim.api.nvim_get_current_buf()

	if #template_lines > 0 then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, template_lines)
	end

	vim.bo[bufnr].modified = true
	vim.cmd("silent write")

	if vim.api.nvim_get_current_buf() == bufnr then
		vim.api.nvim_win_set_cursor(0, cursor_pos)
	end

	return true
end

return M
