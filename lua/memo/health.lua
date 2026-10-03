local config = require("memo.config")
local M = {}

local function check_gpg()
	if vim.fn.executable("gpg") == 1 then
		vim.health.ok("gpg binary is installed")
	else
		vim.health.error("gpg binary is missing from PATH")
	end
end

local function check_memo_binary()
	if vim.fn.executable("memo") == 0 then
		vim.health.error("memo is missing from PATH")
		return
	end

	local result = vim.system({ "memo", "version" }, { text = true }):wait()
	if result.code ~= 0 or not result.stdout then
		vim.health.ok("memo is installed")
		return
	end

	local memo_version = vim.trim(result.stdout)
	local minimum = vim.version.parse(config.minimum_memo_version) --[[@as vim.Version]]

	--- @diagnostic disable-next-line: param-type-mismatch
	if vim.version.ge(vim.version.parse(memo_version), minimum) then
		vim.health.ok(string.format("memo %s >= %s", memo_version, config.minimum_memo_version))
	else
		vim.health.error(string.format("memo %s < %s", memo_version, config.minimum_memo_version))
	end
end

local function check_notes_directory()
	local notes_dir = config.notes_dir

	if vim.fn.isdirectory(notes_dir) == 1 then
		vim.health.ok("Notes directory exists: " .. notes_dir)
	else
		vim.health.warn("Notes directory not found: " .. notes_dir)
	end
end

M.check = function()
	vim.health.start("memo.nvim report")
	check_gpg()
	check_memo_binary()
	check_notes_directory()
end

return M
