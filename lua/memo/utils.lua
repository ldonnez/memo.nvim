local M = {}

---Ensures path ends with .gpg
---@param path string
---@return string
function M.get_gpg_path(path)
	if path == "" or path:match("%.gpg$") then
		return path
	end
	return path .. ".gpg"
end

---Checks whether `path` is inside `dir` after resolving both to absolute paths.
---@param path string
---@param dir string
---@return boolean
function M.is_in_dir(path, dir)
	local abs_path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p") --[[@as string]]) --[[@as string]]
	local abs_dir = vim.fs.normalize(vim.fn.fnamemodify(dir, ":p") --[[@as string]]) --[[@as string]]
	return abs_path:sub(1, #abs_dir) == abs_dir and abs_path:sub(#abs_dir + 1, #abs_dir + 1) == "/"
end

---Ensures a directory exists, creating it (including any missing parents)
---when needed.
---@param dir string
---@return boolean -- true when the directory exists (or was created)
function M.ensure_directories(dir)
	if vim.fn.isdirectory(dir) == 1 then
		return true
	end

	local ok, err = pcall(vim.fn.mkdir, dir, "p")
	if not ok then
		require("memo.message").error("Error creating directory: %s", tostring(err))
		return false
	end

	return true
end

---@param cmd string
---@return boolean
function M.check_exec(cmd)
	if vim.fn.executable(cmd) == 0 then
		local message = require("memo.message")
		message.error("'%s' binary not found", cmd)
		return false
	end
	return true
end

---Lazily load a plugin with fallback to packadd (only for Neovim 0.12+)
---@param import_name string e.g. "conform"
---@param plugin_name string? e.g. "conform.nvim", defaults to import_name
---@return any?
function M.load_plugin(import_name, plugin_name)
	local ok, mod = pcall(require, import_name)

	if not ok and vim.fn.has("nvim-0.12") == 1 then
		local pack_name = plugin_name or import_name
		pcall(vim.cmd.packadd, pack_name)
		_, mod = pcall(require, import_name)
	end
	return mod
end

return M
