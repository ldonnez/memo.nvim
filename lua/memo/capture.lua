local crypto = require("memo.crypto")
local utils = require("memo.utils")
local memo_config = require("memo.config")
local Template = require("memo.note_template")
local message = require("memo.message")
local window = require("memo.window")

local M = {}

---@class CaptureConfig
---@field capture_file string
---@field target_header string? header the capture is inserted under
---@field header_padding integer? blank lines kept between the header and the capture
---@field template? string window template, supports `os.date` formats and a `|`
---cursor marker. A selection is inserted at that marker, and becomes the whole
---capture window when the template has none.
---@field window MemoWindowConfig opens the capture in a split, every option
---has a default

---@type CaptureConfig
local DEFAULTS = {
	capture_file = "inbox.md.gpg",
	header_padding = 0,
	window = {},
}

---@param config CaptureConfig
---@return integer win
---@return integer buf
local function create_capture_window(config)
	local base = config.capture_file:gsub("%.gpg$", "")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_exec_autocmds("BufReadPre", { buffer = buf, modeline = false })

	local win = window.open(config.window)

	vim.api.nvim_win_set_buf(win, buf)

	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].fileencoding = "utf-8"
	vim.bo[buf].filetype = vim.filetype.match({ filename = base })

	vim.api.nvim_buf_set_name(buf, "capture://" .. config.capture_file)
	vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buf, modeline = false })

	return win, buf
end

---@param existing string[]
---@param target_header string?
---@return integer
local function find_target_header_idx(existing, target_header)
	if not target_header or target_header == "" then
		return -1
	end

	for i, line in ipairs(existing) do
		if line == target_header then
			return i
		end
	end

	return -1
end

---Inserts capture lines into the content of the capture file. When a
---`target_header` is configured the block goes right below it, otherwise the
---block is prepended to the top of the file.
---@param existing string[]
---@param new_lines string[]
---@param config CaptureConfig
---@return string[]
local function insert_lines(existing, new_lines, config)
	if #new_lines == 0 then
		return existing
	end

	local header = config.target_header
	local padding = config.header_padding or 0
	local target_idx = find_target_header_idx(existing, header)

	-- Build the "block" to insert
	local block = {}
	if target_idx == -1 and header and header ~= "" then
		table.insert(block, header)
	end
	for _ = 1, padding do
		table.insert(block, "")
	end
	vim.list_extend(block, new_lines)

	-- Construct the result
	local merged = {}
	if target_idx ~= -1 then
		-- Insert after header: [Head] + [Block] + [Tail]
		vim.list_extend(merged, vim.list_slice(existing, 1, target_idx))
		vim.list_extend(merged, block)

		-- Skip exactly one empty line if it follows the header to prevent gaps
		local resume_at = (existing[target_idx + 1] == "") and (target_idx + 2) or (target_idx + 1)
		vim.list_extend(merged, vim.list_slice(existing, resume_at))
	else
		-- Prepend to top: [Block] + [Existing]
		vim.list_extend(merged, block)
		vim.list_extend(merged, existing)
	end

	return merged
end

---@param lines string[] The new lines from the capture window
---@param config CaptureConfig
---@return boolean -- true when the content was saved successfully
local function append_capture(lines, config)
	local notes_dir = memo_config.notes_dir

	local expanded = vim.fn.expand(notes_dir .. "/" .. config.capture_file) --[[@as string]]
	local file = utils.get_gpg_path(expanded)

	if not utils.file_exists(file) then
		-- Ensure relative directories are created
		if not utils.ensure_directories(vim.fs.dirname(file)) then
			return false
		end

		local merged = insert_lines({}, lines, config)
		return crypto.encrypt_from_stdin(file, merged).code == 0
	end

	local read_result = crypto.decrypt_to_stdout(file)

	if not read_result or read_result.code ~= 0 then
		return false
	end

	local existing = vim.split(read_result.stdout or "", "\n", { plain = true })

	if read_result.stdout and read_result.stdout:sub(-1, -1) == "\n" then
		if #existing > 0 and existing[#existing] == "" then
			table.remove(existing)
		end
	end

	local merged = insert_lines(existing, lines, config)

	return crypto.encrypt_from_stdin(file, merged).code == 0
end

---@param opts CaptureConfig
function M.register(opts)
	local cfg = opts --[[@as CaptureConfig]]
	local config = vim.tbl_deep_extend("force", DEFAULTS, cfg) --[[@as CaptureConfig]]

	local capture_template = Template.new({ template = config.template })

	local template_lines, template_cursor, has_cursor_marker = capture_template:resolve_template()

	local bufnr = vim.api.nvim_get_current_buf()
	local range_lines = utils.resolve_selection(bufnr)

	local win, buf = create_capture_window(config)

	---@type string[], [integer, integer]
	local initial_lines, cursor_pos
	if range_lines and has_cursor_marker then
		-- The selection goes where the template asked for it, so a captured
		-- selection keeps the header the template provides.
		initial_lines, cursor_pos = capture_template:insert_at_cursor(range_lines)
	elseif range_lines then
		-- Without a marker there is nowhere to insert, so the selection becomes
		-- the whole capture.
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
				local saved = append_capture(lines, config)

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
