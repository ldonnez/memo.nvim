local M = {}

---@alias MemoTodoState "todo" | "all" | "done"
---@alias TodoLines {lnum: integer, raw: string}[]

local function get_fzf_lua()
	local has_fzf, fzf = pcall(require, "fzf-lua")

	if not has_fzf then
		vim.notify("memo.nvim: fzf-lua is not found", vim.log.levels.ERROR)
		return
	end

	return fzf
end

--- @param bufnr integer
--- @param state MemoTodoState
--- @return TodoLines
function M.collect_todos(bufnr, state)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local items = {}

	local allowed = {}
	if state == "all" then
		allowed = { [" "] = true, ["x"] = true, ["X"] = true }
	elseif state == "todo" then
		allowed = { [" "] = true }
	elseif state == "done" then
		allowed = { ["x"] = true, ["X"] = true }
	end

	for lnum, line in ipairs(lines) do
		local box = line:match("^%s*[-*+]%s+%[(.)%]")
		if box and allowed[box] then
			table.insert(items, { lnum = lnum, raw = line })
		end
	end

	return items
end

--- @param lines TodoLines
--- @return string[]
local function build_items(lines)
	local items = {}
	for _, line in pairs(lines) do
		table.insert(items, string.format("%d: %s", line.lnum, line.raw))
	end
	return items
end

--- @param state MemoTodoState
function M.current_buffer_todo_picker(state)
	local fzf = get_fzf_lua()

	local bufnr = vim.api.nvim_get_current_buf()
	local lines = M.collect_todos(bufnr, state)

	--- @diagnostic disable-next-line: need-check-nil
	fzf.fzf_exec(build_items(lines), {
		prompt = state:upper() .. "> ",
		actions = {
			["default"] = function(selected)
				if not selected or #selected == 0 then
					return
				end

				local entry = selected[1]
				local match = entry:match("^(%d+):")

				if not match then
					return
				end

				-- Ensure integer
				local lnum = math.floor(match)

				if lnum then
					vim.api.nvim_win_set_cursor(0, { lnum, 0 })
					vim.cmd("normal! zvzz")
				end
			end,
		},
	})
end

function M.files_picker()
	local fzf = get_fzf_lua()

	local config = require("memo.config")
	local notes_dir = config.notes_dir

	--- @diagnostic disable-next-line: need-check-nil
	fzf.files({ cwd = notes_dir, previewer = false })
end

return M
