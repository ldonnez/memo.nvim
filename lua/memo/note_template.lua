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
---@return string[] lines, integer[] cursor_pos
function Template:resolve_template()
	local template = self.config.template or ""
	local raw_text = tostring(os.date(tostring(template)))

	local lines = vim.split(raw_text, "\n", { plain = true, trimempty = false })
	local marker = "|"
	local cursor_pos = { #lines, 0 }

	for i, line in ipairs(lines) do
		local col = line:find(marker, 1, true)
		if col then
			lines[i] = line:sub(1, col - 1) .. line:sub(col + 1)
			cursor_pos = { i, col - 1 }
			break
		end
	end

	return lines, cursor_pos
end

return M
