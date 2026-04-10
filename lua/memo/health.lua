local utils = require("memo.utils")
local M = {}

M.check = function()
	vim.health.start("memo.nvim report")

	-- Check Executables
	if vim.fn.executable("gpg") == 1 then
		vim.health.ok("gpg binary is installed")
	else
		vim.health.error("gpg binary is missing from PATH")
	end

	if vim.fn.executable("memo") == 1 then
		vim.health.ok("memo is installed")
	else
		vim.health.error("memo is missing from PATH")
	end

	-- Check Directories
	local notes_dir = utils.get_notes_dir()

	if vim.fn.isdirectory(notes_dir) == 1 then
		vim.health.ok("Notes directory exists: " .. notes_dir)
	else
		vim.health.warn("Notes directory not found: " .. notes_dir)
	end
end

return M
