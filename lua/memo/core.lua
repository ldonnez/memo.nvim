local gpg = require("memo.gpg")

local M = {}

---@param path string
---@return vim.SystemCompleted?
function M.decrypt_to_stdout(path)
	return gpg.exec_with_gpg_auth({ "memo", "decrypt", path })
end

---@param path string
---@param input string[]
---@return vim.SystemCompleted?
function M.encrypt_from_stdin(path, input)
	return vim.system({ "memo", "encrypt", path }, { stdin = input }):wait()
end

---@return vim.SystemCompleted?
function M.sync_git()
	local cmd = { "memo", "sync", "git" }

	local result = vim.system(cmd):wait()
	if result and result.code == 0 then
		return vim.notify("Sync complete: git", vim.log.levels.INFO)
	end
	return vim.notify("Something went wrong syncing git ", vim.log.levels.ERROR)
end

return M
