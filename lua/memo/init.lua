local M = {}

--Opens a capture buffer, prefilled with the target header and the template.
---@param opts CaptureConfig
function M.capture(opts)
	require("memo.capture").create(opts)
end

--Creates a new encrypted note and opens it.
---@param opts? MemoNewNoteOpts
function M.new_note(opts)
	return require("memo.new_note").create(opts)
end

--Opens an existing encrypted note, which is decrypted on open.
---@param opts? MemoOpenOpts
function M.open(opts)
	return require("memo.open_note").open(opts)
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
