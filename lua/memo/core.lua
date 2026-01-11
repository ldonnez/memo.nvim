local gpg = require("memo.gpg")
local message = require("memo.message")

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
		message.error("%s", err)
	end

	return result
end

--- Decrypts a file and returns the content
--- @param path string The path to the encrypted file.
--- @return vim.SystemCompleted?
function M.decrypt_to_stdout(path)
	return gpg.exec_with_gpg_auth({ "memo", "decrypt", path })
end

--- Appends lines to buffer
--- @param bufnr integer
--- @param lines string[]
--- @param state { first_write: boolean }
local function append_to_buffer(bufnr, lines, state)
	if #lines == 0 or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.bo[bufnr].modifiable = true
	if state.first_write then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		state.first_write = false
	else
		vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
	end
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].modified = false
end

--- Decrypts a file and handles all buffer insertions.
--- @param path string The path to the encrypted file.
--- @param bufnr integer The buffer handle to write into.
--- @param on_exit fun(result: vim.SystemCompleted)
--- @return vim.SystemObj?
function M.decrypt_to_buffer(path, bufnr, on_exit)
	local accumulator = ""
	local state = { first_write = true }

	return gpg.exec_with_gpg_auth({ "memo", "decrypt", path }, {
		stdout = function(_, data)
			if not data or data == "" then
				return
			end

			accumulator = accumulator .. data

			vim.schedule(function()
				local lines = vim.split(accumulator, "\n", {
					plain = true,
				})
				accumulator = table.remove(lines)
				append_to_buffer(bufnr, lines, state)
			end)
		end,
	}, function(result)
		vim.schedule(function()
			if result.code == 0 and accumulator ~= "" then
				append_to_buffer(bufnr, { accumulator }, state)
			end
			vim.bo[bufnr].modifiable = false
			vim.bo[bufnr].modified = false
			on_exit(result)
		end)
	end)
end

---@return vim.SystemCompleted?
function M.sync_git()
	local cmd = { "memo", "sync", "git" }

	local result = vim.system(cmd):wait()
	if result and result.code == 0 then
		return message.info("Sync complete: git")
	end
	return message.error("Something went wrong syncing git")
end

return M
