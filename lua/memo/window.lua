local M = {}

---@alias MemoWindowSplit "split" | "vsplit"
---@alias MemoWindowPosition "botright" | "topleft" | "leftabove" | "rightbelow"

---@class MemoWindowConfig
---@field split? MemoWindowSplit "split" (default) or "vsplit"
---@field size? integer rows for a split, columns for a vsplit. Defaults to
---10 rows, or 40% of the editor width for a vsplit, where a row count would be
---unusably narrow.
---@field position? MemoWindowPosition "botright" (default), "topleft",
---"leftabove" or "rightbelow"

local DEFAULTS = {
	split = "split",
	position = "botright",
	rows = 10,
	width_ratio = 0.4,
}

---A vsplit counts columns, so the row default would leave it a few characters
---wide.
---@param split MemoWindowSplit
---@return integer
local function default_size(split)
	if split == "vsplit" then
		return math.max(20, math.floor(vim.o.columns * DEFAULTS.width_ratio))
	end

	return DEFAULTS.rows
end

---The split that would be opened for this config, for callers that need to
---adjust the window they get.
---@param win_config MemoWindowConfig?
---@return MemoWindowSplit
function M.resolve_split(win_config)
	return win_config and win_config.split or DEFAULTS.split
end

---Opens a split for the next buffer, or keeps the current window when no
---config is given. Every option has a default, so `{ split = "vsplit" }` is
---enough to open a note beside the buffer.
---@param win_config MemoWindowConfig? nil keeps the current window
---@return integer win the window to fill
function M.open(win_config)
	if not win_config then
		return vim.api.nvim_get_current_win()
	end

	local split = M.resolve_split(win_config)
	local position = win_config.position or DEFAULTS.position
	local size = win_config.size or default_size(split)

	vim.cmd(string.format("%s %d%s", position, size, split))

	return vim.api.nvim_get_current_win()
end

return M
