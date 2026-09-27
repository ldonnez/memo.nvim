local M = {}

---@class MemoNoteTemplateConfig
---@field template string?

local defaults = {
	template = "",
}

---@class MemoNoteTemplate
---@field config MemoNoteTemplateConfig
local Template = {}

Template.__index = Template

---Constructor: Creates a new Template instance
---@param opts MemoNoteTemplateConfig?
---@return MemoNoteTemplate
function M.new(opts)
	local self = setmetatable({}, Template)

	self.config = vim.tbl_deep_extend("force", defaults, opts or {})

	return self
end

---Resolves the template and cursor position
---@return string[] lines
---@return [integer, integer] cursor_pos row and column, 0-indexed
---@return boolean has_cursor_marker whether a `|` marker was found
function Template:resolve_template()
	local template = self.config.template or ""
	local raw_text = tostring(os.date(tostring(template)))

	local lines = vim.split(raw_text, "\n", { plain = true, trimempty = false })
	local marker = "|"
	local cursor_pos = { #lines, 0 }
	local has_cursor_marker = false

	for i, line in ipairs(lines) do
		local col = line:find(marker, 1, true)
		if col then
			lines[i] = line:sub(1, col - 1) .. line:sub(col + 1)
			cursor_pos = { i, col - 1 }
			has_cursor_marker = true
			break
		end
	end

	return lines, cursor_pos, has_cursor_marker
end

---Inserts `content` where the cursor marker was, keeping the rest of the
---template around it. The returned cursor sits right after the inserted
---content, so typing continues from there.
---Without a cursor marker there is nowhere to insert, so the template is
---returned unchanged.
---@param content string[]
---@return string[] lines, integer[] cursor_pos
function Template:insert_at_cursor(content)
	local lines, cursor_pos, has_cursor_marker = self:resolve_template()

	if #content == 0 or not has_cursor_marker then
		return lines, cursor_pos
	end

	local row, col = cursor_pos[1], cursor_pos[2]
	local line = lines[row] or ""
	local before = line:sub(1, col)
	local after = line:sub(col + 1)

	-- The first content line shares the row with the text before the marker,
	-- the rest get a row each.
	local merged = vim.list_slice(lines, 1, row - 1)
	local end_row, end_col

	if #content == 1 then
		-- A single line keeps the text after the marker on the same row, so the
		-- content does not end up split from it.
		merged[#merged + 1] = before .. content[1] .. after
		end_row = #merged
		end_col = #before + #content[1]
	else
		merged[#merged + 1] = before .. content[1]

		for i = 2, #content do
			merged[#merged + 1] = content[i]
		end

		end_row = #merged
		end_col = #content[#content]

		-- Text following the marker starts a new row once the content spans
		-- several of them.
		if after ~= "" then
			merged[#merged + 1] = after
		end
	end

	vim.list_extend(merged, vim.list_slice(lines, row + 1))

	return merged, { end_row, end_col }
end

return M
