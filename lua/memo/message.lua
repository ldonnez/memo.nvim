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

--- @param fmt string
--- @param ... any
function M.info(fmt, ...)
	vim.notify(fmt:format(...), levels.INFO, { title = "memo.nvim" })
end

return M
