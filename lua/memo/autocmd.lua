local utils = require("memo.utils")
local core = require("memo.core")
local config = require("memo.config")

local M = {}

function M.setup()
	local notes_dir = config.notes_dir
	local abs_notes = vim.fn.fnamemodify(vim.fn.expand(notes_dir), ":p")
	local GROUP = vim.api.nvim_create_augroup("MemoGpg", { clear = true })

	local pattern = { abs_notes .. "*.{md,txt,org}", abs_notes .. "*.{md,txt,org}.gpg" }

	-- 2. Reading / Decrypting
	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = GROUP,
		pattern = pattern,
		callback = function(args)
			local bufnr = args.buf

			utils.apply_gpg_opts(bufnr)

			-- Force filetype detection based on the name without .gpg
			local base = args.file:gsub("%.gpg$", "")
			vim.bo[bufnr].filetype = vim.filetype.match({ filename = base })

			local gpg_path = utils.get_gpg_path(args.file)

			-- If the .gpg file doesn't exist, it's a new note, just open it
			if vim.fn.filereadable(gpg_path) == 0 or vim.fn.getfsize(gpg_path) <= 0 then
				vim.bo[bufnr].modified = false
				return
			end

			local result = core.decrypt_to_stdout(gpg_path)

			if not result or result.code ~= 0 then
				vim.api.nvim_buf_delete(bufnr, { force = true })
				return vim.notify("GPG decryption failed", vim.log.levels.ERROR)
			end

			if not result.stdout then
				return
			end

			local lines = utils.to_lines(result.stdout)
			local sha256 = vim.fn.sha256(table.concat(lines, "\n"))
			vim.b[bufnr].hash = sha256

			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

			vim.bo[bufnr].modified = false
		end,
	})

	-- 3. Writing / Encrypting
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = GROUP,
		pattern = pattern,
		callback = function(args)
			local gpg_path = utils.get_gpg_path(args.file)

			-- Encrypt buffer content directly via stdin to avoid temp files
			local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)

			local current_hash = vim.fn.sha256(table.concat(lines, "\n"))
			local original_hash = vim.b[args.buf].hash

			if current_hash == original_hash then
				vim.notify("No changes detected", vim.log.levels.INFO)
				vim.bo[args.buf].modified = false
				return
			end

			local result = core.encrypt_from_stdin(gpg_path, lines)

			if result and result.code == 0 then
				vim.bo[args.buf].modified = false

				vim.b[args.buf].hash = current_hash
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
