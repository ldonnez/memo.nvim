local M = {}

---@class MemoSelection
---@field start [integer, integer, integer, integer]
---@field finish [integer, integer, integer, integer]
---@field linewise boolean
---@field blockwise? boolean

---@param bufnr integer
---@param line1 integer
---@param line2 integer
local function resolve_range(bufnr, line1, line2)
	return vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false),
		{
			start = { 0, line1, 1, 0 },
			finish = { 0, line2, 1, 0 },
			linewise = true,
		}
end

---Resolves a visual selection or a command range, or nil when neither applies.
---@param bufnr integer
---@param opts? { range?: integer, line1?: integer, line2?: integer }
---@return string[]|nil
---@return MemoSelection|nil
function M.resolve(bufnr, opts)
	if opts and opts.range and opts.range ~= 0 then
		if not opts.line1 or not opts.line2 then
			return nil
		end

		return resolve_range(bufnr, opts.line1, opts.line2)
	end

	local mode = vim.fn.mode()

	if not mode:match("[vV\22]") then
		return nil
	end

	local start, finish = vim.fn.getpos("v"), vim.fn.getpos(".")

	if start[2] == 0 or finish[2] == 0 then
		return nil
	end

	return vim.fn.getregion(start, finish, { type = mode }),
		{
			start = start,
			finish = finish,
			linewise = mode == "V",
			blockwise = mode == "\22",
		}
end

---Removes a resolved selection from the buffer.
---@param bufnr integer
---@param selection MemoSelection
function M.delete_selection(bufnr, selection)
	local start, finish = selection.start, selection.finish

	if selection.blockwise and start[2] == finish[2] and start[3] == finish[3] and start[4] ~= finish[4] then
		local line = vim.api.nvim_buf_get_lines(bufnr, start[2] - 1, start[2], false)[1] or ""

		if line:sub(start[3], start[3]) == "\\t" then
			local tab_width = vim.fn.strdisplaywidth(line:sub(1, start[3]))
				- vim.fn.strdisplaywidth(line:sub(1, start[3] - 1))
			local first, last = math.min(start[4], finish[4]), math.max(start[4], finish[4])

			vim.api.nvim_buf_set_text(
				bufnr,
				start[2] - 1,
				start[3] - 1,
				start[2] - 1,
				start[3],
				{ string.rep(" ", first) .. string.rep(" ", math.max(0, tab_width - last)) }
			)
			return
		end
	end

	if selection.linewise then
		vim.api.nvim_buf_set_lines(bufnr, math.min(start[2], finish[2]) - 1, math.max(start[2], finish[2]), false, {})
		return
	end

	-- Recreate the original Visual selection and let Neovim handle deletion,
	-- including blockwise tabs, multibyte characters, and short lines.
	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd("normal! \27")
		vim.fn.setpos(".", start)
		vim.cmd(selection.blockwise and "normal! \22" or "normal! v")
		vim.fn.setpos(".", finish)
		vim.cmd('normal! "_d')
	end)
end

return M
