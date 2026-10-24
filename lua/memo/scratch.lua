local M = {}
local utils = require("memo.utils")
local window = require("memo.window")

---@return string cwd key used to prefix scratch filenames of the current
---directory, e.g. "%2FUsers%2Fdev%2Fproject"
function M.cwd_key()
	return M.encode_cwd_key(vim.fn.getcwd())
end

---Decode an encoded cwd key into a readable path, for display purposes only.
---@param key string e.g. "%2FUsers%2Fdev%2Fproject"
---@return string e.g. "/Users/dev/project"
function M.decode_cwd_key(key)
	return (
		key:gsub("%%(%x%x)", function(hex)
			local byte = tonumber(hex, 16) --[[@as integer]]
			return string.char(byte)
		end)
	)
end

---Encode a cwd path into the key used to prefix scratch filenames.
---
---Every byte outside letters, digits and hyphens is percent-encoded, so the
---encoding is reversible and distinct paths can never map to the same key:
---"foo.bar" encodes differently from "foo/bar", which a single replacement
---character for both would not.
---@param path string
---@return string
function M.encode_cwd_key(path)
	return (path:gsub("[^%w%-]", function(c)
		return string.format("%%%02X", c:byte())
	end))
end

local SUFFIX = "-scratch"

---Match the "<cwd key>-scratch[.<content ext>].<note ext>" parts of a scratch
---filename. The extensions are captured rather than hardcoded, so a scratch
---file keeps the extensions it was created with.
---@param filename string
---@return string? key
---@return string? ext everything after "-scratch."
local function match_parts(filename)
	if not utils.get_extension(filename) then
		return nil
	end

	local key, ext = filename:match("^(.*)%-scratch%.(.+)$")

	if not key or key == "" then
		return nil
	end

	return key, ext
end

---Rewrite a scratch filename for display as
---"<cwd path>-scratch[.<content ext>].<note ext>".
---@param filename string
---@return string
function M.display_scratch(filename)
	local key, ext = match_parts(filename)
	if not key then
		return filename
	end
	return M.decode_cwd_key(key) .. SUFFIX .. "." .. ext
end

---Recover the real scratch filename from a line rendered by `display_scratch`.
---@param entry string
---@return string
function M.filename_from_display(entry)
	local key, ext = match_parts(entry)
	if not key then
		return entry
	end
	return M.encode_cwd_key(key) .. SUFFIX .. "." .. ext
end

---The scratch file for the current cwd. There is exactly one per cwd.
---@param extension string? content extension, e.g. "md"
---@return string
local function scratch_file(extension)
	local config = require("memo.config")
	local name = M.cwd_key() .. SUFFIX

	if extension and extension ~= "" then
		name = name .. "." .. extension
	end

	return vim.fs.joinpath(config.scratch_dir, name .. "." .. config.extension)
end

---Opens `file` in a window, reusing its buffer when it is already loaded so
---unsaved scratch content is never reloaded or lost.
---@param file string
---@param win_config? MemoWindowConfig
---@return integer bufnr
local function open_file(file, win_config)
	local win = window.open(win_config)
	local bufnr = vim.fn.bufnr(file)

	vim.api.nvim_win_call(win, function()
		if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
			vim.api.nvim_win_set_buf(win, bufnr)
		else
			vim.cmd("silent edit " .. vim.fn.fnameescape(file))
		end
	end)

	return vim.api.nvim_win_get_buf(win)
end

---@class MemoScratchOpts
---@field window? MemoWindowConfig opens the scratch in a split; a scratch
---always splits by default
---@field encryption? GpgEncryptOpts how to encrypt, "key" when omitted
---@field extension? string content extension of a new scratch file, e.g.
---"md" for a Markdown scratch buffer; the note extension still follows it

---Opens the scratch file for the current cwd, creating it on first use.
---@param opts? MemoScratchOpts
---@return boolean success
function M.open_or_create(opts)
	local file = scratch_file(opts and opts.extension)
	local exists = utils.file_has_content(file)

	if not exists and not utils.ensure_directories(require("memo.config").scratch_dir) then
		return false
	end

	local buf = open_file(file, opts and opts.window)

	if exists then
		return true
	end

	local mode = opts and opts.encryption and opts.encryption.mode
	local ok = require("memo.crypto").encrypt_from_stdin(file, {}, buf, { mode = mode })

	return ok
end

return M
