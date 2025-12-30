local M = {}

--- Prompt user for passphrase
---@param label string
---@return string
function M.prompt_passphrase(label)
	return vim.fn.inputsecret("GPG Passphrase for " .. label .. ": ")
end

---Ensures path ends with .gpg
---@param path string
---@return string
function M.get_gpg_path(path)
	if path == "" or path:match("%.gpg$") then
		return path
	end
	return path .. ".gpg"
end

---Add security buffer settings to prevent disk leakage
---@param bufnr integer
function M.harden_buffer(bufnr)
	vim.opt_local.swapfile = false
	vim.opt_local.undofile = false
	vim.opt_local.shadafile = "NONE"
	vim.bo[bufnr].buftype = "acwrite"
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
