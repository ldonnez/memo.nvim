local M = {}

---Check if a path is inside the dir
---@param dir string The configured notes directory
---@param path string The file path to check
---@return boolean
function M.in_dir(dir, path)
	local abs_path = vim.fn.fnamemodify(path, ":p")
	local abs_notes = vim.fn.fnamemodify(vim.fn.expand(dir), ":p")

	local sep = package.config:sub(1, 1) -- Gets '/' on Unix or '\' on Windows

	if abs_notes:sub(-1) ~= sep then
		abs_notes = abs_notes .. sep
	end

	return abs_path:sub(1, #abs_notes) == abs_notes
end

--- Compute base filename for a *.gpg file
---@param path string
---@return string, integer
function M.base_name(path)
	return path:gsub("%.gpg$", "")
end

--- Returns conflicting buffer
---@param base string
---@return integer?
function M.get_conflicting_buffer(base)
	local num = vim.fn.bufnr(base)
	return num ~= -1 and num or nil
end

---@param existing integer
---@param new integer
function M.handle_conflict(existing, new)
	if existing == new then
		return
	end

	vim.cmd("b " .. existing)
	vim.cmd("bwipeout! " .. new)
	vim.notify("Switched to existing decrypted buffer", vim.log.levels.INFO)
end

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
