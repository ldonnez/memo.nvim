local M = {}

---@param path string
---@return boolean
local function is_ignored(path)
	-- `glob2regpat` turns a leading `**` into a regex anchored on a path
	-- separator (`/\.gitignore`), so the subject must be absolute for the
	-- pattern to match a bare basename (e.g. `args.file == ".gitignore"`).
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

---A directory is not a note: opening one asks for a listing, and resolving it
---as a note would notify at ERROR level, which raises inside an autocmd and
---aborts the read.
---@param path string
---@return boolean
local function is_directory(path)
	return vim.fn.isdirectory(path) == 1
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

	-- Normalize to an absolute path: `args.file` can be relative and padding it
	-- with `:p` keeps every downstream path comparison consistent.
	local file = vim.fn.fnamemodify(args.file, ":p")

	if is_directory(file) then
		return
	end

	local note_path = utils.resolve_note_file(file)

	-- Force filetype detection based on the name without the note extension
	local base = utils.strip_extension(file)
	vim.bo[bufnr].filetype = vim.filetype.match({ filename = base })

	if is_ignored(file) then
		read_regular_file(bufnr, file)
		return
	end

	-- If the encrypted note doesn't exist, it's new, just open it
	if not utils.file_has_content(note_path) then
		-- Read file - the regular way - into buffer
		vim.cmd("silent edit " .. vim.fn.fnameescape(file))
		vim.bo[bufnr].modifiable = true
		vim.b[bufnr].decrypting = false

		vim.api.nvim_exec_autocmds("BufNewFile", { buffer = bufnr, modeline = false })
		return
	end

	if not is_armored_gpg(note_path) then
		read_regular_file(bufnr, file)
		return
	end

	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].modified = false
	vim.b[bufnr].decrypting = true
	vim.api.nvim_exec_autocmds("BufReadPre", { buffer = bufnr, modeline = false })

	crypto.decrypt_to_buffer(note_path, bufnr, function(result)
		if result.code ~= 0 then
			local err = (result.stderr and result.stderr ~= "") and result.stderr
				or "decryption failed with no error given"
			utils.drop_buffer_with_error(bufnr, err)

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

	-- Normalize to an absolute path so `file ~= note_path` and the buffer rename
	-- behave the same whether the buffer was opened relative or absolute.
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

	-- A note written with the other extension keeps it, so an existing note is
	-- never split in two.
	local note_path = utils.resolve_note_file(file)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local current_hash = vim.fn.sha256(table.concat(lines, "\n"))

	if current_hash == vim.b[bufnr].hash then
		message.info("No changes detected")
		vim.bo[bufnr].modified = false
		return
	end
	vim.api.nvim_exec_autocmds("BufWritePre", { buffer = bufnr, modeline = false })

	local result = crypto.encrypt_from_stdin(note_path, lines, bufnr)

	if result.code ~= 0 then
		-- Defer: an ERROR-level vim.notify raises inside an autocmd, which
		-- would abort the write command outright.
		local err = (result.stderr and result.stderr ~= "") and result.stderr or "Unknown encryption error"
		message.defer_error("%s", err)
		return
	end

	if file ~= note_path then
		-- If saving a plain text file for the first time, delete the unencrypted original and change the buffer to the encrypted path.
		if utils.file_exists(file) then
			vim.fn.delete(file)
		end
		vim.api.nvim_buf_set_name(bufnr, note_path)
	end

	prepare_buffer_for_edit(bufnr)

	vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr, modeline = false })
end

return M
