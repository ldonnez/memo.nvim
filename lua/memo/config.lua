---@class MemoConfig
---@field notes_dir string
---@field scratch_dir string
---@field ignore_patterns string[]

---@class MemoConfigModule
---@field setup fun()
---@field notes_dir string
---@field scratch_dir string
---@field ignore_patterns string[]

local M = {}

local options

---@type MemoConfig
local defaults = {
	notes_dir = vim.fn.expand("~/notes") --[[@as string]],
	scratch_dir = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "memo-scratch"),
	ignore_patterns = {
		"**/.git/**",
		"**/.githooks/**",
		"**/.gitignore",
		"**/.gitattributes",
		"**/.gitmodules",
		"**/.ignore",
	},
}

function M.setup()
	options = vim.deepcopy(defaults)

	if vim.g.memo_notes_dir ~= nil then
		options.notes_dir = vim.g.memo_notes_dir
	end

	if vim.g.memo_scratch_dir ~= nil then
		options.scratch_dir = vim.g.memo_scratch_dir
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
