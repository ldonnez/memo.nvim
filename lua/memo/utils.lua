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
		vim.notify(
			string.format("Memo.nvim: '%s' binary not found", cmd),
			vim.log.levels.ERROR,
			{ title = "Dependency Missing" }
		)
		return false
	end
	return true
end

return M
