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

local patterns = { abs_notes .. "/*" }

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
	pattern = abs_scratch .. "/*.gpg",
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
	require("memo.core").save_as_note({ range = opts.range, line1 = opts.line1, line2 = opts.line2 })
end, {
	nargs = 0,
	range = true,
	desc = "Save the current buffer or selection as an encrypted note in the notes dir",
})

vim.api.nvim_create_user_command("MemoSync", function(opts)
	local core = require("memo.core")
	local message = require("memo.message")
	local backend = opts.args

	if backend == "git" or backend == "" then
		return core.sync_git()
	end

	message.error("Unknown sync backend: %s", backend)
end, {
	nargs = "?",
	complete = function()
		return { "git" }
	end,
	desc = "Sync memos",
})
