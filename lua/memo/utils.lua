local message = require("memo.message")

local M = {}

---Ensures path ends with .gpg
---@param path string
---@return string
function M.get_gpg_path(path)
	if path == "" or path:match("%.gpg$") then
		return path
	end
	return path .. ".gpg"
end

---@param cmd string
---@return boolean
function M.check_exec(cmd)
	if vim.fn.executable(cmd) == 0 then
		message.error("'%s' binary not found", cmd)
		return false
	end
	return true
end

return M
