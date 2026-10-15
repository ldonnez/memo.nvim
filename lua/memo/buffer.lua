local M = {}

---@class MemoBufferOpts
---@field name string buffer name, e.g. a note path or a scratch path
---@field window? integer window to show the buffer in, current window when
---omitted

---Opens a listed buffer for `opts.name`. Showing it
---performs a real read, which fires the read autocommands, clears the
---`[Not edited]` flag and lets `:mksession` restore the buffer. The filetype is
---derived from the name without its note extension, so it does not depend on
---the plugin's read autocommands.
---@param opts MemoBufferOpts
---@return integer bufnr
function M.create(opts)
	local buf = vim.fn.bufadd(opts.name)

	vim.api.nvim_win_set_buf(opts.window or vim.api.nvim_get_current_win(), buf)

	vim.bo[buf].buflisted = true
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].undofile = false
	-- The buffer is named before its file exists, so the first `:write` would
	-- hit `E13: File exists`. `acwrite` routes the write through our
	-- `BufWriteCmd` instead; autocmd_callbacks.lua -> `prepare_buffer_for_edit` resets it once the note
	-- has been read.
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].fileencoding = "utf-8"
	vim.bo[buf].filetype = require("memo.utils").get_filetype(opts.name) or ""

	return buf
end

return M
