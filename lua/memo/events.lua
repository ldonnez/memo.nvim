local M = {}

--- @enum MemoEvent
M.types = {
	DECRYPT_DONE = "MemoDecryptDone",
	ENCRYPT_DONE = "MemoEncryptDone",
	CAPTURE_DONE = "MemoCaptureDone",
	BUFFER_READY = "MemoBufferReady",
}

--- Broadcasts a memo event safely on the main thread
--- @param event_type string One of M.types
function M.emit(event_type)
	vim.schedule(function()
		vim.api.nvim_exec_autocmds("User", {
			pattern = event_type,
			modeline = false,
		})
	end)
end

return M
