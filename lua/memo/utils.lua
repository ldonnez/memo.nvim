local M = {}

---The note extension of `path`, e.g. "gpg" for "note.md.gpg". Nil for any other
---extension, so a plaintext "note.md" still gets a note extension appended.
---@param path string
---@return string? ext nil when the path carries no note extension
function M.get_extension(path)
	local ext = path:match("%.(%a+)$")

	return ext and vim.tbl_contains(require("memo.config").supported_extensions, ext) and ext or nil
end

---Strips the note extension of `path` (e.g. "note.md.gpg" -> "note.md").
---@param path string
---@return string
function M.strip_extension(path)
	local ext = M.get_extension(path)

	return ext and path:sub(1, #path - #ext - 1) or path
end

---Resolves a path for a note file, adding the default extension if needed.
---If a supported extension is provided, it's respected. Otherwise default is added.
---@param path string
---@return string
function M.resolve_note_file(path)
	if path == "" then
		require("memo.message").error("resolve_note_file: empty path")
		return ""
	end

	if path:sub(-1) == "/" then
		require("memo.message").error("resolve_note_file: path is a directory")
		return ""
	end

	local had_extension = M.get_extension(path) ~= nil
	if had_extension then
		return path
	end

	return path .. "." .. require("memo.config").extension
end

---Checks whether `path` is inside `dir` after resolving both to absolute paths.
---@param path string
---@param dir string
---@return boolean
function M.is_in_dir(path, dir)
	local abs_path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p") --[[@as string]])
	local abs_dir = vim.fs.normalize(vim.fn.fnamemodify(dir, ":p") --[[@as string]])
	return abs_path:sub(1, #abs_dir) == abs_dir and abs_path:sub(#abs_dir + 1, #abs_dir + 1) == "/"
end

---Checks whether a readable file exists at `path`.
---@param path string
---@return boolean
function M.file_exists(path)
	return vim.fn.filereadable(path) == 1
end

---Checks whether a file exists at `path` and holds content. Notes are treated
---as missing while they are still empty, e.g. right after creation and before
---the first write.
---@param path string
---@return boolean
function M.file_has_content(path)
	return M.file_exists(path) and vim.fn.getfsize(path) > 0
end

---Prompts the user with a yes/no question. Warns and returns false when
---declined, so callers can treat a decline as a plain abort.
---@param prompt string question shown in the dialog
---@param title string command name used in the message
---@return boolean
function M.confirm(prompt, title)
	local choice = vim.fn.confirm(prompt, "&Yes\n&No", 2)

	if choice ~= 1 then
		require("memo.message").warn("%s: aborted", title)
		return false
	end

	return true
end

---Builds a full note path for `name` inside the notes directory.
---@param name string note name, with or without an note extension
---@return string
function M.build_note_path(name)
	local notes_dir = require("memo.config").notes_dir

	if name == "" then
		return ""
	end

	if name:sub(1, 1) == "/" then
		return ""
	end

	local path = notes_dir .. "/" .. name

	local resolved = M.resolve_note_file(path)

	if not M.is_in_dir(resolved, notes_dir) then
		return ""
	end

	return resolved
end

---Resolves a supplied note path to an absolute note path inside the notes
---directory. Relative paths are resolved against the notes dir and `~` is
---expanded. A supported extension that is already there is kept, otherwise the
---configured one is appended.
---@param path string
---@return string? note_path nil when the path is empty or escapes the notes dir
function M.resolve_note_path(path)
	local notes_dir = require("memo.config").notes_dir
	local expanded = vim.fn.expand(path) --[[@as string]]

	if expanded == "" then
		return nil
	end

	local target = expanded:sub(1, 1) == "/" and expanded or (notes_dir .. "/" .. expanded)
	local note_path = M.resolve_note_file(target)

	return M.is_in_dir(note_path, notes_dir) and note_path or nil
end

---Prompts for a note path, pre-filled with `default_path`.
---@param default_path string
---@param title string command name used in the message
---@return string? path nil when an empty path was entered
function M.prompt_note_path(default_path, title)
	local target = vim.fn.input("Note path: ", default_path, "file")

	if target == "" then
		require("memo.message").warn("%s: empty note path", title)
		return nil
	end

	return target
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

---Resolves the lines to save: the active visual selection, or the lines given
---by an explicit command range (e.g. `:'<,'>MemoSaveAsNote`), or nil to fall
---back to the whole buffer.
---@param bufnr integer
---@param opts? { range?: integer, line1?: integer, line2?: integer }
---@return string[]|nil
function M.resolve_selection(bufnr, opts)
	if vim.fn.mode():match("[vV\22]") then
		local start = vim.fn.getpos("v")
		local finish = vim.fn.getpos(".")

		if start[2] ~= 0 and finish[2] ~= 0 then
			return vim.fn.getregion(start, finish)
		end
	end

	if opts and opts.range and opts.range ~= 0 then
		local start = vim.fn.getpos("'<")
		local finish = vim.fn.getpos("'>")
		local in_buffer = function(pos)
			return pos[1] == 0 or pos[1] == bufnr
		end
		if in_buffer(start) and in_buffer(finish) and start[2] ~= 0 and finish[2] ~= 0 then
			return vim.fn.getregion(start, finish)
		end
		local line1 = opts.line1 --[[@as integer]]
		local line2 = opts.line2 --[[@as integer]]
		return vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
	end

	return nil
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

--- Reports why something failed and throws the buffer away. Leaving a buffer in
--- place after a failure tends to freeze it: `modifiable` stays false and
--- nothing would reset it.
--- @param bufnr integer
--- @param message string
function M.drop_buffer_with_error(bufnr, message)
	require("memo.message").defer_error("%s", message)
	vim.schedule(function()
		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	end)
end

return M
