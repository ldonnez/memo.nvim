local utils = require("memo.utils")
local core = require("memo.core")
local config = require("memo.config")
local events = require("memo.events")

local M = {}

--- @param bufnr integer
local function prepare_buffer_for_edit(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	-- Ensure the user can edit now that loading is done
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].modified = false

	vim.defer_fn(function()
		if vim.api.nvim_buf_is_valid(bufnr) then
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			vim.b[bufnr].hash = vim.fn.sha256(table.concat(lines, "\n"))

			events.emit(events.types.BUFFER_READY)
		end
	end, 10)
end

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

			utils.harden_buffer(bufnr)

			-- Force filetype detection based on the name without .gpg
			local base = args.file:gsub("%.gpg$", "")
			vim.bo[bufnr].filetype = vim.filetype.match({ filename = base })

			local gpg_path = utils.get_gpg_path(args.file)

			-- If the .gpg file doesn't exist, it's a new note, just open it
			if vim.fn.filereadable(gpg_path) == 0 or vim.fn.getfsize(gpg_path) <= 0 then
				-- Read file - the regular way - into buffer
				vim.cmd("silent edit " .. vim.fn.fnameescape(args.file))
				return
			end

			core.decrypt_to_buffer(args.file, bufnr, function(result)
				vim.schedule(function()
					if result.code ~= 0 then
						vim.bo[bufnr].modifiable = true
						vim.api.nvim_buf_delete(bufnr, { force = true })
						vim.notify("Decryption failed", vim.log.levels.ERROR)
						return
					end

					prepare_buffer_for_edit(bufnr)
				end)
			end)
		end,
	})

	-- 3. Writing / Encrypting
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = GROUP,
		pattern = pattern,
		callback = function(args)
			local bufnr = args.buf
			local gpg_path = utils.get_gpg_path(args.file)
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

			local current_hash = vim.fn.sha256(table.concat(lines, "\n"))

			if current_hash == vim.b[bufnr].hash then
				vim.notify("No changes detected", vim.log.levels.INFO)
				vim.bo[bufnr].modified = false
				events.emit(events.types.BUFFER_READY)
				return
			end

			core.encrypt_from_stdin(gpg_path, lines, function(result)
				vim.schedule(function()
					if not vim.api.nvim_buf_is_valid(bufnr) then
						return
					end

					if result.code == 0 then
						prepare_buffer_for_edit(bufnr)

						if args.file ~= gpg_path and vim.fn.filereadable(args.file) == 1 then
							vim.fn.delete(args.file)
							vim.api.nvim_buf_set_name(bufnr, gpg_path)
						end
						return
					end

					local err = (result.stderr and result.stderr ~= "") and result.stderr or "GPG Error"
					vim.notify("Encryption failed: " .. err, vim.log.levels.ERROR)
				end)
			end)
		end,
	})
end

return M
