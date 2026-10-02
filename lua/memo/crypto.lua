local gpg = require("memo.gpg")
local message = require("memo.message")
local utils = require("memo.utils")

local M = {}

local NO_PASSPHRASE = "the passphrase was not given"
local DECRYPT_FAILED = "Decryption failed: %s"

---@param path string
---@param input string[]
---@param bufnr? integer buffer the note was decrypted into, so a symmetric note
---is written back the way it was encrypted
---@return vim.SystemCompleted
function M.encrypt_from_stdin(path, input, bufnr)
	if gpg.is_symmetric(path, bufnr) then
		local passphrase = gpg.get_symmetric_passphrase(path, bufnr)

		if not passphrase then
			-- A result the caller can still read .code from, for a command that
			-- never ran.
			return { code = 1, signal = 0, stdout = "", stderr = ("Not writing %s: %s"):format(path, NO_PASSPHRASE) }
		end

		-- `memo` owns the encryption, so a passphrase note is byte for byte what
		-- the CLI writes.
		return gpg.exec_with_passphrase(
			{ "memo", "encrypt", "--symmetric", path, "--passphrase-env", gpg.PASSPHRASE_ENV },
			passphrase,
			{ stdin = input }
		):wait()
	end

	return vim.system({ "memo", "encrypt", path }, {
		stdin = input,
	}):wait()
end

--- Decrypts a file and returns the content
--- @param path string The path to the encrypted file.
--- @param bufnr? integer buffer to remember a symmetric passphrase in.
--- @return vim.SystemCompleted?
function M.decrypt_to_stdout(path, bufnr)
	if gpg.is_symmetric(path, bufnr) then
		local passphrase = gpg.get_symmetric_passphrase(path, bufnr)

		if not passphrase then
			message.error("Could not read %s: %s", path, NO_PASSPHRASE)
			return nil
		end

		return gpg.exec_with_passphrase({ "memo", "decrypt", path, "--passphrase-env", gpg.PASSPHRASE_ENV }, passphrase)
			:wait()
	end

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

--- Streams a decrypt command into a buffer as its output arrives.
--- @param bufnr integer the buffer handle to write into
--- @param on_exit fun(result: vim.SystemCompleted)
--- @param run fun(opts: vim.SystemOpts, on_exit: fun(result: vim.SystemCompleted)): vim.SystemObj? nil when the passphrase could not be obtained
--- @return vim.SystemObj?
local function stream_into_buffer(bufnr, on_exit, run)
	local accumulator = ""
	local state = { first_write = true }

	local obj = run({
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

	return obj
end

--- Decrypts a file and handles all buffer insertions.
--- A note encrypted with a passphrase is decrypted by `memo` with the passphrase
--- kept in the buffer, so writing it back stays symmetric. If the
--- passphrase cannot be obtained the `on_exit` callback is NOT invoked, the
--- buffer is wiped and an error message is shown.
--- @param path string The path to the encrypted file.
--- @param bufnr integer The buffer handle to write into.
--- @param on_exit fun(result: vim.SystemCompleted)
--- @return vim.SystemObj?
function M.decrypt_to_buffer(path, bufnr, on_exit)
	if gpg.is_symmetric(path, bufnr) then
		local passphrase = gpg.get_symmetric_passphrase(path, bufnr)

		if not passphrase then
			utils.drop_buffer_with_error(bufnr, DECRYPT_FAILED:format(NO_PASSPHRASE))
			return nil
		end

		return stream_into_buffer(bufnr, on_exit, function(opts, exit)
			return gpg.exec_with_passphrase(
				{ "memo", "decrypt", path, "--passphrase-env", gpg.PASSPHRASE_ENV },
				passphrase,
				opts,
				exit
			)
		end)
	end

	local obj = stream_into_buffer(bufnr, on_exit, function(opts, exit)
		return gpg.exec_with_gpg_auth({ "memo", "decrypt", path }, opts, exit)
	end)

	if not obj then
		utils.drop_buffer_with_error(bufnr, DECRYPT_FAILED:format("could not authenticate"))
	end

	return obj
end

return M
