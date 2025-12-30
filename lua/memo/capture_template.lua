local M = {}

---@class MemoCaptureTemplateConfig
---@field template string?
---@field target_header string?
---@field header_padding integer?

---@type MemoCaptureTemplateConfig
M.defaults = {
	template = "",
	header_padding = 1,
}

---@param opts MemoCaptureTemplateConfig
---@return string[], table @Returns (lines, cursor_pos)
function M.resolve(opts)
	local config = vim.tbl_deep_extend("force", M.defaults, opts or {})

	local template = config.template
	local raw_text = ""

	raw_text = tostring(os.date(tostring(template)))

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

---@param existing string[]
---@param target_header string?
---@return integer index of found target header
local function find_target_header_idx(existing, target_header)
	local target_idx = -1

	if not target_header and target_header ~= "" then
		return target_idx
	end

	for i, line in ipairs(existing) do
		if line == target_header then
			target_idx = i
			break
		end
	end

	return target_idx
end

---@param existing string[]
---@param new_lines string[]
---@param config MemoCaptureTemplateConfig
---@return string[]
function M.merge_with_content(existing, new_lines, config)
	if #new_lines == 0 then
		return existing
	end

	local header = config.target_header
	local padding = config.header_padding or 0
	local target_idx = find_target_header_idx(existing, header)

	-- Build the "block" we want to insert
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
