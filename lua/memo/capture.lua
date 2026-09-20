local core = require("memo.core")
local utils = require("memo.utils")
local memo_config = require("memo.config")
local Template = require("memo.capture_template")
local message = require("memo.message")

local M = {}
---@alias CaptureSplit "split" | "vsplit"
---@alias CapturePosition "botright" | "topleft" | "leftabove" | "rightbelow"

---@class CaptureConfig
---@field capture_file string
---@field capture_template MemoCaptureTemplateConfig
---@field window { split: CaptureSplit, size: integer, position: CapturePosition }

---@type CaptureConfig
local defaults = {
	capture_file = "inbox.md.gpg",
	capture_template = {},
	window = {
		split = "split",
		size = 10,
		position = "botright",
	},
}

---@param config CaptureConfig
---@return integer win
---@return integer buf
local function create_capture_window(config)
	local base = config.capture_file:gsub("%.gpg$", "")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_exec_autocmds("BufReadPre", { buffer = buf, modeline = false })

	local cmd = string.format("%s %d%s", config.window.position, config.window.size, config.window.split)
	vim.cmd(cmd)

	local win = vim.api.nvim_get_current_win()

	vim.api.nvim_win_set_buf(win, buf)

	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].fileencoding = "utf-8"
	vim.bo[buf].filetype = vim.filetype.match({ filename = base })

	if config.window.split == "vsplit" then
		vim.wo[win].winfixwidth = true
	else
		vim.wo[win].winfixheight = true
	end

	vim.api.nvim_buf_set_name(buf, "capture://" .. config.capture_file)
	vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buf, modeline = false })

	return win, buf
end

---@param lines string[] The new lines from the capture window
---@param config CaptureConfig
---@param capture_template MemoCaptureTemplate
---@return boolean -- true when the content was saved successfully
local function append_capture(lines, config, capture_template)
	local notes_dir = memo_config.notes_dir

	local expanded = vim.fn.expand(notes_dir .. "/" .. config.capture_file) --[[@as string]]
	local file = utils.get_gpg_path(expanded)

	if vim.fn.filereadable(file) == 0 then
		-- Ensure relative directories are created
		if not utils.ensure_directories(vim.fs.dirname(file)) then
			return false
		end

		local merged = capture_template:merge_with_content({}, lines)
		return core.encrypt_from_stdin(file, merged).code == 0
	end

	local read_result = core.decrypt_to_stdout(file)

	if not read_result or read_result.code ~= 0 then
		return false
	end

	local existing = vim.split(read_result.stdout or "", "\n", { plain = true })

	if read_result.stdout and read_result.stdout:sub(-1, -1) == "\n" then
		if #existing > 0 and existing[#existing] == "" then
			table.remove(existing)
		end
	end

	local merged = capture_template:merge_with_content(existing, lines)

	return core.encrypt_from_stdin(file, merged).code == 0
end

---Resolves the current buffer's visual selection into its lines.
---@return string[]|nil
local function resolve_selection()
	if not vim.fn.mode():match("[vV\22]") then
		return nil
	end

	local start = vim.fn.getpos("v")
	local finish = vim.fn.getpos(".")

	if start[2] == 0 or finish[2] == 0 then
		return nil
	end

	return vim.fn.getregion(start, finish)
end

---@param opts CaptureConfig
function M.register(opts)
	local cfg = opts --[[@as CaptureConfig]]
	local config = vim.tbl_deep_extend("force", defaults, cfg) --[[@as CaptureConfig]]

	local capture_template = Template.new(config.capture_template)

	local template_lines, template_cursor = capture_template:resolve_template()

	local range_lines = resolve_selection()

	local win, buf = create_capture_window(config)

	local initial_lines, cursor_pos
	if range_lines then
		initial_lines = range_lines
		cursor_pos = { #initial_lines, 0 }
	else
		initial_lines = template_lines
		cursor_pos = template_cursor
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
	vim.api.nvim_win_set_cursor(win, cursor_pos)

	vim.bo[buf].modified = false

	vim.api.nvim_create_autocmd({ "BufWriteCmd" }, {
		buffer = buf,
		callback = function()
			vim.api.nvim_exec_autocmds("BufWritePre", { buffer = buf, modeline = false })
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

			local has_changed = not vim.deep_equal(lines, template_lines)
			local is_not_empty = table.concat(lines, "\n"):gsub("%s+", "") ~= ""

			if has_changed and is_not_empty then
				local saved = append_capture(lines, config, capture_template)

				if not saved then
					-- Keep the buffer so the content is not silently lost.
					message.defer_error("Capture failed: content was not saved")
					return
				end
			else
				message.warn("Capture aborted: empty content")
			end

			vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf, modeline = false })
			vim.api.nvim_buf_delete(buf, { force = true })
		end,
	})
end

return M
