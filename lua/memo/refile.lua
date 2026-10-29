local message = require("memo.message")
local note_io = require("memo.note_io")
local selection = require("memo.selection")
local utils = require("memo.utils")
local window = require("memo.window")

local M = {}

---@class MemoRefileOpts
---@field range? integer Command range indicator
---@field line1? integer First line of the command range
---@field line2? integer Last line of the command range
---@field target_file? string destination note path, absolute or relative to the notes directory
---@field padding? MemoRefilePadding blank lines above and below the refiled content
---@field encryption? GpgEncryptOpts how to encrypt a new destination, "key" when omitted; existing destinations keep their mode
---@field window? MemoWindowConfig Window configuration

---@class MemoRefilePadding
---@field top? integer blank lines before the refiled content
---@field bottom? integer blank lines after the refiled content

---@param config MemoRefileOpts
---@param filetype string
---@return integer buf
---@return integer win
local function create_refile_window(config, filetype)
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
	vim.api.nvim_buf_set_name(buf, "MemoRefile://Refile")
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

---Opens an editable window with the selection. On write, prompts for a note
---path, appends the edited content, then removes the original selection.
---@param opts? MemoRefileOpts
---@return boolean
function M.create(opts)
	local source_win = vim.api.nvim_get_current_win()
	local source_buf = vim.api.nvim_get_current_buf()
	local source_changedtick = vim.api.nvim_buf_get_changedtick(source_buf)
	local filetype = vim.bo[source_buf].filetype
	local lines, selected = selection.resolve(source_buf, opts)

	local function source_changed()
		return not vim.api.nvim_buf_is_valid(source_buf)
			or vim.api.nvim_buf_get_changedtick(source_buf) ~= source_changedtick
	end

	if not lines or not selected or #lines == 0 then
		message.error("MemoRefile: select text to refile")
		return false
	end

	local config = vim.tbl_deep_extend("force", { window = {}, padding = { top = 0, bottom = 0 } }, opts or {})
	local buf, refile_win = create_refile_window(config, filetype)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modified = false

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			vim.api.nvim_exec_autocmds("BufWritePre", { buffer = buf, modeline = false })

			if source_changed() then
				message.defer_error("MemoRefile: source buffer changed; recreate the refile selection")
				return
			end

			local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

			if table.concat(content, "\n"):gsub("%s+", "") == "" then
				message.warn("MemoRefile: empty content")
				return
			end

			local target = opts and opts.target_file
				or utils.prompt_note_path(require("memo.config").notes_dir .. "/", "MemoRefile")

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

			if not vim.bo[source_buf].modifiable then
				message.defer_error("MemoRefile: source buffer is not modifiable")
				return
			end

			local saved, err = note_io.insert_lines(path, content, buf, {
				padding = config.padding,
				mode = config.encryption and config.encryption.mode,
				after = function()
					if source_changed() then
						return false, "source changed while writing"
					end

					selection.delete_selection(source_buf, selected)

					return true
				end,
			})

			if not saved then
				if err then
					message.defer_error("MemoRefile: %s", err)
				end
				return
			end

			message.info("Refiled to %s", path)
			vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf, modeline = false })

			close_refile(source_win, source_buf, refile_win, buf)
		end,
	})

	return true
end

return M
