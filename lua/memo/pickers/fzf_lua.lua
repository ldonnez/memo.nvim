local utils = require("memo.utils")
local config = require("memo.config")
local scratch = require("memo.scratch")
local previewer = require("memo.pickers.fzf_previewer")
local M = {}

---@class MemoPickerOpts
---@field dir? string
---@field delete? boolean
---@field filter? fun(name: string): boolean
---@field display_scratch? boolean
---@field previewer? boolean show the decrypted preview pane

---@type MemoPickerOpts
local DEFAULTS = {
	previewer = false,
}

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
---@param opts MemoPickerOpts
local function pick(fzf, opts)
	local actions = opts.delete and {
		["ctrl-x"] = { fn = delete_scratch_files, reload = true },
	} or nil

	local fn_transform
	if opts.filter or opts.display_scratch then
		fn_transform = function(file)
			local name = vim.fn.fnamemodify(file, ":t")
			if opts.filter and not opts.filter(name) then
				return nil
			end
			return opts.display_scratch and scratch.display_scratch(name) or name
		end
	end

	fzf.files({
		winopts = {
			preview = {
				delay = 300,
			},
		},
		cwd = opts.dir,
		previewer = opts.previewer and previewer.build() or false,
		actions = actions,
		fn_transform = fn_transform,
		-- A function transform cannot be serialized to the worker process, so
		-- keep this picker in the main process (see fzf-lua shell.lua).
		multiprocess = not fn_transform,
		-- The default actions recover the on-disk filename from the display
		-- line before resolving the path.
		_fmt = opts.display_scratch and { from = scratch.filename_from_display } or nil,
	})
end

---@param opts? MemoPickerOpts
function M.files_picker(opts)
	local fzf = utils.load_plugin("fzf-lua")

	if not fzf then
		return
	end

	pick(fzf, vim.tbl_extend("force", DEFAULTS, { dir = config.notes_dir }, opts or {}))
end

---@param opts? MemoPickerOpts
function M.scratch_files_picker(opts)
	local fzf = utils.load_plugin("fzf-lua")

	if not fzf then
		return
	end

	pick(
		fzf,
		vim.tbl_extend(
			"force",
			DEFAULTS,
			{ dir = config.scratch_dir, delete = true, display_scratch = true },
			opts or {}
		)
	)
end

---@param opts? MemoPickerOpts
function M.cwd_scratch_files_picker(opts)
	local fzf = utils.load_plugin("fzf-lua")

	if not fzf then
		return
	end

	local prefix = scratch.cwd_key() .. "-"
	local cwd_filter = function(name)
		return name:sub(1, #prefix) == prefix
	end

	pick(
		fzf,
		vim.tbl_extend(
			"force",
			DEFAULTS,
			{ dir = config.scratch_dir, delete = true, display_scratch = true, filter = cwd_filter },
			opts or {}
		)
	)
end

return M
