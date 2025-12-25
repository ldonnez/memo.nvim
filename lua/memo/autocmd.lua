local utils = require("memo.utils")
local core = require("memo.core")
local config = require("memo.config")

local M = {}
local META = "gpg_original_filename"

function M.setup()
	local notes_dir = config.options.notes_dir
	local abs_notes = vim.fn.fnamemodify(vim.fn.expand(notes_dir), ":p")
	local GROUP = vim.api.nvim_create_augroup("MemoGpg", { clear = true })

	-- Standard patterns
	local pattern = { abs_notes .. "*.{md,txt,org}", abs_notes .. "*.{md,txt,org}.gpg" }

	-- 2. Reading / Decrypting
	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = GROUP,
		pattern = pattern,
		callback = function(args)
			vim.opt_local.swapfile = false
			vim.opt_local.undofile = false
			vim.opt_local.shadafile = "NONE"

			-- Force filetype detection based on the name without .gpg
			local base = args.file:gsub("%.gpg$", "")
			vim.bo[args.buf].filetype = vim.filetype.match({ filename = base })

			local gpg_path = args.file:match("%.gpg$") and args.file or (args.file .. ".gpg")

			-- If the .gpg file doesn't exist, it's a new note, just open it
			if vim.fn.filereadable(gpg_path) == 0 then
				return
			end

			local result = core.decrypt_to_stdout(gpg_path)

			if not result or result.code ~= 0 then
				vim.api.nvim_buf_delete(args.buf, { force = true })
				return vim.notify("GPG decryption failed", vim.log.levels.ERROR)
			end

			if not result.stdout then
				return
			end

			local lines = utils.to_lines(result.stdout)
			vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, lines)

			-- Set state
			vim.b[args.buf][META] = gpg_path
			vim.bo[args.buf].buftype = "acwrite"
			vim.bo[args.buf].modified = false
		end,
	})

	-- 3. Writing / Encrypting
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = GROUP,
		pattern = pattern,
		callback = function(args)
			local gpg_path = vim.b[args.buf][META] or (args.file:match("%.gpg$") and args.file or (args.file .. ".gpg"))

			-- Encrypt buffer content directly via stdin to avoid temp files
			local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
			local result = core.encrypt_from_stdin(lines, gpg_path)

			if result and result.code == 0 then
				vim.bo[args.buf].modified = false
				vim.b[args.buf][META] = gpg_path

				if args.file ~= gpg_path and vim.fn.filereadable(args.file) == 1 then
					vim.fn.delete(args.file)
					-- Rename buffer to .gpg so future saves are "clean"
					vim.api.nvim_buf_set_name(args.buf, gpg_path)
				end
			else
				vim.notify("Encryption failed!", vim.log.levels.ERROR)
			end
		end,
	})
end

return M
