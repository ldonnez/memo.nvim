local crypto = require("memo.crypto")
local message = require("memo.message")
local NoteBackup = require("memo.note_backup")
local selection = require("memo.selection")
local utils = require("memo.utils")
local window = require("memo.window")

local M = {}

---@class MemoRefileOpts
---@field range? integer Command range indicator
---@field line1? integer First line of the command range
---@field line2? integer Last line of the command range
---@field window? MemoWindowConfig Window configuration

---@param path string
---@return "key"|"passphrase"
local function encryption_mode(path)
	local gpg = require("memo.gpg")

	if utils.is_armored_gpg(path) and #gpg.get_file_key_ids(path) == 0 then
		return "passphrase"
	end

	return "key"
end

---@param path string
---@param bufnr integer
---@return string[]? lines
---@return string? err
local function read_note(path, bufnr)
	if not utils.file_has_content(path) then
		return {}
	end

	local result, err = crypto.decrypt_to_stdout(path, bufnr)

	if not result then
		return nil, err
	end

	local output = result.stdout or ""
	local lines = vim.split(output, "\n", { plain = true })

	if output:sub(-1) == "\n" then
		table.remove(lines)
	end

	return lines
end

---@param path string
---@param lines string[]
---@param bufnr integer
---@return boolean success
---@return string? err
local function append_to_note(path, lines, bufnr)
	local existing, err = read_note(path, bufnr)

	if not existing then
		return false, err
	end

	if #existing > 0 and #lines > 0 then
		vim.list_extend(existing, { "" })
	end

	vim.list_extend(existing, lines)

	local existed = utils.file_exists(path)
	local mode = utils.file_has_content(path) and encryption_mode(path) or "key"
	local backup = NoteBackup.new(path)
	local success, write_err = backup:protect(function()
		return crypto.encrypt_from_stdin(path, existing, bufnr, { mode = mode })
	end)

	if not success and not existed and utils.file_exists(path) then
		vim.fn.delete(path)
	end

	return success, write_err
end

---@param config MemoRefileOpts
---@return integer buf
local function create_refile_window(config)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_exec_autocmds("BufReadPre", { buffer = buf, modeline = false })

	local win = window.open(config.window)
	vim.api.nvim_win_set_buf(win, buf)

	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].undofile = false
	vim.bo[buf].fileencoding = "utf-8"

	vim.api.nvim_buf_set_name(buf, "refile://selection")
	vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buf, modeline = false })

	return buf
end

---Opens an editable window with the selection. On write, prompts for a note
---path, appends the edited content, then removes the original selection.
---@param opts? MemoRefileOpts
---@return boolean
function M.create(opts)
	local source_buf = vim.api.nvim_get_current_buf()
	local lines, selected = selection.resolve(source_buf, opts)

	if not lines or not selected or #lines == 0 then
		message.error("MemoRefile: select text to refile")
		return false
	end

	local buf = create_refile_window(opts or {})
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modified = false

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			vim.api.nvim_exec_autocmds("BufWritePre", { buffer = buf, modeline = false })

			local content = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

			if table.concat(content, "\n"):gsub("%s+", "") == "" then
				message.warn("MemoRefile: empty content")
				return
			end

			local target = utils.prompt_note_path("", "MemoRefile")

			if not target then
				return
			end

			local path = utils.resolve_note_path(target)

			if not path then
				message.defer_error("MemoRefile: note path must be inside the notes directory (%s)", require("memo.config").notes_dir)
				return
			end

			if not utils.ensure_directories(vim.fs.dirname(path)) then
				return
			end

			local saved, err = append_to_note(path, content, buf)

			if not saved then
				if err then
					message.defer_error("MemoRefile: %s", err)
				end
				return
			end

			selection.delete_selection(source_buf, selected)
			message.info("Refiled text to %s", path)
			vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf, modeline = false })
			vim.api.nvim_buf_delete(buf, { force = true })
		end,
	})

	return true
end

return M
