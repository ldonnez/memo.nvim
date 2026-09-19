---@class MemoConfigOptions
---@field notes_dir? string
---@field scratch_dir? string
---@field ignore_patterns? string[]

local M = {}

local default_ignore_patterns = {
	"**/.git/**",
	"**/.githooks/**",
	"**/.gitignore",
	"**/.gitattributes",
	"**/.gitmodules",
	"**/.ignore",
}

---@return string
function M.notes_dir()
	return vim.g.memo_notes_dir or vim.fn.expand("~/notes")
end

---@return string
function M.scratch_dir()
	return vim.g.memo_scratch_dir or vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "memo-scratch")
end

---@return string[]
function M.ignore_patterns()
	local patterns = vim.deepcopy(default_ignore_patterns)

	if vim.g.memo_ignore_patterns then
		vim.list_extend(patterns, vim.g.memo_ignore_patterns)
	end

	return patterns
end

return M
