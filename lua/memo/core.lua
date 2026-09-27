local message = require("memo.message")

local M = {}

---@return vim.SystemCompleted?
function M.sync_git()
	local cmd = { "memo", "sync", "git" }

	local result = vim.system(cmd):wait()
	if result and result.code == 0 then
		return message.info("Sync complete: git")
	end
	return message.error("Something went wrong syncing git")
end

return M
