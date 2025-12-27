local M = {}

function M.setup()
	local status_ok, fzf = pcall(require, "fzf-lua")
	if not status_ok or not fzf.fzf_exec then
		vim.notify("fzf-lua is not installed!", vim.log.levels.ERROR)
		return
	end

	local config = require("memo.config")
	local notes_dir = config.notes_dir
	require("fzf-lua").files({ cwd = notes_dir, previewer = false })
end

return M
