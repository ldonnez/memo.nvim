local M = {}

--- Prompt user for passphrase
---@param label string
---@return string
function M.prompt_passphrase(label)
	return vim.fn.inputsecret("GPG Passphrase for " .. label .. ": ")
end

---Ensures a path ends in .gpg
---@param path string
---@return string
function M.get_gpg_path(path)
	if path == "" or path:match("%.gpg$") then
		return path
	end
	return path .. ".gpg"
end

---Inserts new lines into existing content after the header (line 2)
---@param existing_lines string[]
---@param new_lines string[]
---@return string[]
function M.merge_content(existing_lines, new_lines)
	local merged = {
		existing_lines[1] or "",
		existing_lines[2] or "",
	}
	for _, l in ipairs(new_lines) do
		table.insert(merged, l)
	end
	table.insert(merged, "") -- Separator
	for i = 3, #existing_lines do
		table.insert(merged, existing_lines[i])
	end
	return merged
end

---Standard security settings for GPG buffers
---@param bufnr integer
function M.apply_gpg_opts(bufnr)
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
