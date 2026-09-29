local M = {}

---@alias MemoWindowSplit "split" | "vsplit" | "tab"
---@alias MemoWindowPosition "botright" | "topleft" | "leftabove" | "rightbelow"

---@class MemoWindowConfig
---@field split? MemoWindowSplit "split" (default), "vsplit" or "tab"
---@field size? number share of the screen to take, 0 to 1, e.g. 0.5 for half.
---Defaults to half the screen in that direction, so a note has room to write
---in without hiding what you are working against. A "tab" is the whole screen,
---so this does not apply to it.
---@field position? MemoWindowPosition "botright" (default), "topleft",
---"leftabove" or "rightbelow". A "tab" is always opened after the current one,
---so this does not apply to it.

local DEFAULTS = {
	split = "split",
	size = 0.5,
	position = "botright",
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

	return math.floor(extent * DEFAULTS.size)
end

---The split that would be opened for this config.
---@param win_config MemoWindowConfig?
---@return MemoWindowSplit
local function resolve_split(win_config)
	return win_config and win_config.split or DEFAULTS.split
end

---Opens a split or tab for the next buffer, or keeps the current window when no
---config is given. Every option has a default, so `{ split = "vsplit" }` is
---enough to open a note beside the buffer.
---@param win_config MemoWindowConfig? nil keeps the current window
---@return integer win the window to fill
function M.open(win_config)
	if not win_config then
		return vim.api.nvim_get_current_win()
	end

	local split = resolve_split(win_config)
	local position = win_config.position or DEFAULTS.position

	-- `:tabnew` always lands after the current tab, so `position` is dropped
	-- rather than passed on as a modifier that does nothing.
	if split == "tab" then
		vim.cmd("tabnew")
	else
		local size = resolve_size(split, win_config.size)

		vim.cmd(string.format("%s %d%s", position, size, split))
	end

	return vim.api.nvim_get_current_win()
end

return M
