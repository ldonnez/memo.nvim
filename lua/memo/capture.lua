local core = require("memo.core")
local utils = require("memo.utils")
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

---@param lines string[] The new lines from the capture window
---@param config CaptureConfig
local function append_capture(lines, config)
	local notes_dir = vim.fn.expand(memo_config.notes_dir)
	local file = utils.get_gpg_path(vim.fn.expand(notes_dir .. "/" .. config.capture_file))

	if vim.fn.filereadable(file) == 0 then
		-- Ensure relative directories are created
		ensure_directories(file)

		local merged = capture_template.merge_with_content({}, lines, config.capture_template)
		core.encrypt_from_stdin(file, merged)
		return
	end

	local read_result = core.decrypt_to_stdout(file)

	if not read_result or (read_result and read_result.code ~= 0) then
		vim.notify("Capture failed: Decrypt error", vim.log.levels.ERROR)
		return
	end

	local existing = vim.split(read_result.stdout or "", "\n", { plain = true })
	local merged = capture_template.merge_with_content(existing, lines, config.capture_template)

	core.encrypt_from_stdin(file, merged)
end

---@param opts CaptureConfig?
function M.register(opts)
	local config = vim.tbl_deep_extend("force", defaults, opts or {})

	local initial_lines, cursor_pos = capture_template.resolve_header(config.capture_template)
	vim.cmd(config.window.split)
	local base = config.capture_file:gsub("%.gpg$", "")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(0, buf)

	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = vim.filetype.match({ filename = base })
	vim.api.nvim_buf_set_name(buf, "capture://" .. config.capture_file)

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
	vim.api.nvim_win_set_cursor(0, cursor_pos)

	vim.bo[buf].modified = false

	vim.api.nvim_create_autocmd({ "BufWriteCmd" }, {
		buffer = buf,
		once = true,
		callback = function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

			local current_content = table.concat(lines, "\n")
			local template_content = table.concat(initial_lines, "\n")

			local has_changed = current_content ~= template_content
			local is_not_empty = current_content:gsub("%s+", "") ~= ""

			if has_changed and is_not_empty then
				append_capture(lines, config)
			else
				vim.notify("Capture aborted: empty content", vim.log.levels.WARN)
			end
			vim.api.nvim_buf_delete(buf, { force = true })
		end,
	})
end

return M
