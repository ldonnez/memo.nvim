local message = require("memo.message")
local note_io = require("memo.note_io")
local selection = require("memo.selection")
local utils = require("memo.utils")
local window = require("memo.window")
local Template = require("memo.note_template")

local M = {}

---@class RefileConfig: MemoRefileOpts
---@field window MemoWindowConfig
---@field padding MemoRefilePadding
---@field prepend boolean
---@field remove_from_source boolean
---@type table
local DEFAULTS = {
	window = {},
	padding = { top = 0, bottom = 0 },
	prepend = false,
	remove_from_source = false,
}

---@class MemoRefileOpts
---@field range? integer Command range indicator
---@field line1? integer First line of the command range
---@field line2? integer Last line of the command range
---@field prompt_path? boolean prompt for a destination instead of using the default target
---@field prepend? boolean insert content before existing destination content
---@field target_header? string insert content below this exact header, creating it when missing
---@field remove_from_source? boolean remove the selection after writing; defaults to false
---@field template? string window template, supports `os.date` formats and a `|` cursor marker; selected text is inserted at the marker
---@field padding? MemoRefilePadding blank lines above and below the refiled content
---@field encryption? GpgEncryptOpts how to encrypt a new destination, "key" when omitted; existing destinations keep their mode
---@field window? MemoWindowConfig Window configuration

---@class MemoRefilePadding
---@field top? integer blank lines before the refiled content
---@field bottom? integer blank lines after the refiled content

---@param path string
---@return boolean valid
---@return string? err
local function validate_destination(path)
	local stat = vim.uv.fs_stat(path)

	if stat and stat.type ~= "file" then
		return false, ("destination is not a regular file: %s"):format(path)
	end

	return true
end

---@param default_target string
---@param prompt_path boolean?
---@return string? target
local function resolve_target(default_target, prompt_path)
	if not prompt_path then
		return default_target
	end

	local notes_dir = require("memo.config").notes_dir
	local default_path = default_target == "" and notes_dir
		or (default_target:sub(1, 1) == "/" and default_target or vim.fs.joinpath(notes_dir, default_target))

	return utils.prompt_note_path(default_path, "MemoRefile")
end

---Inserts `lines` into the note at `path`, then runs `after` before dropping the
---destination's original. The original is restored if writing or `after` fails.
---@param lines string[]
---@param count integer
---@param from_start boolean
---@return integer
local function missing_padding(lines, count, from_start)
	local existing = 0
	local index = from_start and 1 or #lines
	local step = from_start and 1 or -1

	while lines[index] == "" do
		existing = existing + 1
		index = index + step
	end

	return math.max(0, count - existing)
end

---@param target string[]
---@param count integer
local function append_blank_lines(target, count)
	for _ = 1, count do
		table.insert(target, "")
	end
end

---@param path string
---@param lines string[]
---@param config RefileConfig
---@param bufnr integer
---@param after fun(): boolean, string?
---@return boolean success
---@return string? err
local function insert_into_note(path, lines, config, bufnr, after)
	local padding = config.padding
	local encryption = config.encryption
	local prepend = config.prepend
	local target_header = config.target_header or ""
	local has_target_header = target_header ~= ""
	local valid, validation_err = validate_destination(path)

	if not valid then
		return false, validation_err
	end

	local existing, err = note_io.read_lines(path, bufnr)

	if not existing then
		return false, err
	end

	local mode = not utils.file_has_content(path) and encryption and encryption.mode or nil

	local merged = {}
	local header_idx

	if has_target_header then
		for i, line in ipairs(existing) do
			if line == target_header then
				header_idx = i
				break
			end
		end
	end

	local block = {}

	if has_target_header and not header_idx then
		table.insert(block, target_header)
	end

	if has_target_header then
		append_blank_lines(block, missing_padding(lines, padding.top or 0, true))
	end

	vim.list_extend(block, lines)

	append_blank_lines(block, missing_padding(lines, padding.bottom or 0, false))

	if header_idx then
		vim.list_extend(merged, vim.list_slice(existing, 1, header_idx))
		vim.list_extend(merged, block)
		local remaining = vim.list_slice(existing, header_idx + 1)
		if
			#lines > 0
			and #remaining > 0
			and remaining[1] ~= ""
			and lines[#lines] ~= ""
			and (padding.bottom or 0) == 0
		then
			table.insert(merged, "")
		end
		vim.list_extend(merged, remaining)
	elseif has_target_header then
		if #existing > 0 and #lines > 0 and lines[#lines] ~= "" and (padding.bottom or 0) == 0 then
			table.insert(block, "")
		end
		vim.list_extend(merged, block)
		vim.list_extend(merged, existing)
	elseif prepend then
		append_blank_lines(merged, missing_padding(lines, padding.top or 0, true))
		vim.list_extend(merged, lines)
		local bottom_padding = math.max(
			missing_padding(lines, padding.bottom or 0, false),
			#existing > 0 and #lines > 0 and 1 - (#lines[#lines] == "" and 1 or 0) - (existing[1] == "" and 1 or 0) or 0
		)
		for _ = 1, bottom_padding do
			table.insert(merged, "")
		end
		vim.list_extend(merged, existing)
	else
		local top_padding = math.max(
			missing_padding(lines, padding.top or 0, true),
			#existing > 0 and #lines > 0 and 1 - (existing[#existing] == "" and 1 or 0) - (#lines[1] == "" and 1 or 0)
				or 0
		)

		vim.list_extend(merged, existing)

		for _ = 1, top_padding do
			table.insert(merged, "")
		end

		vim.list_extend(merged, lines)

		append_blank_lines(merged, missing_padding(lines, padding.bottom or 0, false))
	end

	return note_io.write_lines(path, merged, bufnr, { mode = mode }, after)
end

---@param config RefileConfig
---@param filetype string
---@param name string
---@return integer buf
---@return integer win
local function create_refile_window(config, filetype, name)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_exec_autocmds("BufReadPre", { buffer = buf, modeline = false })

	local win = window.open(config.window)
	vim.api.nvim_win_set_buf(win, buf)

	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].undofile = false
	vim.bo[buf].fileencoding = "utf-8"
	vim.bo[buf].filetype = filetype
	vim.api.nvim_buf_set_name(buf, name)
	vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buf, modeline = false })

	return buf, win
