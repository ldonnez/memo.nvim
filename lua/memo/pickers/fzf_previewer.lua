local crypto = require("memo.crypto")
local utils = require("memo.utils")

local M = {}

---The filetype of a note, based on its name without the note extension, so a
---"note.md.asc" previews as markdown instead of asciidoc.
---@param path string
---@return string?
local function get_filetype(path)
	local filetype = vim.filetype.match({
		filename = utils.strip_extension(path),
	})
	return filetype
end

---Displays a message in a valid preview buffer.
---@param bufnr integer
---@param message string
local function show_preview_message(bufnr, message)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { message })
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].modified = false
end

---Creates the custom fzf-lua previewer class.
---@param builtin any
---@return any
local function create_previewer(builtin)
	local GpgPreviewer = builtin.buffer_or_file:extend()

	function GpgPreviewer:new(o, opts, fzf_win)
		GpgPreviewer.super.new(self, o, opts, fzf_win)
		setmetatable(self, GpgPreviewer)

		return self
	end

	---Decrypts an encrypted note that is not open in a buffer into the preview
	---buffer asynchronously. A note already open uses the builtin previewer.
	---@param entry_str string
	function GpgPreviewer:populate_preview_buf(entry_str)
		-- Every invocation invalidates callbacks from earlier preview requests,
		-- even if the selection later returns to the same note.
		self._preview_request_id = (self._preview_request_id or 0) + 1
		local request_id = self._preview_request_id

		-- Stop any previous asynchronous preview job.
		self:_stop_preview_job()

		local entry = self:entry_to_file(entry_str)
		local path = entry.path
		local is_loaded = entry.bufnr and vim.api.nvim_buf_is_loaded(entry.bufnr)

		if not (path and not is_loaded and utils.is_armored_gpg(path)) then
			return GpgPreviewer.super.populate_preview_buf(self, entry_str)
		end

		if not self.win or not self.win:validate_preview() then
			return
		end

		entry.tick = utils.file_signature(path)
		entry.filetype = get_filetype(path)

		self._last_entry = entry_str

		-- Without a reliable file signature, do not reuse cached plaintext.
		if entry.tick then
			local cached, stale = self.bcache:check(entry)

			if cached and not stale and vim.api.nvim_buf_is_valid(cached.bufnr) then
				self:_apply_cached_preview(entry, cached)
				return
			end
		end

		local tmpbuf = self:get_tmp_buffer()

		show_preview_message(tmpbuf, "Decrypting...")

		self:set_preview_buf(tmpbuf)

		local function is_current_request()
			return self._preview_request_id == request_id
				and self._last_entry == entry_str
				and vim.api.nvim_buf_is_valid(tmpbuf)
		end

		local obj = crypto.decrypt_to_buffer(path, tmpbuf, function(result)
			-- Ignore callbacks from cancelled or superseded preview requests.
			if not is_current_request() then
				return
			end

			if result.code ~= 0 then
				-- vim.system reports a timed-out command with exit code 124.
				-- This identifies the command timeout, not necessarily
				-- termination of any subprocesses it may have spawned.
				local reason = result.code == 124 and "timed out" or "failed"

				show_preview_message(tmpbuf, "Decryption " .. reason)
			else
				self:preview_buf_post(entry)
			end

			-- Do not clear a newer request's stop handler.
			if self._preview_request_id == request_id then
				self.stop_job = nil
			end
		end)

		if not obj then
			-- The user dismissed the passphrase prompt.
			-- Keep the preview buffer valid.
			if is_current_request() then
				show_preview_message(tmpbuf, "Decryption cancelled")
			end

			return
		end

		-- Wiping the preview buffer cancels the subprocess. The request token
		-- prevents its eventual callback from updating a later preview.
		vim.api.nvim_create_autocmd("BufWipeout", {
			buffer = tmpbuf,
			once = true,
			callback = function()
				if self._preview_request_id == request_id then
					self._preview_request_id = request_id + 1
					self.stop_job = nil
				end

				pcall(obj.kill, obj, 15)
			end,
		})

		self.stop_job = function()
			pcall(obj.kill, obj, 15)
		end
	end

	return GpgPreviewer
end

---Returns the custom previewer class, loading fzf-lua only when needed.
---@return any
function M.build()
	if M._previewer then
		return M._previewer
	end

	local builtin = utils.load_plugin("fzf-lua.previewer.builtin", "fzf-lua")

	if not builtin then
		return nil
	end

	M._previewer = create_previewer(builtin)

	return M._previewer
end

return M
