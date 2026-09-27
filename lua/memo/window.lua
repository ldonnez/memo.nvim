local M = {}

---@alias MemoWindowSplit "split" | "vsplit"
---@alias MemoWindowPosition "botright" | "topleft" | "leftabove" | "rightbelow"

---@class MemoWindowConfig
---@field split MemoWindowSplit
---@field size integer
---@field position MemoWindowPosition

---Opens a split for the next buffer, or keeps the current window when no
---config is given. Callers that want to stay where they are pass nothing.
---@param win_config MemoWindowConfig? nil keeps the current window
---@return integer win the window to fill
function M.open(win_config)
	if not win_config then
		return vim.api.nvim_get_current_win()
	end

	vim.cmd(string.format("%s %d%s", win_config.position, win_config.size, win_config.split))

	return vim.api.nvim_get_current_win()
end

return M
