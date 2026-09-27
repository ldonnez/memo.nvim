local M = {}

---@alias MemoWindowSplit "split" | "vsplit"
---@alias MemoWindowPosition "botright" | "topleft" | "leftabove" | "rightbelow"

---@class MemoWindowConfig
---@field split? MemoWindowSplit "split" (default) or "vsplit"
---@field size? number share of the screen to take, 0 to 1, e.g. 0.5 for half.
---Defaults to half the screen in that direction, so a note has room to write
---in without hiding what you are working against.
---@field position? MemoWindowPosition "botright" (default), "topleft",
---"leftabove" or "rightbelow"

local DEFAULTS = {
	split = "split",
	position = "botright",
	ratio = 0.5,
}

---A split counts rows and a vsplit counts columns, so the same share of the
---screen means a different unit per direction. A share of 1 or more would be
---larger than the screen, and 0 or less would leave no window, so both fall
---back to the default.
---@param split MemoWindowSplit
---@param size number?
---@return integer
local function resolve_size(split, size)
	local extent = split == "vsplit" and vim.o.columns or vim.o.lines

	if size and size > 0 and size <= 1 then
		return math.max(1, math.floor(extent * size))
	end

	return math.floor(extent * DEFAULTS.ratio)
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
	local size = resolve_size(split, win_config.size)

	vim.cmd(string.format("%s %d%s", position, size, split))

	return vim.api.nvim_get_current_win()
end

return M
