local levels = vim.log.levels

local M = {}

--- @param fmt string
--- @param ... any
function M.warn(fmt, ...)
	vim.notify(fmt:format(...), levels.WARN, { title = "memo.nvim" })
end

--- @param fmt string
--- @param ... any
function M.error(fmt, ...)
	vim.notify(fmt:format(...), levels.ERROR, { title = "memo.nvim" })
end

---Deferred `error`: an ERROR-level vim.notify raises when invoked directly
---inside an autocmd (BufReadCmd/BufWriteCmd), so defer it via `vim.schedule`.
---@param fmt string
---@param ... any
function M.defer_error(fmt, ...)
	local msg = fmt:format(...)
	vim.schedule(function()
		M.error("%s", msg)
	end)
end

--- @param fmt string
--- @param ... any
function M.info(fmt, ...)
	vim.notify(fmt:format(...), levels.INFO, { title = "memo.nvim" })
end

return M
