local M = {}
local utils = require("memo.utils")
local window = require("memo.window")

---@return string cwd key used to prefix scratch filenames of the current
---directory, e.g. "%Users%dev%project"
function M.cwd_key()
	return (vim.fn.getcwd():gsub("[^%w%-]", "%%"))
end

---Decode an encoded cwd key into a readable path, for display purposes only.
---@param key string e.g. "%Users%dev%project"
---@return string e.g. "/Users/dev/project"
function M.decode_cwd_key(key)
	return (key:gsub("%%", "/"))
end

---Encode a cwd path into the key used to prefix scratch filenames.
---@param path string
---@return string
function M.encode_cwd_key(path)
	return (path:gsub("[^%w%-]", "%%"))
end

---Match the "<cwd key>-<timestamp>-<hash>.<ext>" parts of a scratch filename.
---The extension is captured rather than hardcoded, so a scratch file keeps the
---extension it was created with.
---@param filename string
---@return string? key
---@return string? timestamp
---@return string? hash
---@return string? ext
local function match_parts(filename)
	local ext = utils.get_extension(filename)

	if not ext then
		return nil
	end

	-- The hash is wrapped in its own capture group: Lua's pattern engine
	-- would otherwise return the previous capture for it after backtracking
	-- the greedy leading `(.*)`.
	local key, ts, hash =
		filename:match("^(.*)%-(%d%d%d%d%d%d%d%dT%d%d%d%d%d%d)%-([%x][%x][%x][%x][%x][%x])%." .. ext .. "$")

	if not key then
		return nil
	end

	return key, ts, hash, ext
end

---Rewrite a scratch filename for display as "<cwd path>-<timestamp>-<hash>.<ext>".
---@param filename string
---@return string
function M.display_scratch(filename)
	local key, ts, hash, ext = match_parts(filename)
	if not key then
		return filename
	end
	return M.decode_cwd_key(key) .. "-" .. ts .. "-" .. hash .. "." .. ext
end

---Recover the real scratch filename from a line rendered by `display_scratch`.
---@param entry string
---@return string
function M.filename_from_display(entry)
	local key, ts, hash, ext = match_parts(entry)
	if not key then
		return entry
	end
	return M.encode_cwd_key(key) .. "-" .. ts .. "-" .. hash .. "." .. ext
end

---@return string
local function get_timestamp()
	return os.date("!%Y%m%dT%H%M%S")
end

---@return string
local function get_hash()
	return vim.fn.sha256(tostring(vim.uv.hrtime())):sub(1, 6)
end

---@return string|nil -- nil when the scratch directory could not be created
local function get_scratch_file()
	local dir = require("memo.config").scratch_dir
	if not utils.ensure_directories(dir) then
		return nil
	end

	local base = M.cwd_key() .. "-" .. get_timestamp() .. "-" .. get_hash()

	return vim.fs.joinpath(dir, base .. "." .. require("memo.config").extension)
end

---@class MemoScratchOpts
---@field window? MemoWindowConfig opens the scratch in a split; a scratch
---always splits by default
---@field encryption? GpgEncryptOpts how to encrypt, "key" when omitted

---@param opts? MemoScratchOpts
function M.create(opts)
	local file = get_scratch_file()
	if not file then
		return
	end

	window.open(opts and opts.window)

	vim.cmd("silent edit " .. vim.fn.fnameescape(file))

	-- A scratch file is always new: its write handler carries the mode of the
	-- first write, later writes read it back from the file.
	local mode = opts and opts.encryption and opts.encryption.mode
	if mode then
		require("memo.autocmd_callbacks").register_write(vim.api.nvim_get_current_buf(), mode)
	end
end

function M.is_scratch_file(path)
	local filename = vim.fn.fnamemodify(path, ":t")

	local key = match_parts(filename)

	return key ~= nil and key ~= ""
end

---Lists the scratch files stored for the current cwd, oldest first.
---@return string[] absolute paths
function M.files_for_cwd()
	local dir = require("memo.config").scratch_dir
	local prefix = M.cwd_key() .. "-"
	local files = {}
	local handle = vim.uv.fs_scandir(dir)
	if not handle then
		return files
	end

	while true do
		local name, ftype = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end
		if ftype == "file" and name:sub(1, #prefix) == prefix and M.is_scratch_file(name) then
			files[#files + 1] = vim.fs.joinpath(dir, name)
		end
	end

	table.sort(files)
	return files
end

return M
