local message = require("memo.message")

local M = {}

---@return boolean synced -- true when `memo sync git` exited successfully
function M.sync_git()
	local result = vim.system({ "memo", "sync", "git" }):wait()

	if result.code == 0 then
		message.info("Sync complete: git")
		return true
	end

	message.error("Something went wrong syncing git")
	return false
end

return M
