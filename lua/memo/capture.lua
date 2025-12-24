local core = require("memo.core")
local memo_config = require("memo.config")

local M = {}

---@alias CaptureSplit "split" | "vsplit"
---@class CaptureConfig
---@field capture_file string
---@field header string|function
---@field window { split: CaptureSplit }

---@type CaptureConfig
local defaults = {
	capture_file = vim.fn.expand("~/notes" .. "/inbox.md.gpg"),
	header = function()
		return "## " .. os.date("%Y-%m-%d %H:%M")
	end,
	window = {
		split = "split",
	},
}

---@type CaptureConfig
local config = vim.deepcopy(defaults)
---@cast config.capture_file string

---@param header string|function
---@return string
local function resolve_header(header)
	if type(header) == "function" then
		return header()
	end
	return tostring(header)
end

---@param lines string[]
---@param capture_path string
local function append_capture_memo(lines, capture_path)
	if #lines == 0 then
		return
	end

	local file = vim.fn.expand(capture_path)

	-- Try to decrypt without passphrase first (cached)
	local result = core.decrypt_file(file)

	if result and result.code ~= 0 then
		vim.notify("Memo decryption failed: " .. (result.stderr or "Wrong passphrase?"), vim.log.levels.ERROR)
		return
	end

	if not result or result.stdout == nil then
		return
	end

	-- Split output into lines
	local decrypted = vim.split(result.stdout, "\n", { plain = true })
	if decrypted[#decrypted] == "" then
		table.remove(decrypted)
	end

	-- Ensure at least 2 lines
	decrypted[1] = decrypted[1] or ""
	decrypted[2] = decrypted[2] or ""

	local new = {
		decrypted[1],
		decrypted[2],
	}

	-- Insert block (lines + blank line)
	for _, l in ipairs(lines) do
		table.insert(new, l)
	end
	table.insert(new, "")

	-- Append the rest of decrypted (from line 3 onward)
	for i = 3, #decrypted do
		table.insert(new, decrypted[i])
	end

	decrypted = new

	-- Write decrypted + new capture to temp file
	local tmpfile = vim.fn.tempname() .. ".txt"
	local w = io.open(tmpfile, "w")

	if w == nil then
		return
	end

	for _, l in ipairs(decrypted) do
		w:write(l .. "\n")
	end

	w:close()

	local encrypt_result = core.encrypt_file(tmpfile, file)

	if encrypt_result and encrypt_result.code ~= 0 then
		vim.notify("Memo encryption failed", vim.log.levels.ERROR)
	else
		vim.notify("Capture inserted -> " .. file)
	end

	vim.fn.delete(tmpfile)
end

---@param opts CaptureConfig?
function M.register(opts)
	if opts then
		config = vim.tbl_deep_extend("force", defaults, opts)
	end

	local notes_dir = memo_config.options.notes_dir
	local path = vim.fn.expand(notes_dir .. "/" .. config.capture_file)

	if vim.fn.filereadable(path) == 0 then
		local tmp = vim.fn.tempname() .. ".md"
		vim.fn.writefile({ "", "" }, tmp)

		local result = core.encrypt_file(tmp, path)

		if result and result.code ~= 0 then
			vim.notify("Memo Encryption failed: " .. (result.stderr or "Wrong passphrase?"), vim.log.levels.ERROR)
			return
		end

		vim.fn.delete(tmp)
	end

	vim.cmd(config.window.split)
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(win, buf)

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "markdown"
	vim.api.nvim_buf_set_name(buf, "capture://" .. path)

	local header = resolve_header(config.header)
	local initial_lines = { header, "", "" }
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
	vim.api.nvim_win_set_cursor(win, { 3, 0 })

	local has_finished = false
	local group = vim.api.nvim_create_augroup("CaptureMemo_" .. buf, { clear = true })

	local function finalize_capture()
		if has_finished then
			return
		end
		has_finished = true

		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

		-- Abort check
		local is_empty = #lines == 0 or (#lines == 1 and lines[1] == "")
		local only_header = #lines <= #initial_lines and table.concat(lines) == table.concat(initial_lines)

		if is_empty or only_header then
			vim.notify("Capture aborted: empty content", vim.log.levels.WARN)
		else
			-- Process the capture
			append_capture_memo(lines, path)
		end

		-- Safe Buffer Cleanup
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end)
	end

	vim.api.nvim_create_autocmd({ "BufWriteCmd", "BufUnload" }, {
		buffer = buf,
		group = group,
		callback = finalize_capture,
	})
end

return M
