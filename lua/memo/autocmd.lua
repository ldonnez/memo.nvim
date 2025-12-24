local utils = require("memo.utils")
local core = require("memo.core")
local config = require("memo.config")

local M = {}

---@param file string
---@return string
local function as_gpg_file(file)
	if not file:match("%.gpg$") then
		return file .. ".gpg"
	end
	return file
end

function M.setup()
	local notes_dir = config.options.notes_dir
	local GROUP = vim.api.nvim_create_augroup("customGpg", { clear = true })
	local META = "gpg_original_filename"
	local abs_notes = vim.fn.fnamemodify(vim.fn.expand(notes_dir), ":p")

	-- 1. Disable unsafe swaps for *.gpg
	vim.api.nvim_create_autocmd("BufReadPre", {
		group = GROUP,
		pattern = abs_notes .. "*.{md,txt,org}.gpg",
		callback = function()
			vim.opt_local.shadafile = "NONE"
			vim.opt_local.swapfile = false
			vim.opt_local.undofile = false
		end,
	})

	-- 2. Decrypt on BufReadCmd
	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = GROUP,
		pattern = {
			abs_notes .. "*.{md,txt,org}",
			abs_notes .. "*.{md,txt,org}.gpg",
		},
		callback = function(args)
			local file = args.file
			local base = utils.base_name(file)
			local gpg_file = as_gpg_file(file)

			if vim.fn.filereadable(gpg_file) == 0 then
				return
			end

			local bufnr = args.buf

			-- Conflict?
			local conflict = utils.get_conflicting_buffer(base)
			if conflict and conflict ~= bufnr then
				return utils.handle_conflict(conflict, bufnr)
			end

			-- Decrypt (cached)
			local result = core.decrypt_file(gpg_file)

			-- Retry with passphrase
			if result == nil or (result and result.code ~= 0) then
				vim.cmd("bwipeout! " .. bufnr)
				vim.notify("GPG decryption failed", vim.log.levels.ERROR)
				return
			end

			if result.stdout then
				local lines = utils.to_lines(result.stdout)
				core.load_decrypted(bufnr, gpg_file, lines, META)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = GROUP,
		pattern = abs_notes .. "*.{md,txt,org}",
		callback = function(args)
			local file = args.file
			local bufnr = args.buf

			if not file:match("%.gpg$") then
				local new_name = file .. ".gpg"

				local result = core.encrypt_file(file, new_name)

				if not result or (result and result.code ~= 0) then
					vim.api.nvim_buf_delete(bufnr, { force = true })
					return vim.notify("GPG decryption failed", vim.log.levels.ERROR)
				end

				vim.fn.delete(file)
				vim.api.nvim_buf_set_name(bufnr, new_name)
				vim.api.nvim_command("edit!")
				vim.notify("Encrypted -> " .. utils.base_name(new_name))
			end
		end,
	})
end

return M
