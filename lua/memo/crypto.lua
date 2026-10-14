local gpg = require("memo.gpg")
local message = require("memo.message")

local M = {}

local NO_PASSPHRASE = "the passphrase was not given"

---@param path string
---@param input string[]
---@param bufnr? integer buffer holding the passphrase of a passphrase note
---@param opts? GpgEncryptOpts
---@return vim.SystemCompleted
function M.encrypt_from_stdin(path, input, bufnr, opts)
	return gpg.encrypt(path, input, vim.tbl_extend("force", opts or {}, { bufnr = bufnr }))
end

--- Decrypts a file and returns the content
--- @param path string The path to the encrypted file.
--- @param bufnr? integer buffer to remember a symmetric passphrase in.
--- @return vim.SystemCompleted?
function M.decrypt_to_stdout(path, bufnr)
	local obj = gpg.decrypt(path, bufnr)

	if not obj then
		message.error("Could not read %s: %s", path, NO_PASSPHRASE)
		return nil
	end

	return obj:wait()
end

--- Appends lines to a buffer, replacing its content on the first write.
--- Returns the flag for the following write, so callers can thread it instead
--- of passing a mutable container around.
--- @param bufnr integer
--- @param lines string[]
--- @param first_write boolean
--- @return boolean first_write
local function append_to_buffer(bufnr, lines, first_write)
	if #lines == 0 or not vim.api.nvim_buf_is_valid(bufnr) then
		return first_write
	end

	vim.bo[bufnr].modifiable = true
	if first_write then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	else
		vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
	end
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].modified = false

	return false
end

--- Splits buffered decrypt output into complete lines, carrying the text after
--- the last newline over as `remainder` for the next batch. With
--- `emit_partial` the unterminated tail is emitted too, which is what the end
--- of the stream needs. Pure: no buffer or process state.
--- @param chunks string[] raw chunks buffered since the last split
--- @param remainder string the unterminated tail from the previous split
--- @param emit_partial boolean whether to also emit the unterminated tail
--- @return string[] lines
--- @return string remainder
local function split_lines(chunks, remainder, emit_partial)
	local text = remainder

	if #chunks > 0 then
		text = text .. table.concat(chunks)
	end

	if text == "" then
		return {}, remainder
	end

	local lines = vim.split(text, "\n", { plain = true })
	remainder = table.remove(lines)

	if emit_partial and remainder ~= "" then
		lines[#lines + 1] = remainder
		remainder = ""
	end

	return lines, remainder
end

--- Streams a decrypt command into a buffer as its output arrives.
--- @param bufnr integer the buffer handle to write into
--- @param on_exit fun(result: vim.SystemCompleted)
--- @return vim.SystemObj? nil when a passphrase prompt was dismissed
local function stream_into_buffer(path, bufnr, on_exit)
	local pending = {}
	local remainder = ""
	local first_write = true
	local scheduled = false

	local function drain(emit_partial)
		local lines, new_remainder = split_lines(pending, remainder, emit_partial)
		remainder = new_remainder
		pending = {}

		first_write = append_to_buffer(bufnr, lines, first_write)
	end

	local function flush()
		scheduled = false
		drain(false)
	end

	return gpg.decrypt(path, bufnr, {
		stdout = function(_, data)
			if not data or data == "" then
				return
			end

			pending[#pending + 1] = data

			-- Only a chunk with a newline completes a line; anything else is
			-- held until then, so the buffer is not rescheduled per chunk.
			if not scheduled and data:find("\n", 1, true) then
				scheduled = true
				vim.schedule(flush)
			end
		end,
	}, function(result)
		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end

			if result.code == 0 then
				drain(true)
			end
			vim.bo[bufnr].modifiable = false
			vim.bo[bufnr].modified = false
			on_exit(result)
		end)
	end)
end

--- Decrypts a file into a buffer. When no passphrase can be obtained, `on_exit`
--- is not invoked and the buffer is wiped.
--- @param path string The path to the encrypted file.
--- @param bufnr integer The buffer handle to write into.
--- @param on_exit fun(result: vim.SystemCompleted)
--- @return vim.SystemObj?
function M.decrypt_to_buffer(path, bufnr, on_exit)
	return stream_into_buffer(path, bufnr, on_exit)
end

return M
