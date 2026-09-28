local M = {}

---@param opts CaptureConfig
function M.register_capture(opts)
	require("memo.capture").register(opts)
end

--Creates a new encrypted note and opens it.
---@param opts? MemoNewNoteOpts
function M.new_note(opts)
	return require("memo.new_note").create(opts)
end

function M.sync_git()
	return require("memo.sync").sync_git()
end

function M.save_as_note()
	return require("memo.save_as_note").create()
end

--Opens a new encrypted scratch buffer.
---@param direction? "horizontal"|"vertical"|"tab"
function M.scratch(direction)
	require("memo.scratch").create(direction)
end

return M
