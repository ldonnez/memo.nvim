local M = {}

---@class MemoCaptureTemplateConfig
---@field template string?
---@field target_header string?
---@field header_padding integer?

local defaults = {
	template = "",
	header_padding = 0,
}

---@class MemoCaptureTemplate
---@field config MemoCaptureTemplateConfig
local Template = {}

Template.__index = Template

---Constructor: Creates a new Template instance
---@param opts MemoCaptureTemplateConfig?
---@return MemoCaptureTemplate
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

---Internal helper to find header index
---@private
---@param existing string[]
---@return integer
function Template:_find_target_header_idx(existing)
	local target_header = self.config.target_header

	if not target_header or target_header == "" then
		return -1
	end

	for i, line in ipairs(existing) do
		if line == target_header then
			return i
		end
	end

	return -1
end

---Merges new lines into existing content based on internal config
---@param existing string[]
---@param new_lines string[]
---@return string[]
function Template:merge_with_content(existing, new_lines)
	if #new_lines == 0 then
		return existing
	end

	local header = self.config.target_header
	local padding = self.config.header_padding or 0
	local target_idx = self:_find_target_header_idx(existing)

	-- Build the "block" to insert
	local block = {}
	if target_idx == -1 and header and header ~= "" then
		table.insert(block, header)
	end
	for _ = 1, padding do
		table.insert(block, "")
	end
	vim.list_extend(block, new_lines)

	-- Construct the result
	local merged = {}
	if target_idx ~= -1 then
		-- Insert after header: [Head] + [Block] + [Tail]
		vim.list_extend(merged, vim.list_slice(existing, 1, target_idx))
		vim.list_extend(merged, block)

		-- Skip exactly one empty line if it follows the header to prevent gaps
		local resume_at = (existing[target_idx + 1] == "") and (target_idx + 2) or (target_idx + 1)
		vim.list_extend(merged, vim.list_slice(existing, resume_at))
	else
		-- Prepend to top: [Block] + [Existing]
		vim.list_extend(merged, block)
		vim.list_extend(merged, existing)
	end

	return merged
end

return M
