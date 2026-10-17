local crypto = require("memo.crypto")
local utils = require("memo.utils")
local builtin = utils.load_plugin("fzf-lua.previewer.builtin", "fzf-lua")

if not builtin then
	return
end

local GpgPreviewer = builtin.buffer_or_file:extend()

function GpgPreviewer:new(o, opts, fzf_win)
	GpgPreviewer.super.new(self, o, opts, fzf_win)
	setmetatable(self, GpgPreviewer)

	return self
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

---Decrypts an encrypted note that is not open in a buffer into the preview
---buffer asynchronously. A note already open uses the builtin previewer.
---@param entry_str string
function GpgPreviewer:populate_preview_buf(entry_str)
	-- Invalidate callbacks from earlier preview requests.
	self._preview_request_id = (self._preview_request_id or 0) + 1
	local request_id = self._preview_request_id

	self:_stop_preview_job()

	local entry = self:entry_to_file(entry_str)
	local path = entry.path

	if not (path and utils.is_armored_gpg(path)) then
		return GpgPreviewer.super.populate_preview_buf(self, entry_str)
	end

	entry.tick = utils.file_signature(path)
	entry.filetype = utils.get_filetype(path)
	entry.do_not_cache = entry.tick == nil

	self._last_entry = entry_str

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
		return self._preview_request_id == request_id and vim.api.nvim_buf_is_valid(tmpbuf)
	end

	local obj = crypto.decrypt_to_buffer(path, tmpbuf, function(result, err)
		if not is_current_request() then
			return
		end

		if result then
			self:preview_buf_post(entry)
		else
			-- Cancellation is quiet; failures show their reason.
			show_preview_message(tmpbuf, err or "")
		end

		if self._preview_request_id == request_id then
			self.stop_job = nil
		end
	end)

	-- Cancellation or startup failure means no subprocess exists to cancel.
	-- The callback handles that outcome, so only install cleanup for a real job.
	if not obj then
		return
	end

	-- Wiping the buffer cancels the subprocess.
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
