local M = {}

function M.setup()
	local notes_dir = require("memo.utils").get_notes_dir()
	local scratch_dir = require("memo.utils").get_scratch_dir()

	if not notes_dir or notes_dir == "" then
		return
	end

	local abs_notes = vim.fn.fnamemodify(notes_dir, ":p")
	local abs_scratch = vim.fn.fnamemodify(scratch_dir, ":p")

	local GROUP = vim.api.nvim_create_augroup("MemoGpg", { clear = true })

	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = GROUP,
		pattern = {
			abs_notes .. "*",
			abs_scratch .. "*",
		},
		callback = function(args)
			local memo = require("memo.autocmd_callbacks")
			memo.on_read(args)
		end,
	})

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = GROUP,
		pattern = {
			abs_notes .. "*",
			abs_scratch .. "*",
		},
		callback = function(args)
			local memo = require("memo.autocmd_callbacks")
			memo.on_write(args)
		end,
	})

	vim.api.nvim_create_autocmd("BufDelete", {
		group = GROUP,
		pattern = abs_scratch .. "*.gpg",
		callback = function(args)
			local path = vim.api.nvim_buf_get_name(args.buf)

			if vim.fn.filereadable(path) == 1 then
				vim.fn.delete(path)
			end
		end,
	})

	vim.api.nvim_create_user_command("MemoScratch", function(opts)
		local direction = opts.args

		if direction ~= "horizontal" and direction ~= "vertical" and direction ~= "tab" then
			require("memo.scratch").create()
			return
		end

		require("memo.scratch").create(direction)
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

	vim.api.nvim_create_user_command("MemoSaveAsNote", function()
		require("memo.core").save_as_note()
	end, {
		nargs = 0,
		desc = "Save the current buffer as an encrypted note in the notes dir",
	})

	vim.api.nvim_create_user_command("MemoSync", function(opts)
		local core = require("memo.core")
		local message = require("memo.message")
		local backend = opts.args

		if backend == "git" or backend == "" then
			return core.sync_git()
		else
			message.error("Unknown sync backend: %s", backend)
		end
	end, {
		nargs = "?",
		complete = function()
			return { "git" }
		end,
		desc = "Sync memos",
	})
end

M.setup()

return M
