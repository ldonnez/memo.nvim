local M = {}

function M.setup()
	local status_ok, fzf = pcall(require, "fzf-lua")
	if not status_ok or not fzf.fzf_exec then
		vim.notify("fzf-lua is not installed!", vim.log.levels.ERROR)
		return
	end

	local config = require("memo.config")
	local notes_dir = vim.fn.expand(config.options.notes_dir)

	fzf.fzf_exec("rg --files", {
		prompt = "Notes> ",
		cwd = notes_dir,
		actions = require("fzf-lua").defaults.actions.files,
	})
end

return M