end

---Restores focus to the source window and drops the refile buffer.
---@param source_win integer
---@param source_buf integer
---@param refile_win integer
---@param buf integer
local function close_refile(source_win, source_buf, refile_win, buf)
	if vim.api.nvim_win_is_valid(source_win) then
		if refile_win == source_win then
			vim.api.nvim_win_set_buf(source_win, source_buf)
		elseif vim.api.nvim_win_is_valid(refile_win) then
			vim.api.nvim_win_close(refile_win, true)
		end

		vim.api.nvim_set_current_win(source_win)
	end

	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

---Opens an editable window for new content or a selection. On write, saves
---the edited content to the default or prompted destination.
---@param opts? MemoRefileOpts
---@return boolean
function M.create(opts)
	local source_win = vim.api.nvim_get_current_win()
	local source_buf = vim.api.nvim_get_current_buf()
	local source_changedtick = vim.api.nvim_buf_get_changedtick(source_buf)
	local lines, selected = selection.resolve(source_buf, opts)
	local has_selection = lines ~= nil and selected ~= nil and #lines > 0
	local config = vim.tbl_deep_extend("force", DEFAULTS, opts or {}) --[[@as RefileConfig]]

	local function source_changed()
		return not vim.api.nvim_buf_is_valid(source_buf)
			or vim.api.nvim_buf_get_changedtick(source_buf) ~= source_changedtick
	end

	local default_target = require("memo.config").refile_target or ""
	if default_target == "" and not config.prompt_path then
		message.error("MemoRefile: a destination is required, or set g:memo_default_refile_target")
		return false
	end

	local filetype = (has_selection and vim.bo[source_buf].filetype or utils.get_filetype(default_target)) or ""
	local name = ("MemoRefile://%s"):format(
		not config.prompt_path and default_target ~= "" and default_target or "Refile"
	)
	local buf, refile_win = create_refile_window(config, filetype, name)
	local template = Template.new({ template = config.template })
	local initial_lines, cursor_pos = template:initial_content(has_selection and lines or nil)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
	vim.api.nvim_win_set_cursor(refile_win, cursor_pos)
	vim.bo[buf].modified = false

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			vim.api.nvim_exec_autocmds("BufWritePre", { buffer = buf, modeline = false })

			if selected and config.remove_from_source and source_changed() then
				message.defer_error("MemoRefile: source buffer changed; recreate the refile selection")
				return
			end

			local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

			if table.concat(content, "\n"):gsub("%s+", "") == "" then
				message.warn("MemoRefile: empty content")
				return
			end

			if not has_selection and vim.deep_equal(content, initial_lines) then
				message.info("MemoRefile: no changes")
				close_refile(source_win, source_buf, refile_win, buf)
				return
			end

			local target = resolve_target(default_target, config.prompt_path)

			if not target then
				return
			end

			local path = utils.resolve_note_path(target)

			if not path then
				message.defer_error(
					"MemoRefile: note path must be inside the notes directory (%s)",
					require("memo.config").notes_dir
				)
				return
			end

			local source_path = vim.api.nvim_buf_get_name(source_buf)
			if source_path ~= "" and vim.fn.fnamemodify(source_path, ":p") == path then
				message.defer_error("MemoRefile: destination must differ from the source buffer")
				return
			end

			if not utils.ensure_directories(vim.fs.dirname(path)) then
				return
			end

			if selected and config.remove_from_source and not vim.bo[source_buf].modifiable then
				message.defer_error("MemoRefile: source buffer is not modifiable")
				return
			end

			local saved, err = insert_into_note(path, content, config, buf, function()
				if selected and config.remove_from_source then
					if source_changed() then
						return false, "source changed while writing"
					end

					selection.delete_selection(source_buf, selected)
				end

				return true, nil
			end)

			if not saved then
				if err then
					message.defer_error("MemoRefile: %s", err)
				end
				return
			end

			local action = has_selection and (config.remove_from_source and "Moved to" or "Copied to") or "Saved to"

			message.info("%s %s", action, path)
			vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf, modeline = false })

			close_refile(source_win, source_buf, refile_win, buf)
		end,
	})

	return true
end
return M
