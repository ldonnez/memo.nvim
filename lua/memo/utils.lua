local M = {}

--- Prompt user for passphrase
---@return string
function M.prompt_passphrase()
	return vim.fn.inputsecret("GPG Passphrase: ")
end

--- Split decrypted text into clean list of lines
---@param str string
---@return string[]
function M.to_lines(str)
	local lines = vim.split(str or "", "\n", { plain = true })
	if lines[#lines] == "" then
		table.remove(lines)
	end
	return lines
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
