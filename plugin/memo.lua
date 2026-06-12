local M = {}

function M.setup()
	local notes_dir = vim.fn.expand(vim.g.memo_notes_dir or "~/notes") --[[@as string]]

	if not notes_dir or notes_dir == "" then
		return
	end

	local abs_notes = vim.fn.fnamemodify(notes_dir, ":p")
	local GROUP = vim.api.nvim_create_augroup("MemoGpg", { clear = true })

	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = GROUP,
		pattern = {
			abs_notes .. "*.{md,txt,org}",
			abs_notes .. "*.{md,txt,org}.gpg",
		},
		callback = function(args)
			local memo = require("memo.autocmd_callbacks")
			memo.on_read(args)
		end,
	})

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = GROUP,
		pattern = {
			abs_notes .. "*.{md,txt,org}",
			abs_notes .. "*.{md,txt,org}.gpg",
		},
		callback = function(args)
			local memo = require("memo.autocmd_callbacks")
			memo.on_write(args)
		end,
	})

	if vim.g.memo_conform_integration ~= false then
		vim.api.nvim_create_autocmd("BufReadCmd", {
			once = true,
			pattern = {
				abs_notes .. "*.{md,txt,org}",
				abs_notes .. "*.{md,txt,org}.gpg",
			},
			callback = function()
				require("memo.autocmd_callbacks").setup_conform()
			end,
		})
	end

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
