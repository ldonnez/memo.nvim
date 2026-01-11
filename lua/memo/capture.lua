local core = require("memo.core")
local utils = require("memo.utils")
local Template = require("memo.capture_template")
local memo_config = require("memo.config")
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

---Ensures relative directories are created from given capture file path.
---@param file string -- capture file path
local function ensure_directories(file)
	local dir = vim.fn.fnamemodify(file, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		local success, err = pcall(vim.fn.mkdir, dir, "p")
		if not success then
			message.error("Error: %s", tostring(err))
			return
		end
	end
end

---@param config CaptureConfig
---@return integer win
---@return integer buf
local function create_capture_window(config)
	local base = config.capture_file:gsub("%.gpg$", "")
	local buf = vim.api.nvim_create_buf(false, true)

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

	return win, buf
end

---@param lines string[] The new lines from the capture window
---@param config CaptureConfig
---@param capture_template MemoCaptureTemplate
local function append_capture(lines, config, capture_template)
	local notes_dir = vim.fn.expand(memo_config.notes_dir)
	local file = utils.get_gpg_path(vim.fn.expand(notes_dir .. "/" .. config.capture_file))

	if vim.fn.filereadable(file) == 0 then
		-- Ensure relative directories are created
		ensure_directories(file)

		local merged = capture_template:merge_with_content({}, lines)
		core.encrypt_from_stdin(file, merged)
		return
	end

	local read_result = core.decrypt_to_stdout(file)

	if not read_result or (read_result and read_result.code ~= 0) then
		message.error("Capture failed: decryption error")
		return
	end

	local existing = vim.split(read_result.stdout or "", "\n", { plain = true })

	if read_result.stdout and read_result.stdout:sub(-1, -1) == "\n" then
		if #existing > 0 and existing[#existing] == "" then
			table.remove(existing)
		end
	end

	local merged = capture_template:merge_with_content(existing, lines)

	core.encrypt_from_stdin(file, merged)
end

---@param opts CaptureConfig?
function M.register(opts)
	local config = vim.tbl_deep_extend("force", defaults, opts or {})

	local capture_template = Template.new(config.capture_template)

	local initial_lines, cursor_pos = capture_template:resolve_template()

	local win, buf = create_capture_window(config)

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
	vim.api.nvim_win_set_cursor(win, cursor_pos)

	vim.bo[buf].modified = false

	vim.api.nvim_create_autocmd({ "BufWriteCmd" }, {
		buffer = buf,
		once = true,
		callback = function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

			local current_content = table.concat(lines, "\n")

			local has_changed = not vim.deep_equal(lines, initial_lines)
			local is_not_empty = current_content:gsub("%s+", "") ~= ""

			if has_changed and is_not_empty then
				append_capture(lines, config, capture_template)
			else
				message.warn("Capture aborted: empty content")
			end
			vim.api.nvim_buf_delete(buf, { force = true })
		end,
	})
end

return M
