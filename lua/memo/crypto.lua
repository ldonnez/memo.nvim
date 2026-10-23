local gpg = require("memo.gpg")

local M = {}

--- Converts common GPG decryption errors into clearer messages, falling back
--- to trimmed stderr when no known error matches.
--- @param result vim.SystemCompleted
--- @return string
local function decrypt_failure_reason(result)
	-- vim.system uses exit code 124 when its timeout kills the process.
	if result.code == 124 then
		return "GPG: decryption timed out"
	end

	local stderr = result.stderr or ""

	if stderr:find("Bad session key", 1, true) then
		return "GPG: incorrect passphrase or corrupted file"
	end

	if stderr:find("Bad passphrase", 1, true) then
		return "GPG: incorrect passphrase"
	end

	if stderr:find("No secret key", 1, true) then
		return "GPG: no secret key available"
	end

	local trimmed = vim.trim(stderr)

	return trimmed ~= "" and trimmed or "GPG: decryption failed"
end

--- Uses GPG's stderr for encryption failures, or a fallback if it is empty.
--- @param result vim.SystemCompleted
--- @return string
local function encrypt_failure_reason(result)
	local stderr = vim.trim(result.stderr or "")

	return stderr ~= "" and stderr or "encryption failed"
end

--- Converts startup or process outcomes into a consistent result/error pair.
--- A missing result means no process completed; err is nil when startup was
--- cancelled without an error. A completed process succeeds only with code 0.
--- @param result vim.SystemCompleted? nil if no process completed
--- @param err string? startup error, or nil for cancellation / completed process
--- @param reason fun(result: vim.SystemCompleted): string
--- @return vim.SystemCompleted? result the successful process result, or nil
--- @return string? err the failure reason, or nil on success or cancellation
local function process_result(result, err, reason)
	if not result then
		return nil, err
	end

	if result.code ~= 0 then
		return nil, reason(result)
	end

	return result
end

--- Encrypts content from stdin.
--- Returns true on success, or false and an optional error on failure.
--- If the passphrase prompt is dismissed, returns false, nil.
---@param path string
---@param input string[]
---@param bufnr? integer buffer holding the passphrase of a passphrase note
---@param opts? GpgEncryptOpts
---@return boolean success
---@return string? err the failure reason, or nil when cancelled
function M.encrypt_from_stdin(path, input, bufnr, opts)
	local result, err = gpg.encrypt(path, input, vim.tbl_extend("force", opts or {}, { bufnr = bufnr }))
	local completed, reason = process_result(result, err, encrypt_failure_reason)

	return completed ~= nil, reason
end

--- Decrypts a file and returns its completed process result.
--- On failure, returns nil and an error; dismissing the passphrase prompt
--- returns nil, nil.
--- @param path string The path to the encrypted file.
--- @param bufnr? integer buffer to remember a symmetric passphrase in.
--- @return vim.SystemCompleted? result the successful decrypt, nil otherwise
--- @return string? err the reason to report, nil when there is nothing to say
function M.decrypt_to_stdout(path, bufnr)
	local obj, err = gpg.decrypt(path, bufnr)

	return process_result(obj and obj:wait(), err, decrypt_failure_reason)
end

--- Appends lines to a buffer, replacing its content on the first write.
--- Returns whether the next write should replace the buffer.
---@param bufnr integer
---@param lines string[]
---@param first_write boolean
---@return boolean first_write
local function append_to_buffer(bufnr, lines, first_write)
	if not vim.api.nvim_buf_is_valid(bufnr) or (#lines == 0 and not first_write) then
		return first_write
	end

	vim.bo[bufnr].modifiable = true

	if first_write then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	elseif #lines > 0 then
		vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
	end

	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].modified = false

	return false
end

--- Splits buffered output into complete lines, retaining any unterminated
--- tail for the next batch. When emit_partial is true, also emits that tail
--- (used when the stream ends). This helper does not access editor or process state.
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

--- Decrypts a file into a buffer while streaming stdout.
--- Calls on_exit once the operation finishes, including startup failures and
--- passphrase cancellation; cancellation is reported as nil, nil. The returned
--- process object is nil when no process started.
--- @param path string The path to the encrypted file.
--- @param bufnr integer The buffer handle to write into.
--- @param on_exit fun(result: vim.SystemCompleted?, err: string?)
--- @return vim.SystemObj? obj the decrypt process, nil when none started
function M.decrypt_to_buffer(path, bufnr, on_exit)
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

	local function finish(result, err)
		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end

			if result then
				drain(true)
			end
			vim.bo[bufnr].modifiable = false
			vim.bo[bufnr].modified = false
			on_exit(result, err)
		end)
	end

	local obj, startup_err = gpg.decrypt(path, bufnr, {
		stdout = function(_, data)
			if not data or data == "" then
				return
			end

			pending[#pending + 1] = data

			-- Flush only when a complete line arrives; chunks without a newline
			-- stay buffered until a later chunk completes the line.
			if not scheduled and data:find("\n", 1, true) then
				scheduled = true
				vim.schedule(flush)
			end
		end,
	}, function(result)
		local ok, err = process_result(result, nil, decrypt_failure_reason)
		finish(ok, err)
	end)

	if not obj then
		-- No process callback will run if startup was cancelled or failed.
		-- Finish through the same scheduled path used for process completion.
		finish(nil, startup_err)
	end

	return obj
end

return M
