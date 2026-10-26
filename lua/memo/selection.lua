local M = {}

---@class MemoSelection
---@field start [integer, integer, integer, integer]
---@field finish [integer, integer, integer, integer]
---@field linewise boolean
---@field blockwise? boolean

---@param bufnr integer
---@param line1 integer
---@param line2 integer
local function range_selection(bufnr, line1, line2)
	local start_line = line1 - 1
	---@cast start_line integer

	return vim.api.nvim_buf_get_lines(bufnr, start_line, line2, false),
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

		return range_selection(bufnr, opts.line1, opts.line2)
	end

	local mode = vim.fn.mode()

	if not mode:match("[vV\22]") then
		return nil
	end

	local start = vim.fn.getpos("v")
	local finish = vim.fn.getpos(".")

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

local function delete_blockwise(bufnr, start, finish)
	local regions = vim.fn.getregionpos(start, finish, { type = "\22" })

	-- Delete bottom-up so each row's byte columns remain unchanged.
	for i = #regions, 1, -1 do
		local first, last = regions[i][1], regions[i][2]
		local line = vim.api.nvim_buf_get_lines(bufnr, first[2] - 1, first[2], false)[1] or ""

		if first[3] <= #line then
			local start_char = line:sub(first[3], first[3])
			local end_char = vim.fn.strcharpart(line:sub(last[3]), 0, 1)
			local leading, trailing = "", ""

			if start_char == "\t" and first[4] > 0 then
				leading = string.rep(" ", first[4])
			end

			if end_char == "\t" then
				local tab_width = vim.fn.strdisplaywidth(line:sub(1, last[3]))
					- vim.fn.strdisplaywidth(line:sub(1, last[3] - 1))
				local end_offset = last[4] > 0 and last[4] or tab_width
				trailing = string.rep(" ", math.max(0, tab_width - end_offset))
			end

			vim.api.nvim_buf_set_text(
				bufnr,
				first[2] - 1,
				first[3] - 1,
				first[2] - 1,
				last[3] - 1 + #end_char,
				{ leading .. trailing }
			)
		end
	end
end

---Removes a resolved selection from the buffer.
---@param bufnr integer
---@param selection MemoSelection
function M.delete_selection(bufnr, selection)
	local start, finish = selection.start, selection.finish

	if selection.blockwise then
		delete_blockwise(bufnr, start, finish)
		return
	end

	if selection.linewise then
		local first, last = math.min(start[2], finish[2]), math.max(start[2], finish[2])
		vim.api.nvim_buf_set_lines(bufnr, first - 1, last, false, {})
		return
	end

	if start[2] > finish[2] or (start[2] == finish[2] and start[3] > finish[3]) then
		start, finish = finish, start
	end

	local line = vim.api.nvim_buf_get_lines(bufnr, finish[2] - 1, finish[2], false)[1] or ""
	local end_char = vim.fn.strcharpart(line:sub(finish[3]), 0, 1)
	vim.api.nvim_buf_set_text(bufnr, start[2] - 1, start[3] - 1, finish[2] - 1, finish[3] - 1 + #end_char, { "" })
end

return M
