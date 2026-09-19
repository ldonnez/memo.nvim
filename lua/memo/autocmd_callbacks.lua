local M = {}

---@param path string
---@return boolean
local function is_ignored(path)
	-- `glob2regpat` turns a leading `**` into a regex anchored on a path
	-- separator (`/\.gitignore`), so the subject must be absolute for the
	-- pattern to match a bare basename (e.g. `args.file == ".gitignore"`).
	local absolute = vim.fn.fnamemodify(path, ":p")
	local config = require("memo.config")
	local ignore_patterns = config.ignore_patterns()

	for _, pattern in ipairs(ignore_patterns) do
		if vim.fn.match(absolute, vim.fn.glob2regpat(pattern)) >= 0 then
			return true
		end
	end

	return false
end

--- @param bufnr integer
local function prepare_buffer_for_edit(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].undofile = false

	-- Ensure the user can edit
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].fileencoding = "utf-8"
	vim.bo[bufnr].modified = false

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	vim.b[bufnr].hash = vim.fn.sha256(table.concat(lines, "\n"))
	vim.b[bufnr].decrypting = false
end

---@param path string
---@return boolean
local function is_armored_gpg(path)
	local lines = vim.fn.readfile(path, "b", 1)

	return lines[1] == "-----BEGIN PGP MESSAGE-----"
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
	local core = require("memo.core")
	local message = require("memo.message")

	-- Force filetype detection based on the name without .gpg
	local base = args.file:gsub("%.gpg$", "")
	vim.bo[bufnr].filetype = vim.filetype.match({ filename = base })

	if is_ignored(args.file) then
		read_regular_file(bufnr, vim.fn.fnameescape(args.file))
		return
	end

	local gpg_path = utils.get_gpg_path(args.file)

	-- If the .gpg file doesn't exist, it's new, just open it
	if vim.fn.filereadable(gpg_path) == 0 or vim.fn.getfsize(gpg_path) <= 0 then
		-- Read file - the regular way - into buffer
		vim.cmd("silent edit " .. vim.fn.fnameescape(args.file))
		vim.bo[bufnr].modifiable = true
		vim.b[bufnr].decrypting = false

		vim.api.nvim_exec_autocmds("BufNewFile", { buffer = bufnr, modeline = false })
		return
	end

	if not is_armored_gpg(gpg_path) then
		read_regular_file(bufnr, vim.fn.fnameescape(args.file))
		return
	end

	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].modified = false
	vim.b[bufnr].decrypting = true
	vim.api.nvim_exec_autocmds("BufReadPre", { buffer = bufnr, modeline = false })

	core.decrypt_to_buffer(args.file, bufnr, function(result)
		if result.code ~= 0 then
			vim.api.nvim_buf_delete(bufnr, { force = true })
			message.error("Decryption failed")
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
	local core = require("memo.core")
	local message = require("memo.message")

	if is_ignored(args.file) then
		write_regular_file(bufnr)
		return
	end

	if vim.b[bufnr].decrypting then
		return
	end

	local gpg_path = utils.get_gpg_path(args.file)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local current_hash = vim.fn.sha256(table.concat(lines, "\n"))

	if current_hash == vim.b[bufnr].hash then
		message.info("No changes detected")
		vim.bo[bufnr].modified = false
		return
	end
	vim.api.nvim_exec_autocmds("BufWritePre", { buffer = bufnr, modeline = false })

	local result = core.encrypt_from_stdin(gpg_path, lines)

	if result.code == 0 then
		if args.file ~= gpg_path then
			-- If saving a plain text file for the first time, delete the unencrypted original and change the buffer to the new .gpg path.
			if vim.fn.filereadable(args.file) == 1 then
				vim.fn.delete(args.file)
			end
			vim.api.nvim_buf_set_name(bufnr, gpg_path)
		end

		prepare_buffer_for_edit(bufnr)
	end

	vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr, modeline = false })
end

return M
