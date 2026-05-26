local utils = require("memo.utils")
local M = {}

function M.files_picker()
	local fzf = utils.load_plugin("fzf-lua")

	if not fzf then
		return
	end

	local notes_dir = utils.get_notes_dir()

	--- @diagnostic disable-next-line: need-check-nil
	fzf.files({ cwd = notes_dir, previewer = false })
end

return M
