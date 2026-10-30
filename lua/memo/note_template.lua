local M = {}

---@class MemoNoteTemplateConfig
---@field template string?
---@field source_path string?
---@field source_line integer?

---@class MemoNoteTemplate
---@field config MemoNoteTemplateConfig
---@field resolve_template fun(self: MemoNoteTemplate): string[], [integer, integer], boolean
---@field insert_at_cursor fun(self: MemoNoteTemplate, content: string[], lines?: string[], cursor_pos?: [integer, integer], has_cursor_marker?: boolean): string[], integer[]
---@field initial_content fun(self: MemoNoteTemplate, selection?: string[]): string[], [integer, integer]

---@class MemoNoteTemplateBufferOpts
---@field template string?
---@field bufnr integer
---@field selection MemoSelection?
---@field source_line integer?

local DEFAULTS = { template = "" }
local Template = {}
Template.__index = Template

---@param opts MemoNoteTemplateConfig?
---@return MemoNoteTemplate
function M.new(opts)
	return setmetatable({ config = vim.tbl_extend("force", DEFAULTS, opts or {}) }, Template)
end

---Creates a template whose source context comes from a buffer.
---@param opts MemoNoteTemplateBufferOpts
---@return MemoNoteTemplate
function M.for_buffer(opts)
	local source_path = vim.api.nvim_buf_get_name(opts.bufnr)
	local source_line = opts.source_line

	if opts.selection then
		source_line = math.min(opts.selection.start[2], opts.selection.finish[2])
	end

	return M.new({
		template = opts.template,
		source_path = source_path ~= "" and vim.fn.fnamemodify(source_path, ":p") or nil,
		source_line = source_line,
	})
end

---@param template string
---@param source_path string?
---@param source_line integer?
---@return string[] lines
---@return [integer, integer] cursor_pos
---@return boolean has_cursor_marker
local function expand(template, source_path, source_line)
	local output = {}
	---@type integer?
	local cursor_offset
	local index = 1

	local function append(value)
		output[#output + 1] = value
	end

	while index <= #template do
		if template:sub(index, index + 2) == "\\${" then
			local finish = template:find("}", index + 3, true)
			if finish then
				append(template:sub(index + 1, finish))
				index = finish + 1
			else
				append(template:sub(index, index))
				index = index + 1
			end
		elseif template:sub(index, index + 1) == "\\\\" then
			append("\\")
			index = index + 2
		elseif template:sub(index, index + 1) == "${" then
			local finish = template:find("}", index + 2, true)
			if not finish then
				append(template:sub(index, index))
				index = index + 1
			else
				local token = template:sub(index + 2, finish - 1)
				local value
				if token == "cursor" and cursor_offset == nil then
					cursor_offset = #table.concat(output)
					value = ""
				elseif token == "cursor" then
					value = template:sub(index, finish)
				elseif token == "date" then
					value = os.date("%Y-%m-%d")
				elseif token == "datetime" then
					value = os.date("%Y-%m-%d %H:%M")
				elseif token == "timestamp" then
					value = os.date("<%Y-%m-%d %a>")
				elseif token == "timestamp:time" then
					value = os.date("<%Y-%m-%d %a %H:%M>")
				elseif token:sub(1, 5) == "date:" or token:sub(1, 5) == "time:" then
					value = os.date(token:sub(6))
				elseif token == "clipboard" then
					value = table.concat(vim.fn.getreg("*", 1, true), "\n")
					if value == "" then
						value = table.concat(vim.fn.getreg("+", 1, true), "\n")
					end
				elseif token == "yank" then
					value = table.concat(vim.fn.getreg('"', 1, true), "\n")
				elseif token == "filename" then
					value = source_path and vim.fn.fnamemodify(source_path, ":t") or ""
				elseif token == "filepath" then
					value = source_path or ""
				elseif token == "capture" then
					value = source_path
							and ("[" .. vim.fn.fnamemodify(source_path, ":t") .. "](" .. vim.uri_from_fname(source_path) .. "#L" .. (source_line or 1) .. ")")
						or ""
				end
				append(value == nil and template:sub(index, finish) or value)
				index = finish + 1
			end
		else
			append(template:sub(index, index))
			index = index + 1
		end
	end

	local text = table.concat(output)
	local lines = vim.split(text, "\n", { plain = true, trimempty = false })
	local cursor_pos = { #lines, 0 }
	if cursor_offset ~= nil then
		local before = vim.split(text:sub(1, cursor_offset), "\n", { plain = true, trimempty = false })
		cursor_pos = { #before, #before[#before] }
	end
	return lines, cursor_pos, cursor_offset ~= nil
end

---@return string[] lines
---@return [integer, integer] cursor_pos
---@return boolean has_cursor_marker
function Template:resolve_template()
	return expand(self.config.template, self.config.source_path, self.config.source_line)
end

---@param content string[]
---@param lines string[]? already-resolved template lines
---@param cursor_pos [integer, integer]?
---@param has_cursor_marker boolean?
---@return string[] lines, integer[] cursor_pos
function Template:insert_at_cursor(content, lines, cursor_pos, has_cursor_marker)
	if not lines or not cursor_pos or has_cursor_marker == nil then
		lines, cursor_pos, has_cursor_marker = self:resolve_template()
	end
	if #content == 0 or not has_cursor_marker then
		return lines, cursor_pos
	end

	local row, col = cursor_pos[1], cursor_pos[2]
	local line = lines[row] or ""
	local before, after = line:sub(1, col), line:sub(col + 1)
	local merged = vim.list_slice(lines, 1, row - 1)
	local end_row, end_col
	if #content == 1 then
		merged[#merged + 1] = before .. content[1] .. after
		end_row, end_col = #merged, #before + #content[1]
	else
		merged[#merged + 1] = before .. content[1]
		for i = 2, #content do
			merged[#merged + 1] = content[i]
		end
		end_row, end_col = #merged, #content[#content]
		if after ~= "" then
			merged[#merged + 1] = after
		end
	end
	vim.list_extend(merged, vim.list_slice(lines, row + 1))
	return merged, { end_row, end_col }
end

---@param selection? string[]
---@return string[] lines
---@return [integer, integer] cursor_pos
function Template:initial_content(selection)
	local lines, cursor_pos, has_cursor_marker = self:resolve_template()
	if not selection then
		return lines, cursor_pos
	end
	if has_cursor_marker then
		return self:insert_at_cursor(selection, lines, cursor_pos, has_cursor_marker)
	end
	return selection, { #selection, 0 }
end

return M
