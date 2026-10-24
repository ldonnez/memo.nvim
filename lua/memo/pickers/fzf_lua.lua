local utils = require("memo.utils")
local config = require("memo.config")
local scratch = require("memo.scratch")
local GpgPreviewer = require("memo.pickers.fzf_gpg_previewer")

local M = {}

---@class MemoPickerOpts
---@field dir? string
---@field previewer? boolean show the decrypted preview pane

---@type MemoPickerOpts
local DEFAULTS = {
	previewer = false,
}

---Load fzf-lua, returning nil when the plugin is unavailable.
---@return table?
local function load_fzf()
	return utils.load_plugin("fzf-lua")
end

---Common options shared by all note pickers.
---@param opts MemoPickerOpts
---@return table
local function build_common_opts(opts)
	return {
		cwd = opts.dir,
		previewer = opts.previewer and GpgPreviewer or false,
		winopts = {
			preview = {
				delay = 300,
			},
		},
	}
end

---Delete selected scratch files, also wiping any buffer that has them
---open. Entries are relative to the picker cwd and may carry icon/ANSI
---prefixes, so resolve them with fzf-lua's entry parser. This function is
---serialized by fzf-lua for reload actions, so it must not rely on upvalues.
---@param selected string[]
---@param opts any
local function delete_scratch_files(selected, opts)
	local fzf_path = utils.load_plugin("fzf-lua.path")

	for _, entry in ipairs(selected) do
		local file = fzf_path.entry_to_file(entry, opts).path
		if file then
			local bufnr = vim.fn.bufnr(file)
			if bufnr ~= -1 then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end

			vim.fn.delete(file)
		end
	end
end

-- The `*_opts` functions are exported for tests: they build the options each
-- picker hands to fzf-lua so the tests can validate them without opening the
-- fzf UI (which needs a terminal). The entrypoint functions below are the real
-- ones and share these builders.

---@param opts? MemoPickerOpts
---@return table
function M.files_opts(opts)
	return build_common_opts(vim.tbl_extend("force", DEFAULTS, {
		dir = config.notes_dir,
	}, opts or {}))
end

---@param opts? MemoPickerOpts
---@return table
function M.scratch_files_opts(opts)
	local common = build_common_opts(vim.tbl_extend("force", DEFAULTS, {
		dir = config.scratch_dir,
	}, opts or {}))

	return vim.tbl_extend("force", common, {
		actions = {
			["ctrl-x"] = {
				fn = delete_scratch_files,
				reload = true,
			},
		},
		fn_transform = function(file)
			return scratch.display_scratch(vim.fn.fnamemodify(file, ":t"))
		end,
		_fmt = {
			from = scratch.filename_from_display,
		},
		-- Function transforms cannot be serialized to the worker process.
		multiprocess = false,
	})
end

---@param opts? MemoPickerOpts
function M.files(opts)
	local fzf = load_fzf()
	if not fzf then
		return
	end

	fzf.files(M.files_opts(opts))
end

---@param opts? MemoPickerOpts
function M.scratch_files(opts)
	local fzf = load_fzf()
	if not fzf then
		return
	end

	fzf.files(M.scratch_files_opts(opts))
end

return M
