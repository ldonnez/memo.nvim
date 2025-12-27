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

	return vim.system(cmd):wait()
end

return M
