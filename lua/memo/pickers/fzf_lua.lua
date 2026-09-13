local utils = require("memo.utils")
local M = {}

---Delete the selected scratch files, also wiping any buffer that has them
---open. Entries are relative to the picker `cwd` and may carry icon/ANSI
---prefixes, so we resolve them with fzf-lua's entry parser. This function is
---serialized by fzf-lua into a separate process for `reload=true` actions, so
---it must not rely on upvalues.
---@param selected string[]
---@param opts any
local function delete_scratch_files(selected, opts)
	local fzf_path = utils.load_plugin("fzf-lua.path")
	for _, entry in ipairs(selected) do
		local file = fzf_path.entry_to_file(entry, opts).path
		if file then
			-- Wiping the buffer triggers the memo autocmd that deletes the
			-- on-disk file, so only delete manually for files without a buffer.
			local bufnr = vim.fn.bufnr(file)
			if bufnr ~= -1 then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			else
				vim.fn.delete(file)
			end
		end
	end
end

---@param fzf any
---@param dir string
---@param delete? boolean Enable a keybind to delete the selected files
local function pick(fzf, dir, delete)
	local actions = delete and {
		["ctrl-x"] = { fn = delete_scratch_files, reload = true },
	} or nil

	fzf.files({
		cwd = dir,
		previewer = false,
		actions = actions,
	})
end

function M.files_picker()
	local fzf = utils.load_plugin("fzf-lua")

	if not fzf then
		return
	end

	pick(fzf, utils.get_notes_dir())
end

function M.scratch_files_picker()
	local fzf = utils.load_plugin("fzf-lua")

	if not fzf then
		return
	end

	pick(fzf, utils.get_scratch_dir(), true)
end

return M
