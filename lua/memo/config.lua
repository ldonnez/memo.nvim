local utils = require("memo.utils")

local M = {}

---@class MemoConfig
---@field notes_dir string

---@type MemoConfig
local defaults = {
	notes_dir = vim.fn.expand("~/notes"),
}

---@cast M.options.notes_dir string
---@type MemoConfig
M.options = vim.deepcopy(defaults)

---@param opts MemoConfig?
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", defaults, opts or {})
	M.options.notes_dir = vim.fn.expand(M.options.notes_dir)

	utils.check_exec("gpg")
	utils.check_exec("memo")

	if vim.fn.isdirectory(M.options.notes_dir) == 0 then
		vim.notify(
			string.format("Memo: Directory '%s' does not exist.", M.options.notes_dir),
			vim.log.levels.WARN,
			{ title = "memo.nvim" }
		)
	end
end

return M
