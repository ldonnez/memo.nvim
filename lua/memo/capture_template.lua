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
---@param new_lines string[]
---@param config MemoCaptureTemplateConfig
---@return string[]
function M.merge_with_content(existing, new_lines, config)
	if #new_lines == 0 then
		return existing
	end

	local has_content = false
	for _, line in ipairs(new_lines) do
		if line:gsub("%s+", "") ~= "" then
			has_content = true
			break
		end
	end
	if not has_content then
		return existing
	end

	local merged = {}
	local target = config.target_header
	local padding_count = config.header_padding or 0
	local target_idx = -1

	if target and target ~= "" then
		for i, line in ipairs(existing) do
			if line == target then
				target_idx = i
				break
			end
		end
	end

	if target_idx ~= -1 then
		for i = 1, target_idx do
			table.insert(merged, existing[i])
		end

		for _ = 1, padding_count do
			table.insert(merged, "")
		end

		for _, line in ipairs(new_lines) do
			table.insert(merged, line)
		end

		local resume_idx = target_idx + 1
		if existing[resume_idx] == "" then
			resume_idx = resume_idx + 1
		end

		for i = resume_idx, #existing do
			table.insert(merged, existing[i])
		end
	elseif target and target ~= "" then
		table.insert(merged, target)

		for _ = 1, padding_count do
			table.insert(merged, "")
		end

		for _, line in ipairs(new_lines) do
			table.insert(merged, line)
		end

		-- Push down all existing content
		if #existing > 0 then
			table.insert(merged, "") -- Add a separator between new and old blocks
			for _, line in ipairs(existing) do
				table.insert(merged, line)
			end
		end
	else
		for _, l in ipairs(new_lines) do
			table.insert(merged, l)
		end
		for _, l in ipairs(existing) do
			table.insert(merged, l)
		end
	end

	return merged
end

return M
