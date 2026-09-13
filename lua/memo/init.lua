local M = {}

---@param opts CaptureConfig
function M.register_capture(opts)
	require("memo.capture").register(opts)
end

function M.sync_git()
	return require("memo.core").sync_git()
end

function M.save_as_note()
	return require("memo.core").save_as_note()
end

--Opens a new encrypted scratch buffer.
---@param direction? "horizontal"|"vertical"|"tab"
function M.scratch(direction)
	require("memo.scratch").create(direction)
end

return M
