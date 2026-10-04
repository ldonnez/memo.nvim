---@class MemoConfig
---@field notes_dir string
---@field scratch_dir string
---@field capture_file string
---@field extension string
---@field supported_extensions string[]
---@field ignore_patterns string[]
---@field minimum_memo_version string

---@class MemoConfigModule
---@field setup fun()
---@field notes_dir string
---@field scratch_dir string
---@field capture_file string
---@field extension string
---@field supported_extensions string[]
---@field ignore_patterns string[]
---@field minimum_memo_version string

local M = {}

local options

---@type MemoConfig
local DEFAULTS = {
	notes_dir = vim.fn.expand("~/notes") --[[@as string]],
	capture_file = "inbox.md.asc",
	scratch_dir = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "memo-scratch"),
	-- Supported note extensions. New notes are written with `extension`, while
	-- every entry here is read and written as it is.
	-- The `extension` field joins this list in `setup`.
	supported_extensions = { "asc", "gpg" },
	extension = "asc",
	ignore_patterns = {
		"**/.git/**",
		"**/.githooks/**",
		"**/.gitignore",
		"**/.gitattributes",
		"**/.gitmodules",
		"**/.ignore",
	},
	minimum_memo_version = "0.11.0",
}

function M.setup()
	options = vim.deepcopy(DEFAULTS)

	if vim.g.memo_notes_dir ~= nil then
		options.notes_dir = vim.g.memo_notes_dir
	end

	if vim.g.memo_scratch_dir ~= nil then
		options.scratch_dir = vim.g.memo_scratch_dir
	end

	if vim.g.memo_default_capture_file ~= nil then
		options.capture_file = vim.g.memo_default_capture_file
	end

	if vim.g.memo_extension ~= nil then
		options.extension = vim.g.memo_extension
	end

	if not vim.tbl_contains(options.supported_extensions, options.extension) then
		table.insert(options.supported_extensions, options.extension)
	end

	if vim.g.memo_ignore_patterns ~= nil then
		vim.list_extend(options.ignore_patterns, vim.g.memo_ignore_patterns)
	end
end

return setmetatable(M, {
	__index = function(_, key)
		if options == nil then
			M.setup()
		end

		return options--[[@cast -?]][key]
	end,

	__newindex = function(_, key, value)
		if options == nil then
			M.setup()
		end

		options--[[@cast -?]][key] = value
	end,
}) --[[@as MemoConfigModule]]
