local M = {}

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

	if vim.api.nvim_buf_is_valid(bufnr) then
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		vim.b[bufnr].hash = vim.fn.sha256(table.concat(lines, "\n"))

		vim.b[bufnr].decrypting = false
	end
end

--- @param args vim.api.keyset.create_autocmd.callback_args
function M.on_read(args)
	local bufnr = args.buf
	local utils = require("memo.utils")
	local core = require("memo.core")
	local message = require("memo.message")

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

	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].modified = false
	vim.b[bufnr].decrypting = true
	vim.api.nvim_exec_autocmds("BufReadPre", { buffer = bufnr, modeline = false })

	-- Force filetype detection based on the name without .gpg
	local base = args.file:gsub("%.gpg$", "")
	vim.bo[bufnr].filetype = vim.filetype.match({ filename = base })

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

function M.setup_conform()
	local utils = require("memo.utils")

	local conform = utils.load_plugin("conform", "conform.nvim")
	if not conform then
		return
	end

	if not conform.formatters then
		return
	end

	local notes_dir = utils.get_notes_dir()

	local function is_memo_buffer(bufnr)
		local name = vim.api.nvim_buf_get_name(bufnr or 0)
		return name:sub(1, #notes_dir) == notes_dir
	end

	local function get_logical_name(bufnr)
		local name = vim.api.nvim_buf_get_name(bufnr)
		return name:gsub("%.gpg$", "")
	end

	local function make_prettier_formatter(cmd)
		return function(bufnr)
			if not is_memo_buffer(bufnr) then
				return nil
			end

			local logical = get_logical_name(bufnr)

			return {
				command = cmd,
				args = { "--stdin-filepath", logical },
				stdin = true,
			}
		end
	end

	conform.formatters.prettierd = make_prettier_formatter("prettierd")
	conform.formatters.prettier = make_prettier_formatter("prettier")
end

return M
