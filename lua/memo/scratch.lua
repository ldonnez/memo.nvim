local M = {}

---@return string
local function get_cwd_key()
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

---@return string
local function get_scratch_file()
	local dir = require("memo.config").scratch_dir
	vim.fn.mkdir(dir, "p")

	return vim.fs.joinpath(dir, get_cwd_key() .. "-" .. get_timestamp() .. "-" .. get_hash() .. ".gpg")
end

---@param direction? "horizontal"|"vertical"|"tab"
function M.create(direction)
	local file = get_scratch_file()

	if direction == "vertical" then
		vim.cmd("belowright vsplit")
	elseif direction == "tab" then
		vim.cmd("tabnew")
	else
		vim.cmd("belowright split")
	end

	vim.cmd("silent edit " .. vim.fn.fnameescape(file))
end

return M
