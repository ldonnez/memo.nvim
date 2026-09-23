local M = {}
local utils = require("memo.utils")

---@return string cwd key used to prefix scratch filenames of the current
---directory, e.g. "%Users%dev%project"
function M.cwd_key()
	return (vim.fn.getcwd():gsub("[^%w%-]", "%%"))
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

	return vim.fs.joinpath(dir, M.cwd_key() .. "-" .. get_timestamp() .. "-" .. get_hash() .. ".gpg")
end

---@param direction? string any direction other than "vertical"/"tab" opens a horizontal split
function M.create(direction)
	local file = get_scratch_file()
	if not file then
		return
	end

	if direction == "vertical" then
		vim.cmd("belowright vsplit")
	elseif direction == "tab" then
		vim.cmd("tabnew")
	else
		vim.cmd("belowright split")
	end

	vim.cmd("silent edit " .. vim.fn.fnameescape(file))
end

function M.is_scratch_file(path)
	local filename = vim.fn.fnamemodify(path, ":t")

	return filename:match("^[^/]+%-%d%d%d%d%d%d%d%dT%d%d%d%d%d%d%-%x%x%x%x%x%x%.gpg$") ~= nil
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
