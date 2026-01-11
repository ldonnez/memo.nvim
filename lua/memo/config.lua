local utils = require("memo.utils")
local message = require("memo.message")

---@class MemoConfig
---@field notes_dir string

---@type MemoConfig
local config = {
	notes_dir = vim.fn.expand("~/notes"),
}

---@class MemoConfigModule : MemoConfig
local M = {}

---@param opts MemoConfig?
function M.setup(opts)
	if opts then
		local new_config = vim.tbl_deep_extend("force", config, opts)
		for k, v in pairs(new_config) do
			config[k] = v
		end
	end

	config.notes_dir = vim.fn.expand(config.notes_dir)

	utils.check_exec("gpg")
	utils.check_exec("memo")

	if vim.fn.isdirectory(config.notes_dir) == 0 then
		message.warn("Directory '%s' does not exist", config.notes_dir)
	end
end

---@type MemoConfigModule
local module = setmetatable(M, {
	__index = config,
})

return module
