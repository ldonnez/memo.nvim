local core = require("memo.core")
local utils = require("memo.utils")
local events = require("memo.events")
local memo_config = require("memo.config")

local M = {}

---@alias CaptureSplit "split" | "vsplit"
---@class CaptureConfig
---@field capture_file string
---@field header string|function
---@field window { split: CaptureSplit }

---@type CaptureConfig
local defaults = {
	capture_file = "inbox.md.gpg",
	header = function()
		return "## " .. os.date("%Y-%m-%d %H:%M")
	end,
	window = {
		split = "split",
	},
}

---@param header string|function
---@return string
local function resolve_header(header)
	if type(header) == "function" then
		return header()
	end
	return tostring(header)
end

---@param lines string[] The new lines from the capture window
---@param capture_path string
local function append_capture_memo(lines, capture_path)
	if #lines == 0 then
		return
	end
	local file = vim.fn.expand(capture_path)
	local temp_buf = vim.api.nvim_create_buf(false, true)

	-- 1. Async Decrypt
	core.decrypt_to_buffer(file, temp_buf, function(read_result)
		if read_result.code ~= 0 then
			vim.schedule(function()
				vim.notify("Capture failed: Decrypt error", vim.log.levels.ERROR)
			end)
			return
		end

		vim.schedule(function()
			-- 2. Extract and Merge (Main thread)
			local existing = vim.api.nvim_buf_get_lines(temp_buf, 0, -1, false)
			local merged = utils.merge_content(existing, lines)

			-- Cleanup temp buffer now that we have the data
			if vim.api.nvim_buf_is_valid(temp_buf) then
				vim.api.nvim_buf_delete(temp_buf, { force = true })
			end

			-- 3. Async Encrypt
			core.encrypt_from_stdin(file, merged, function(write_result)
				if write_result.code == 0 then
					vim.notify("Capture saved", vim.log.levels.INFO)
				else
					vim.notify("Capture failed: Encrypt error", vim.log.levels.ERROR)
				end

				events.emit(events.types.CAPTURE_DONE)
			end)
		end)
	end)
end

---@param opts CaptureConfig?
function M.register(opts)
	local config = vim.tbl_deep_extend("force", defaults, opts or {})
	local path = utils.get_gpg_path(memo_config.notes_dir .. "/" .. config.capture_file)

	-- Ensure capture file exists, otherwise create
	if vim.fn.filereadable(path) == 0 then
		core.encrypt_from_stdin(path, { "", "" })
	end

	-- UI Setup
	vim.cmd(config.window.split)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(0, buf)

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "markdown"
	vim.api.nvim_buf_set_name(buf, "capture://" .. path)

	local initial_lines = { resolve_header(config.header), "", "" }
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
	vim.api.nvim_win_set_cursor(0, { 3, 0 })

	vim.api.nvim_create_autocmd({ "BufWriteCmd", "BufUnload" }, {
		buffer = buf,
		once = true,
		callback = function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

			-- Abort when capture window contains only the header or is empty
			if #lines > 3 or (lines[3] and lines[3] ~= "") then
				append_capture_memo(lines, path)
			else
				vim.notify("Capture aborted: empty content", vim.log.levels.WARN)
				events.emit(events.types.CAPTURE_DONE)
				return
			end

			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(buf) then
					vim.api.nvim_buf_delete(buf, { force = true })
				end
			end)
		end,
	})
end

return M
