local gpg = require("memo.gpg")

local M = {}

---@param path string
---@param input string[]
---@return vim.SystemCompleted
function M.encrypt_from_stdin(path, input)
	local result = vim.system({ "memo", "encrypt", path }, {
		stdin = input,
	}):wait()

	if result.code ~= 0 then
		local err = (result.stderr and result.stderr ~= "") and result.stderr or "Unknown encryption error"
		vim.notify("Memo failed: " .. err, vim.log.levels.ERROR)
	end

	return result
end

--- Decrypts a file and returns the content
--- @param path string The path to the encrypted file.
--- @return vim.SystemCompleted?
function M.decrypt_to_stdout(path)
	return gpg.exec_with_gpg_auth({ "memo", "decrypt", path })
end

--- Decrypts a file and handles all buffer insertions.
--- @param path string The path to the encrypted file.
--- @param bufnr integer The buffer handle to write into.
--- @param on_exit fun(result: vim.SystemCompleted)
--- @return vim.SystemObj?
function M.decrypt_to_buffer(path, bufnr, on_exit)
	return gpg.exec_with_gpg_auth({ "memo", "decrypt", path }, {
		stdout = function(_, data)
			if not data or data == "" then
				return
			end

			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(bufnr) then
					return
				end

				vim.bo[bufnr].modifiable = true

				local line_count = vim.api.nvim_buf_line_count(bufnr)
				local last_line_idx = line_count - 1
				local last_line_content = vim.api.nvim_buf_get_lines(bufnr, -2, -1, false)[1] or ""
				local last_col = #last_line_content

				vim.api.nvim_buf_set_text(
					bufnr,
					last_line_idx,
					last_col,
					last_line_idx,
					last_col,
					vim.split(data, "\n", { plain = true, trimempty = true })
				)

				-- Ensure cursor stays on top
				local winid = vim.fn.bufwinid(bufnr)
				if winid ~= -1 then
					vim.api.nvim_win_set_cursor(winid, { 1, 0 })
				end

				vim.bo[bufnr].modified = false
				vim.bo[bufnr].modifiable = false
			end)
		end,
	}, function(result)
		vim.schedule(function()
			on_exit(result)
		end)
	end)
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
