local gpg = require("memo.gpg")
local message = require("memo.message")

local M = {}

---@param path string
---@param input string[]
---@return vim.SystemCompleted
function M.encrypt_from_stdin(path, input)
	return vim.system({ "memo", "encrypt", path }, {
		stdin = input,
	}):wait()
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
--- aborted the passphrase prompt); in that case an error message is shown and
--- the buffer is wiped. The `on_exit` callback is NOT invoked then.
--- @param path string The path to the encrypted file.
--- @param bufnr integer The buffer handle to write into.
--- @param on_exit fun(result: vim.SystemCompleted)
--- @return vim.SystemObj?
function M.decrypt_to_buffer(path, bufnr, on_exit)
	local accumulator = ""
	local state = { first_write = true }

	local obj = gpg.exec_with_gpg_auth({ "memo", "decrypt", path }, {
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
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end

			if result.code == 0 and accumulator ~= "" then
				append_to_buffer(bufnr, { accumulator }, state)
			end
			vim.bo[bufnr].modifiable = false
			vim.bo[bufnr].modified = false
			on_exit(result)
		end)
	end)

	-- exec_with_gpg_auth returns nil when the passphrase could not be obtained.
	-- Leaving the buffer in place would freeze it: modifiable stays false and
	-- nothing would reset it, so wipe it and tell the user.
	if not obj then
		message.defer_error("Decryption failed: could not authenticate")
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end)
	end

	return obj
end

return M
