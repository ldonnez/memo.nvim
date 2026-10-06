if vim.fn.has("nvim-0.11") ~= 1 then
	vim.notify("Memo requires neovim >= v0.11", vim.log.levels.ERROR, { title = "memo.nvim" })
	return
end

local config = require("memo.config")

local notes_dir = config.notes_dir
local scratch_dir = config.scratch_dir

if not notes_dir or notes_dir == "" then
	return
end

local function is_same_or_child(path, parent)
	return path == parent or vim.startswith(path, parent .. "/")
end

local abs_notes = vim.fn.fnamemodify(notes_dir, ":p"):gsub("/$", "")
local abs_scratch = vim.fn.fnamemodify(scratch_dir, ":p"):gsub("/$", "")

-- Notes may live in subdirectories (e.g. `journals/2026-01-01.md.asc`), so the
-- notes pattern has to match recursively.
local patterns = { abs_notes .. "/**" }

if not is_same_or_child(abs_scratch, abs_notes) then
	table.insert(patterns, abs_scratch .. "/*")
end

local GROUP = vim.api.nvim_create_augroup("MemoGpg", { clear = true })

vim.api.nvim_create_autocmd("BufReadCmd", {
	group = GROUP,
	pattern = patterns,
	callback = function(args)
		local memo = require("memo.autocmd_callbacks")
		memo.on_read(args)
	end,
})

vim.api.nvim_create_autocmd("BufWriteCmd", {
	group = GROUP,
	pattern = patterns,
	callback = function(args)
		local memo = require("memo.autocmd_callbacks")
		memo.on_write(args)
	end,
})

vim.api.nvim_create_autocmd("BufDelete", {
	group = GROUP,
	-- Scratch files carry the configured note extension, but a file written
	-- before it changed must be cleaned up as well.
	pattern = abs_scratch .. "/*",
	callback = function(args)
		local path = vim.api.nvim_buf_get_name(args.buf)
		local scratch = require("memo.scratch")

		if not scratch.is_scratch_file(path) then
			return
		end

		if vim.fn.filereadable(path) == 1 then
			vim.fn.delete(path)
		end
	end,
})

--- Splits the arguments of `:MemoNewNote` into an encryption mode and a path.
--- `passphrase` and `key` are reserved as the mode, so they come first:
--- `:MemoNewNote passphrase journals/2026-01-01.md`.
--- @param fargs string[] the command arguments, split on whitespace
--- @return "passphrase"|"key"? mode nil when none was given
--- @return string? path everything after the mode, joined back up
local function split_mode(fargs)
	if fargs[1] == "passphrase" or fargs[1] == "key" then
		return fargs[1], table.concat(vim.list_slice(fargs, 2), " ")
	end

	return nil, table.concat(fargs, " ")
end

--- Completes the mode, which only has a place while it is still the first
--- argument.
--- @param arglead string the argument being completed
--- @param cmdline string the whole command line
--- @return string[]
local function complete_mode(arglead, cmdline)
	local rest = cmdline:match("^%S+%s*(.*)$") or ""

	if (rest:gsub("%S*$", ""):match("^%s*(.-)%s*$") or "") ~= "" then
		return {}
	end

	return vim.tbl_filter(function(candidate)
		return vim.startswith(candidate, arglead)
	end, { "passphrase", "key" })
end

vim.api.nvim_create_user_command("MemoScratch", function(opts)
	require("memo.scratch").create(opts.args)
end, {
	nargs = "?",
	complete = function()
		return { "horizontal", "vertical", "tab" }
	end,
	desc = "Open an encrypted scratch buffer",
})

vim.api.nvim_create_user_command("MemoFiles", function()
	require("memo.pickers.fzf_lua").files_picker()
end, {
	nargs = 0,
	desc = "Browse and open files",
})

vim.api.nvim_create_user_command("MemoScratchFiles", function()
	require("memo.pickers.fzf_lua").scratch_files_picker()
end, {
	nargs = 0,
	desc = "Browse and open encrypted scratch files",
})

vim.api.nvim_create_user_command("MemoScratchFilesCwd", function()
	require("memo.pickers.fzf_lua").cwd_scratch_files_picker()
end, {
	nargs = 0,
	desc = "Browse and open encrypted scratch files for the current directory",
})

vim.api.nvim_create_user_command("MemoSaveAsNote", function(opts)
	local message = require("memo.message")
	-- The buffer is the path, so anything but a mode here is a mistake.
	local mode, path = split_mode(opts.fargs)

	if path ~= "" then
		message.error("MemoSaveAsNote: expected passphrase or key, got %q", path)
		return
	end

	require("memo.save_as_note").create({
		range = opts.range,
		line1 = opts.line1,
		line2 = opts.line2,
		encryption = { mode = mode },
	})
end, {
	nargs = "?",
	range = true,
	complete = complete_mode,
	desc = "Save the current buffer or selection as an encrypted note in the notes dir",
})

vim.api.nvim_create_user_command("MemoNewNote", function(opts)
	-- An empty path makes `create` prompt for it.
	local mode, path = split_mode(opts.fargs)

	require("memo.new_note").create({
		path = path,
		range = opts.range,
		line1 = opts.line1,
		line2 = opts.line2,
		encryption = { mode = mode },
	})
end, {
	nargs = "*",
	range = true,
	complete = complete_mode,
	desc = "Create a new encrypted note in the notes dir",
})

vim.api.nvim_create_user_command("Memo", function()
	require("memo").open()
end, {
	nargs = 0,
	desc = "Open the default capture file",
})

vim.api.nvim_create_user_command("MemoSync", function(opts)
	local sync = require("memo.sync")
	local message = require("memo.message")
	local backend = opts.args

	if backend == "git" or backend == "" then
		return sync.sync_git()
	end

	message.error("Unknown sync backend: %s", backend)
end, {
	nargs = "?",
	complete = function()
		return { "git" }
	end,
	desc = "Sync memos",
})
