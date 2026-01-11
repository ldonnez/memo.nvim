local M = {}

---@param opts MemoConfig?
function M.setup(opts)
	require("memo.config").setup(opts)
	require("memo.autocmd").setup()
	require("memo.user_commands").setup()
end

---@param opts CaptureConfig?
function M.register_capture(opts)
	require("memo.capture").register(opts)
end

function M.sync_git()
	return require("memo.core").sync_git()
end

return M
