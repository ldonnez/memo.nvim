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

---Options shared by scratch pickers.
---@return table
local function build_scratch_opts()
	return {
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
	}
end

---@param opts? MemoPickerOpts
function M.files_picker(opts)
	local fzf = load_fzf()
	if not fzf then
		return
	end

	local picker_opts = vim.tbl_extend("force", DEFAULTS, {
		dir = config.notes_dir,
	}, opts or {})

	fzf.files(build_common_opts(picker_opts))
end

---@param opts? MemoPickerOpts
function M.scratch_files_picker(opts)
	local fzf = load_fzf()
	if not fzf then
		return
	end

	local picker_opts = vim.tbl_extend("force", DEFAULTS, {
		dir = config.scratch_dir,
	}, opts or {})

	fzf.files(vim.tbl_extend("force", build_common_opts(picker_opts), build_scratch_opts()))
end

---@param opts? MemoPickerOpts
function M.cwd_scratch_files_picker(opts)
	local fzf = load_fzf()
	if not fzf then
		return
	end

	local prefix = scratch.cwd_key() .. "-"
	local picker_opts = vim.tbl_extend("force", DEFAULTS, {
		dir = config.scratch_dir,
	}, opts or {})

	fzf.files(vim.tbl_extend("force", build_common_opts(picker_opts), build_scratch_opts(), {
		fn_transform = function(file)
			local name = vim.fn.fnamemodify(file, ":t")
			if name:sub(1, #prefix) ~= prefix then
				return nil
			end

			return scratch.display_scratch(name)
		end,
	}))
end

return M
