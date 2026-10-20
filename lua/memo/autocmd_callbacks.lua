local M = {}

---@param path string
---@return boolean
local function is_ignored(path)
	-- `glob2regpat` anchors a leading `**` on a path separator, so the subject
	-- must be absolute to match a bare basename.
	local absolute = vim.fn.fnamemodify(path, ":p")
	local config = require("memo.config")
	local ignore_patterns = config.ignore_patterns

	for _, pattern in ipairs(ignore_patterns) do
		if vim.fn.match(absolute, vim.fn.glob2regpat(pattern)) >= 0 then
			return true
		end
	end

	return false
end

---A directory is not a note: resolving one notifies at ERROR level, which
---raises inside an autocmd.
---@param path string
---@return boolean
local function is_directory(path)
	return vim.fn.isdirectory(path) == 1
end

---@param bufnr integer
local function prepare_buffer(bufnr)
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].undofile = false
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].fileencoding = "utf-8"
	vim.bo[bufnr].modified = false
	vim.b[bufnr].decrypting = false
end

---@param bufnr integer
---@param file string
local function prepare_new_file(bufnr, file)
	prepare_buffer(bufnr)

	vim.api.nvim_exec_autocmds("BufNewFile", {
		buffer = bufnr,
		modeline = false,
	})

	vim.bo[bufnr].buftype = "acwrite"
	vim.bo[bufnr].filetype = require("memo.utils").get_filetype(file) or ""
end

---@param bufnr integer
local function prepare_buffer_for_edit(bufnr)
	prepare_buffer(bufnr)

	-- Regular buffers restore correctly from sessions.
	vim.bo[bufnr].buftype = ""

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	vim.b[bufnr].hash = vim.fn.sha256(table.concat(lines, "\n"))
end

--- @param bufnr integer
local function write_regular_file(bufnr)
	vim.api.nvim_exec_autocmds("BufWritePre", {
		buffer = bufnr,
		modeline = false,
	})

	vim.cmd("silent noautocmd write")

	vim.api.nvim_exec_autocmds("BufWritePost", {
		buffer = bufnr,
		modeline = false,
	})
end

--- @param bufnr integer
--- @param path string
local function read_regular_file(bufnr, path)
	vim.api.nvim_exec_autocmds("BufReadPre", {
		buffer = bufnr,
		modeline = false,
	})

	vim.cmd("silent noautocmd edit " .. vim.fn.fnameescape(path))

	vim.api.nvim_exec_autocmds("BufReadPost", {
		buffer = bufnr,
		modeline = false,
	})
end

--- @param args vim.api.keyset.create_autocmd.callback_args
function M.on_read(args)
	local bufnr = args.buf
	local utils = require("memo.utils")
	local crypto = require("memo.crypto")
	local file = vim.fn.fnamemodify(args.file, ":p")

	if is_directory(file) then
		return
	end

	if is_ignored(file) then
		read_regular_file(bufnr, file)
		return
	end

	if not utils.file_exists(file) or not utils.file_has_content(file) then
		prepare_new_file(bufnr, file)
		return
	end

	-- Existing non-encrypted files should be loaded normally.
	if not utils.is_armored_gpg(file) then
		read_regular_file(bufnr, file)
		return
	end

	local note_path = utils.resolve_note_file(file)

	vim.bo[bufnr].filetype = utils.get_filetype(file) or ""

	-- Do not allow plaintext produced by asynchronous decryption to reach swap
	-- or persistent undo files before prepare_buffer_for_edit() runs.
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].undofile = false
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].modified = false
	vim.b[bufnr].decrypting = true
	vim.api.nvim_exec_autocmds("BufReadPre", { buffer = bufnr, modeline = false })

	crypto.decrypt_to_buffer(note_path, bufnr, function(result, err)
		if not result then
			if err then
				utils.drop_buffer_with_error(bufnr, err)
				return
			end

			-- A dismissed prompt is a cancellation, not an error: wipe quietly.
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(bufnr) then
					vim.api.nvim_buf_delete(bufnr, { force = true })
				end
			end)
			return
		end

		vim.schedule(function()
			prepare_buffer_for_edit(bufnr)
		end)
	end)

	vim.api.nvim_exec_autocmds("BufReadPost", { buffer = bufnr, modeline = false })
end

--- @param args vim.api.keyset.create_autocmd.callback_args
function M.on_write(args)
	local bufnr = args.buf
	local utils = require("memo.utils")
	local crypto = require("memo.crypto")
	local message = require("memo.message")
	local file = vim.fn.fnamemodify(args.file, ":p")

	if is_directory(file) then
		return
	end

	if is_ignored(file) then
		write_regular_file(bufnr)
		return
	end

	if vim.b[bufnr].decrypting then
		return
	end

	local note_path = utils.resolve_note_file(file)

	vim.api.nvim_exec_autocmds("BufWritePre", { buffer = bufnr, modeline = false })

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local current_hash = vim.fn.sha256(table.concat(lines, "\n"))

	if current_hash == vim.b[bufnr].hash then
		message.info("No changes detected")
		vim.bo[bufnr].modified = false
		return
	end

	local result, err = crypto.encrypt_from_stdin(note_path, lines, bufnr)

	if not result then
		-- A dismissed prompt has no reason: a cancellation, nothing to report.
		if err then
			message.defer_error("%s", err)
		end
		return
	end

	if file ~= note_path then
		if utils.file_exists(file) then
			vim.fn.delete(file)
		end

		vim.api.nvim_buf_set_name(bufnr, note_path)
	end

	prepare_buffer_for_edit(bufnr)

	vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr, modeline = false })
end

return M
