local message = require("memo.message")

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

---@param cmd string
---@return boolean
function M.check_exec(cmd)
	if vim.fn.executable(cmd) == 0 then
		message.error("'%s' binary not found", cmd)
		return false
	end
	return true
end

---@return string
function M.get_notes_dir()
	local dir = vim.fn.expand(vim.g.memo_notes_dir or "~/notes") --[[@as string]]
	return dir
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
