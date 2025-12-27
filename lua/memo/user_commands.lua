local M = {}

local function setup_memo_setup()
	vim.api.nvim_create_user_command("MemoSetup", function()
		local memo = require("memo")
		local config = require("memo.config")

		if not config or next(config) == nil then
			memo.setup({ notes_dir = config.notes_dir })
		end
	end, {})
end

local function setup_memo_sync()
	vim.api.nvim_create_user_command("MemoSync", function(opts)
		local core = require("memo.core")
		local backend = opts.args

		if backend == "git" or backend == "" then
			local result = core.sync_git()
			if result and result.code == 0 then
				return vim.notify("Sync complete: git", vim.log.levels.INFO)
			end
			return vim.notify("Something went wrong syncing: " .. backend, vim.log.levels.ERROR)
		else
			vim.notify("Unknown sync backend: " .. backend, vim.log.levels.ERROR)
		end
	end, {
		nargs = "?",
		complete = function()
			-- This provides tab-completion
			return { "git" }
		end,
		desc = "Sync memos",
	})
end

function M.setup()
	setup_memo_setup()
	setup_memo_sync()
end

return M
