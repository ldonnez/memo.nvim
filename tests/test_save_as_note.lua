local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("save_as_note", function()
	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		-- Load tested plugin
		child.lua([[ M = require('memo.save_as_note') ]])
	end)

	after_each(function()
		child.stop()
	end)

	describe("with gpg key without password", function()
		setup(function()
			helpers.setup_test_env()
			helpers.create_gpg_key("mock@example.com")
		end)

		teardown(function()
			helpers.cleanup_test_env()
			helpers.kill_gpg_agent()
		end)

		it("saves a plain buffer in the notes dir and keeps it open", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Plain buffer content", "<Esc>")

			child.lua("vim.fn.input = function() return 'plain' end")
			child.cmd("MemoSaveAsNote")

			local note = vim.env.NOTES_DIR .. "/plain.gpg"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), source)

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Plain buffer content") ~= nil, true)
		end)

		it("saves a buffer not under the notes dir", function()
			local source = vim.env.HOME .. "/todo.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Unrelated content", "<Esc>")

			child.lua("vim.fn.input = function() return 'imported' end")
			child.cmd("MemoSaveAsNote")

			local note = vim.env.NOTES_DIR .. "/imported.gpg"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), source)
		end)

		it("defaults to the notes dir path with .gpg", function()
			local note = vim.env.NOTES_DIR .. "/my-note.md.gpg"
			child.cmd("edit " .. vim.fn.fnameescape(note))
			child.type_keys("i", "content", "<Esc>")

			child.lua([[
        vim.g.input_default = nil
        vim.fn.input = function(_prompt, default)
          vim.g.input_default = default
          return default
        end
      ]])
			child.cmd("MemoSaveAsNote")

			local saved = vim.env.NOTES_DIR .. "/my-note.md.gpg"
			MiniTest.expect.equality(child.g.input_default, vim.env.NOTES_DIR .. "/my-note.md.gpg")
			MiniTest.expect.equality(child.fn.filereadable(saved), 1)

			local result = helpers.decrypt_file(saved)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("content") ~= nil, true)
		end)

		it("defaults to the notes dir path for non-gpg buffers", function()
			local path = vim.env.HOME .. "/todo.txt"
			child.cmd("edit " .. vim.fn.fnameescape(path))

			child.lua([[
        vim.g.input_default = nil
        vim.fn.input = function(_prompt, default)
          vim.g.input_default = default
          return default
        end
      ]])
			child.cmd("MemoSaveAsNote")

			MiniTest.expect.equality(child.g.input_default, vim.env.NOTES_DIR .. "/todo.txt.gpg")
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/todo.txt.gpg"), 1)
		end)

		it("creates subdirectories for nested note names", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "nested", "<Esc>")

			child.lua("vim.fn.input = function() return 'projects/idea' end")
			child.cmd("MemoSaveAsNote")

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/projects/idea.gpg"), 1)
		end)

		it("aborts when the note name is empty", function()
			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/random.txt"))

			child.lua("vim.fn.input = function() return '' end")
			local result = child.lua_get("{ pcall(function() return M.create() end) }")

			MiniTest.expect.equality(result[1], true)
			MiniTest.expect.equality(result[2], false)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), vim.env.NOTES_DIR .. "/random.txt")
		end)

		it("refuses to overwrite when user declines", function()
			local existing = vim.env.NOTES_DIR .. "/occupied.gpg"
			helpers.encrypt_file(existing, "old content\n")

			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/random.txt"))
			child.type_keys("i", "new content", "<Esc>")

			child.lua("vim.fn.input = function() return 'occupied' end")
			child.lua("vim.fn.confirm = function() return 2 end")
			local result = child.lua_get("{ pcall(function() return M.create() end) }")

			MiniTest.expect.equality(result[1], true)
			MiniTest.expect.equality(result[2], false)

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout:find("old content") ~= nil, true)
		end)

		it("overwrites when user confirms", function()
			local existing = vim.env.NOTES_DIR .. "/occupied.gpg"
			helpers.encrypt_file(existing, "old content\n")

			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/random.txt"))
			child.type_keys("i", "new content", "<Esc>")

			child.lua("vim.fn.input = function() return 'occupied' end")
			child.lua("vim.fn.confirm = function() return 1 end")
			local result = child.lua_get("{ pcall(function() return M.create() end) }")

			MiniTest.expect.equality(result[1], true)
			MiniTest.expect.equality(result[2], true)

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout:find("new content") ~= nil, true)
		end)

		it("refuses an absolute path outside the notes dir", function()
			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/random.txt"))

			child.lua("vim.fn.input = function() return vim.env.HOME .. '/outside.gpg' end")
			local result = child.lua_get("{ pcall(function() return M.create() end) }")

			MiniTest.expect.equality(result[1], true)
			MiniTest.expect.equality(result[2], false)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.HOME .. "/outside.gpg"), 0)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), vim.env.NOTES_DIR .. "/random.txt")
		end)

		it("refuses a relative path escaping the notes dir", function()
			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/random.txt"))

			child.lua("vim.fn.input = function() return '../escape.gpg' end")
			local result = child.lua_get("{ pcall(function() return M.create() end) }")

			MiniTest.expect.equality(result[1], true)
			MiniTest.expect.equality(result[2], false)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.HOME .. "/escape.gpg"), 0)
		end)

		it("saves only the characterwise visual selection via the user command", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.api.nvim_buf_set_lines(0, 0, -1, false, {
				"alpha beta gamma",
				"delta epsilon",
			})

			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })

			child.lua("vim.fn.input = function() return 'visual' end")
			child.type_keys(":", "MemoSaveAsNote", "<CR>")

			local note = vim.env.NOTES_DIR .. "/visual.gpg"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("beta") ~= nil, true)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("alpha") ~= nil, false)
		end)

		it("saves only the visual selection when called during visual mode", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.api.nvim_buf_set_lines(0, 0, -1, false, {
				"alpha beta gamma",
				"delta epsilon",
			})

			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })

			child.lua("vim.fn.input = function() return 'direct' end")
			local result = child.lua_get("{ pcall(function() return M.create() end) }")

			MiniTest.expect.equality(result[1], true)
			MiniTest.expect.equality(result[2], true)

			local note = vim.env.NOTES_DIR .. "/direct.gpg"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)

			local decrypted = helpers.decrypt_file(note)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout:find("beta") ~= nil, true)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout:find("alpha") ~= nil, false)
		end)

		it("saves the linewise visual selection via the user command", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.api.nvim_buf_set_lines(0, 0, -1, false, {
				"alpha",
				"beta",
				"gamma",
				"delta",
			})

			child.api.nvim_win_set_cursor(0, { 2, 0 })
			child.cmd("normal! V")
			child.api.nvim_win_set_cursor(0, { 3, 4 })

			child.lua("vim.fn.input = function() return 'visual-lines' end")
			child.type_keys(":", "MemoSaveAsNote", "<CR>")

			local note = vim.env.NOTES_DIR .. "/visual-lines.gpg"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("beta") ~= nil, true)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("gamma") ~= nil, true)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("alpha") ~= nil, false)
		end)
	end)

	describe("with gpg key with password", function()
		local gpg_key_password = "test"

		setup(function()
			helpers.setup_test_env()
			helpers.create_gpg_key("mock-password@example.com", gpg_key_password)
		end)

		teardown(function()
			helpers.cleanup_test_env()
		end)

		after_each(function()
			helpers.kill_gpg_agent()
		end)

		it("saves a plain buffer when gpg key has password", function()
			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/random.txt"))
			child.type_keys("i", "Secret plain content", "<Esc>")

			helpers.cache_gpg_password(gpg_key_password)
			child.lua("vim.fn.input = function() return 'pw-plain' end")
			child.cmd("MemoSaveAsNote")

			local note = vim.env.NOTES_DIR .. "/pw-plain.gpg"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), vim.env.NOTES_DIR .. "/random.txt")

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Secret plain content") ~= nil, true)
		end)
	end)
end)
