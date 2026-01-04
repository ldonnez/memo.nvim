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
	local accumulator = ""
	local first_write = true

	return gpg.exec_with_gpg_auth({ "memo", "decrypt", path }, {
		stdout = function(_, data)
			if not data or data == "" then
				return
			end

			accumulator = accumulator .. data

			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(bufnr) then
					return
				end

				-- Only process if we have at least one newline
				if accumulator:find("\n") then
					local lines = vim.split(accumulator, "\n", { plain = true })
					-- Keep the part after the last newline in the accumulator
					accumulator = table.remove(lines)

					vim.bo[bufnr].modifiable = true
					if first_write then
						vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
						first_write = false
					else
						-- Append completed lines
						vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
					end
					vim.bo[bufnr].modifiable = false
					vim.bo[bufnr].modified = false
				end
			end)
		end,
	}, function(result)
		vim.schedule(function()
			if result.code == 0 and vim.api.nvim_buf_is_valid(bufnr) then
				vim.bo[bufnr].modifiable = true

				if first_write then
					vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { accumulator })
				elseif accumulator ~= "" then
					vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { accumulator })
				end

				vim.bo[bufnr].modifiable = false
				vim.bo[bufnr].modified = false
			end

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
