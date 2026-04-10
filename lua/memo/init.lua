local M = {}

---@param opts CaptureConfig
function M.register_capture(opts)
	require("memo.capture").register(opts)
end

function M.sync_git()
	return require("memo.core").sync_git()
end

return M
