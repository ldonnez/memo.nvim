local M = {}

-- The augroup owned by plugin/memo.lua, which creates and clears it at
-- startup. The per-buffer writers below join it so the plugin's global writer
-- can tell they are registered and defer to them.
local GROUP = require("memo.config").autocmd_group

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

	-- Absolute, so path comparisons hold whether `args.file` is relative or not.
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

	-- A new note: open it the regular way.
	if not utils.file_has_content(note_path) then
		-- Read it the regular way.
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

--- Gives a buffer its own write handler, so a new note can set
--- the encryption mode of its first write in a closure. The handler stays
--- with the buffer; once the note exists.
--- @param bufnr integer
--- @param mode "passphrase"|"key"
function M.register_write(bufnr, mode)
	-- Re-registering replaces the previous handler instead of stacking one.
	vim.api.nvim_clear_autocmds({ event = "BufWriteCmd", buffer = bufnr, group = GROUP })

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = bufnr,
		group = GROUP,
		desc = "memo: write a new encrypted note",
		callback = function(args)
			M.on_write(args, mode)
		end,
	})
end

--- @param args vim.api.keyset.create_autocmd.callback_args
--- @param mode? "passphrase"|"key" only for a new note, ignored once the file exists
function M.on_write(args, mode)
	local bufnr = args.buf
	local utils = require("memo.utils")
	local crypto = require("memo.crypto")
	local message = require("memo.message")

	-- Absolute, so `file ~= note_path` and the buffer rename hold either way.
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

	-- A note that carries a supported extension keeps it.
	local note_path = utils.resolve_note_file(file)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local current_hash = vim.fn.sha256(table.concat(lines, "\n"))

	if current_hash == vim.b[bufnr].hash then
		message.info("No changes detected")
		vim.bo[bufnr].modified = false
		return
	end
	vim.api.nvim_exec_autocmds("BufWritePre", { buffer = bufnr, modeline = false })

	local result = crypto.encrypt_from_stdin(note_path, lines, bufnr, { mode = mode })

	if result.code ~= 0 then
		-- Deferred: an ERROR-level vim.notify raises inside an autocmd.
		local err = (result.stderr and result.stderr ~= "") and result.stderr or "Unknown encryption error"
		message.defer_error("%s", err)
		return
	end

	if file ~= note_path then
		-- First save of a plain text file: delete it and rename to the note.
		if utils.file_exists(file) then
			vim.fn.delete(file)
		end
		vim.api.nvim_buf_set_name(bufnr, note_path)
	end

	prepare_buffer_for_edit(bufnr)

	vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr, modeline = false })
end

return M
