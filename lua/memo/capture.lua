local core = require("memo.core")
local utils = require("memo.utils")
local events = require("memo.events")
local capture_template = require("memo.capture_template")
local memo_config = require("memo.config")

local M = {}

---@alias CaptureSplit "split" | "vsplit"
---@class CaptureConfig
---@field capture_file string
---@field capture_template MemoCaptureTemplateConfig
---@field window { split: CaptureSplit }

---@type CaptureConfig
local defaults = {
	capture_file = "inbox.md.gpg",
	capture_template = capture_template.defaults,
	window = {
		split = "split",
	},
}

---Ensures relative directories are created from given capture file path.
---@param file string -- capture file path
local function ensure_directories(file)
	local dir = vim.fn.fnamemodify(file, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		local success, err = pcall(vim.fn.mkdir, dir, "p")
		if not success then
			vim.notify("Memo: Could not create directory " .. dir .. "\nError: " .. tostring(err), vim.log.levels.ERROR)
			return
		end
	end
end

---@param result vim.SystemCompleted
local function on_encrypt_done(result)
	if result.code == 0 then
		vim.notify("Capture saved", vim.log.levels.INFO)
	else
		vim.notify("Capture failed: Encrypt error", vim.log.levels.ERROR)
	end
end

---@param bufnr integer
local function on_capture_done(bufnr)
	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end
	events.emit(events.types.CAPTURE_DONE)
end

---@param lines string[] The new lines from the capture window
---@param config CaptureConfig
---@param on_done fun() callback triggered after encryption completes
local function append_capture(lines, config, on_done)
	if #lines == 0 then
		on_done()
		return
	end

	local notes_dir = vim.fn.expand(memo_config.notes_dir)
	local file = utils.get_gpg_path(vim.fn.expand(notes_dir .. "/" .. config.capture_file))
	local temp_buf = vim.api.nvim_create_buf(false, true)

	if vim.fn.filereadable(file) == 0 then
		-- Ensure relative directories are created
		ensure_directories(file)

		local merged = capture_template.merge_with_content({}, lines, config.capture_template)

		core.encrypt_from_stdin(file, merged, function(result)
			on_encrypt_done(result)
			on_done()
		end)
		return
	end

	core.decrypt_to_buffer(file, temp_buf, function(read_result)
		if read_result.code ~= 0 then
			vim.notify("Capture failed: Decrypt error", vim.log.levels.ERROR)
			on_done()
			return
		end

		vim.schedule(function()
			local existing = vim.api.nvim_buf_get_lines(temp_buf, 0, -1, false)
			local merged = capture_template.merge_with_content(existing, lines, config.capture_template)

			if vim.api.nvim_buf_is_valid(temp_buf) then
				vim.api.nvim_buf_delete(temp_buf, { force = true })
			end

			core.encrypt_from_stdin(file, merged, function(result)
				on_encrypt_done(result)
				on_done()
			end)
		end)
	end)
end

---@param opts CaptureConfig?
function M.register(opts)
	local config = vim.tbl_deep_extend("force", defaults, opts or {})

	local initial_lines, cursor_pos = capture_template.resolve_header(config.capture_template)
	vim.cmd(config.window.split)
	local base = config.capture_file:gsub("%.gpg$", "")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(0, buf)

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = vim.filetype.match({ filename = base })
	vim.api.nvim_buf_set_name(buf, "capture://" .. config.capture_file)

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
	vim.api.nvim_win_set_cursor(0, cursor_pos)
	vim.cmd("startinsert!")

	vim.api.nvim_create_autocmd({ "BufWriteCmd", "BufUnload" }, {
		buffer = buf,
		once = true,
		callback = function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

			local current_content = table.concat(lines, "\n")
			local template_content = table.concat(initial_lines, "\n")

			local has_changed = current_content ~= template_content
			local is_not_empty = current_content:gsub("%s+", "") ~= ""

			if has_changed and is_not_empty then
				append_capture(lines, config, function()
					on_capture_done(buf)
				end)
				return
			else
				vim.notify("Capture aborted: empty content", vim.log.levels.WARN)
				events.emit(events.types.CAPTURE_DONE)
				return
			end
		end,
	})
end

return M
