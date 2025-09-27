local M = {}

M.check = function()
	vim.health.start("memo.nvim report")

	-- Check Executables
	if vim.fn.executable("gpg") == 1 then
		vim.health.ok("gpg binary is installed")
	else
		vim.health.error("gpg binary is missing from PATH")
	end

	-- Check Directories
	local config = require("memo.config")
	if vim.fn.isdirectory(config.options.notes_dir) == 1 then
		vim.health.ok("Notes directory exists: " .. config.options.notes_dir)
	else
		vim.health.warn("Notes directory not found: " .. config.options.notes_dir)
	end
end

return M
