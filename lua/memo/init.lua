local M = {}

--Opens a capture buffer, prefilled with the target header and the template.
---@param opts? MemoCaptureOpts
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

---@param opts? MemoSaveAsNoteOpts
function M.save_as_note(opts)
	return require("memo.save_as_note").create(opts)
end

--Moves the selected lines into the current note's companion archive file.
---@param opts? MemoArchiveOpts
---@return boolean success
function M.archive(opts)
	return require("memo.archive").archive(opts)
end

--Opens the encrypted scratch buffer for the current directory, creating it on
--first use.
---@param opts? MemoScratchOpts
---@return boolean success
function M.scratch(opts)
	return require("memo.scratch").open_or_create(opts)
end

return M
