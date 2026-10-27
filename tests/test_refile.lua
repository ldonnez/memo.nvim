local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("refile", function()
	before_each(function()
		vim.fn.delete(vim.env.NOTES_DIR .. "/destination.md.asc", "rf")

		for _, backup in ipairs(vim.fn.glob(vim.env.NOTES_DIR .. "/destination.md.memo-backup-*.asc", false, true)) do
			vim.fn.delete(backup)
		end

		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		child.lua(
			[[
			vim.g.memo_notes_dir = ...
			require("memo.config").setup()

			local crypto = require("memo.crypto")
			crypto.decrypt_to_stdout = function(path)
				return { code = 0, stdout = table.concat(vim.fn.readfile(path), "\n") .. "\n" }
			end
			crypto.encrypt_from_stdin = function(path, lines)
				vim.fn.writefile(lines, path)
				return true
			end

			require("memo.utils").prompt_note_path = function()
				return "destination.md"
			end

			M = require("memo.refile")
			]],
			{ vim.env.NOTES_DIR }
		)
	end)

	after_each(function()
		child.stop()
	end)

	setup(function()
		helpers.setup_test_env()
	end)

	teardown(function()
		helpers.cleanup_test_env()
	end)

	it("opens a split by default and preserves the source filetype", function()
		local source = child.api.nvim_get_current_buf()
		local source_win = child.api.nvim_get_current_win()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "selected" })
		child.api.nvim_set_option_value("filetype", "markdown", { buf = source })
		MiniTest.expect.equality(child.api.nvim_get_option_value("filetype", { buf = source }), "markdown")

		child.lua([[ M.create({ range = 1, line1 = 1, line2 = 1 }) ]])

		local refile_buf = child.api.nvim_get_current_buf()
		MiniTest.expect.equality(child.api.nvim_get_current_win() ~= source_win, true)
		MiniTest.expect.equality(child.api.nvim_win_get_buf(source_win), source)
		MiniTest.expect.equality(refile_buf ~= source, true)
		MiniTest.expect.equality(child.api.nvim_get_option_value("filetype", { buf = refile_buf }), "markdown")
	end)

	it("uses the notes directory as the destination prompt default", function()
		child.lua([[
			require("memo.utils").prompt_note_path = function(default_path)
				prompt_default = default_path
				return nil
			end
		]])
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "selected" })

		child.lua([[ M.create({ range = 1, line1 = 1, line2 = 1 }) ]])
		child.cmd("write")

		MiniTest.expect.equality(child.lua_get("prompt_default"), vim.env.NOTES_DIR .. "/")
	end)

	it("appends the selection and removes it from the source after writing", function()
		local source = child.api.nvim_get_current_buf()
		local source_win = child.api.nvim_get_current_win()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "before", "move me", "after" })

		local destination = vim.env.NOTES_DIR .. "/destination.md.asc"
		vim.fn.writefile({ "existing" }, destination)

		child.lua([[ M.create({ range = 1, line1 = 2, line2 = 2, window = { split = "split" } }) ]])
		child.cmd("write")

		MiniTest.expect.equality(vim.fn.readfile(destination), { "existing", "", "move me" })
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "before", "after" })
		MiniTest.expect.equality(child.api.nvim_get_current_win(), source_win)
		MiniTest.expect.equality(child.api.nvim_get_current_buf(), source)
	end)

	it("creates a destination and moves edited content into it", function()
		local source = child.api.nvim_get_current_buf()
		local source_win = child.api.nvim_get_current_win()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "before", "selected", "after" })

		child.lua([[ M.create({ range = 1, line1 = 2, line2 = 2 }) ]])
		child.api.nvim_buf_set_lines(child.api.nvim_get_current_buf(), 0, -1, false, { "edited", "content" })
		child.cmd("write")

		MiniTest.expect.equality(vim.fn.readfile(vim.env.NOTES_DIR .. "/destination.md.asc"), { "edited", "content" })
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "before", "after" })
		MiniTest.expect.equality(child.api.nvim_get_current_win(), source_win)
		MiniTest.expect.equality(child.api.nvim_get_current_buf(), source)
	end)

	it("uses a relative target_file without prompting", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "move me" })

		child.lua([[
			require("memo.utils").prompt_note_path = function()
				error("should not prompt")
			end
			M.create({ range = 1, line1 = 1, line2 = 1, target_file = "nested/target.md" })
		]])

		child.cmd("write")

		local destination = vim.env.NOTES_DIR .. "/nested/target.md.asc"
		MiniTest.expect.equality(vim.fn.readfile(destination), { "move me" })
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "" })
	end)

	it("uses an absolute target_file without prompting", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "move me" })

		local destination = vim.env.NOTES_DIR .. "/absolute-target.md.asc"
		child.lua(
			[[
			require("memo.utils").prompt_note_path = function()
				error("should not prompt")
			end
			M.create({ range = 1, line1 = 1, line2 = 1, target_file = ... })
		]],
			{ destination }
		)

		child.cmd("write")

		MiniTest.expect.equality(vim.fn.readfile(destination), { "move me" })
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "" })
	end)

	it("does not write when the source buffer is not modifiable", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "keep me" })
		child.lua([[ vim.bo[vim.api.nvim_get_current_buf()].modifiable = false ]])

		child.lua([[ M.create({ range = 1, line1 = 1, line2 = 1 }) ]])
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "keep me" })
		MiniTest.expect.equality(vim.fn.filereadable(vim.env.NOTES_DIR .. "/destination.md.asc"), 0)
	end)

	it("rejects a destination that is not a regular file", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "keep me" })
		local destination = vim.env.NOTES_DIR .. "/destination.md.asc"
		vim.fn.mkdir(destination, "p")

		child.lua([[ M.create({ range = 1, line1 = 1, line2 = 1 }) ]])
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "keep me" })
		MiniTest.expect.equality(vim.fn.isdirectory(destination), 1)
	end)

	it("does not refile a stale selection when the source changes before writing", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "keep me" })

		child.lua([[ M.create({ range = 1, line1 = 1, line2 = 1 }) ]])
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "changed source" })
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "changed source" })
		MiniTest.expect.equality(vim.fn.filereadable(vim.env.NOTES_DIR .. "/destination.md.asc"), 0)
	end)

	it("keeps the source when it changes during the destination write", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "keep me" })

		local destination = vim.env.NOTES_DIR .. "/destination.md.asc"
		vim.fn.writefile({ "existing" }, destination)

		child.lua([[
			require("memo.crypto").encrypt_from_stdin = function(path, lines)
				vim.api.nvim_buf_set_lines(1, 0, -1, false, { "changed during write" })
				vim.fn.writefile(lines, path)
				return true
			end
			M.create({ range = 1, line1 = 1, line2 = 1 })
		]])
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "changed during write" })
		MiniTest.expect.equality(vim.fn.readfile(destination), { "existing" })
		MiniTest.expect.equality(child.fn.glob(vim.env.NOTES_DIR .. "/destination.md.memo-backup-*.asc"), "")
	end)

	it("reports an explicit warning when destination rollback fails", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "keep me" })

		local destination = vim.env.NOTES_DIR .. "/destination.md.asc"
		vim.fn.writefile({ "existing" }, destination)

		child.lua([[
			local rename = vim.uv.fs_rename
			vim.uv.fs_rename = function(from, to)
				if from:find(".memo-backup-", 1, true) then
					return nil, "rename failed"
				end
				return rename(from, to)
			end
			require("memo.crypto").encrypt_from_stdin = function(path, lines)
				vim.api.nvim_buf_set_lines(1, 0, -1, false, { "changed during write" })
				vim.fn.writefile(lines, path)
				return true
			end
			M.create({ range = 1, line1 = 1, line2 = 1 })
		]])
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "changed during write" })
		MiniTest.expect.equality(vim.fn.readfile(destination), { "existing", "", "keep me" })

		child.wait_until(function()
			return child.cmd_capture("messages"):find("could not be restored", 1, true) ~= nil
		end)

		local messages = child.cmd_capture("messages")
		MiniTest.expect.equality(messages:find("source changed while writing", 1, true) ~= nil, true)
	end)

	it("restores an empty destination as a zero-byte file when the source changes", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "keep me" })

		local destination = vim.env.NOTES_DIR .. "/destination.md.asc"
		helpers.write_file(destination, "")

		child.lua([[
			require("memo.crypto").encrypt_from_stdin = function(path, lines)
				vim.api.nvim_buf_set_lines(1, 0, -1, false, { "changed during write" })
				vim.fn.writefile(lines, path)
				return true
			end
			M.create({ range = 1, line1 = 1, line2 = 1 })
		]])
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "changed during write" })
		MiniTest.expect.equality(vim.fn.filereadable(destination), 1)
		MiniTest.expect.equality(vim.fn.getfsize(destination), 0)
	end)

	it("does not remove the source selection when the destination write fails", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "keep me" })

		child.lua([[
			require("memo.crypto").encrypt_from_stdin = function()
				return false, "write failed"
			end
			M.create({ range = 1, line1 = 1, line2 = 1 })
		]])
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "keep me" })
		MiniTest.expect.equality(child.api.nvim_buf_is_valid(child.api.nvim_get_current_buf()), true)
	end)

	it("keeps the source selection when refile content is empty", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "keep me" })

		child.lua([[ M.create({ range = 1, line1 = 1, line2 = 1 }) ]])
		child.api.nvim_buf_set_lines(child.api.nvim_get_current_buf(), 0, -1, false, { "" })
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "keep me" })
		MiniTest.expect.equality(vim.fn.filereadable(vim.env.NOTES_DIR .. "/destination.md.asc"), 0)
	end)

	it("keeps the source selection when the destination prompt is cancelled", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "keep me" })

		child.lua([[
			require("memo.utils").prompt_note_path = function()
				return nil
			end
			M.create({ range = 1, line1 = 1, line2 = 1 })
		]])
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "keep me" })
		MiniTest.expect.equality(vim.fn.filereadable(vim.env.NOTES_DIR .. "/destination.md.asc"), 0)
	end)

	it("rejects paths outside the notes directory", function()
		local source = child.api.nvim_get_current_buf()
		child.api.nvim_buf_set_lines(source, 0, -1, false, { "keep me" })

		child.lua([[
			require("memo.utils").prompt_note_path = function()
				return "../outside.md"
			end
			M.create({ range = 1, line1 = 1, line2 = 1 })
		]])
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_lines(source, 0, -1, false), { "keep me" })
		MiniTest.expect.equality(vim.fn.filereadable(vim.env.NOTES_DIR .. "/destination.md.asc"), 0)
	end)
end)
