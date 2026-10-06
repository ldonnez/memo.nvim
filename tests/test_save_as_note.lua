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
		end)

		it("saves a plain buffer in the notes dir and keeps it open", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Plain buffer content", "<Esc>")

			child.lua("vim.fn.input = function() return 'plain' end")
			child.cmd("MemoSaveAsNote")

			local note = vim.env.NOTES_DIR .. "/plain.asc"
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

			local note = vim.env.NOTES_DIR .. "/imported.asc"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), source)
		end)

		it("defaults to the notes dir path with the note extension", function()
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

			local saved = vim.env.NOTES_DIR .. "/my-note.md.asc"
			MiniTest.expect.equality(child.g.input_default, vim.env.NOTES_DIR .. "/my-note.md.asc")
			MiniTest.expect.equality(child.fn.filereadable(saved), 1)

			local result = helpers.decrypt_file(saved)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("content") ~= nil, true)
		end)

		it("defaults to the notes dir path for buffers outside the notes dir", function()
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

			MiniTest.expect.equality(child.g.input_default, vim.env.NOTES_DIR .. "/todo.txt.asc")
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/todo.txt.asc"), 1)
		end)

		it("creates subdirectories for nested note names", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "nested", "<Esc>")

			child.lua("vim.fn.input = function() return 'projects/idea' end")
			child.cmd("MemoSaveAsNote")

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/projects/idea.asc"), 1)
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

			child.lua("vim.fn.input = function() return 'occupied.gpg' end")
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

			child.lua("vim.fn.input = function() return 'occupied.gpg' end")
			child.lua("vim.fn.confirm = function() return 1 end")
			local result = child.lua_get("{ pcall(function() return M.create() end) }")

			MiniTest.expect.equality(result[1], true)
			MiniTest.expect.equality(result[2], true)

			-- The note is written where it already is, not next to it.
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/occupied.asc"), 0)

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

			local note = vim.env.NOTES_DIR .. "/visual.asc"
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

			local note = vim.env.NOTES_DIR .. "/direct.asc"
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

			local note = vim.env.NOTES_DIR .. "/visual-lines.asc"
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

	describe("with a symmetric passphrase", function()
		local passphrase = "sym-pass"

		setup(function()
			helpers.setup_test_env()
			helpers.create_gpg_key("mock@example.com")
		end)

		teardown(function()
			helpers.cleanup_test_env()
		end)

		it("saves a buffer as a passphrase note when asked", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Symmetric content", "<Esc>")

			child.lua(
				[[
      local passphrase = ...
      vim.fn.input = function() return "sym" end
      require("memo.gpg").prompt_passphrase = function() return passphrase end

      M.create({ encryption = { mode = "passphrase" } })
    ]],
				{ passphrase }
			)

			local note = vim.env.NOTES_DIR .. "/sym.asc"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(helpers.is_symmetric_file(note), true)

			local result = helpers.decrypt_symmetric_file(note, passphrase)
			MiniTest.expect.equality(vim.trim(result.stdout or ""), "Symmetric content")
		end)

		it("asks for the passphrase twice when it creates a passphrase note", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Symmetric content", "<Esc>")

			child.lua([[
      local prompts = 0
      local gpg = require("memo.gpg")

      gpg.prompt_passphrase = function()
        prompts = prompts + 1
        return "sym-pass"
      end

      vim.fn.input = function() return "sym" end

      function _G.memo_passphrase_prompts()
        return prompts
      end
    ]])

			child.lua([[
      vim.fn.input = function() return "sym-twice" end
    ]])

			child.lua_get([[ M.create({ encryption = { mode = "passphrase" } }) ]])

			MiniTest.expect.equality(child.lua_get([[ memo_passphrase_prompts() ]]), 2)
			MiniTest.expect.equality(helpers.is_symmetric_file(vim.env.NOTES_DIR .. "/sym-twice.asc"), true)
		end)

		it("does not create the note when the confirmation does not match", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Never written", "<Esc>")

			child.lua([[
      local answers = { "first answer", "second answer" }
      local prompts = 0
      local gpg = require("memo.gpg")

      gpg.prompt_passphrase = function()
        prompts = prompts + 1
        return answers[prompts]
      end

      vim.fn.input = function() return "mismatch" end
    ]])

			child.lua_get([[ M.create({ encryption = { mode = "passphrase" } }) ]])

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/mismatch.asc"), 0)
			MiniTest.expect.equality(child.cmd_capture("messages"):find("the passphrases do not match") ~= nil, true)
		end)

		it("takes the mode as a command argument", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Symmetric content", "<Esc>")

			child.lua([[
      vim.fn.input = function() return "cmd-sym" end
      require("memo.gpg").prompt_passphrase = function() return "sym-pass" end
    ]])
			child.cmd([[MemoSaveAsNote passphrase]])

			local note = vim.env.NOTES_DIR .. "/cmd-sym.asc"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(helpers.is_symmetric_file(note), true)
		end)

		it("encrypts to the key when the command is given no mode", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Key content", "<Esc>")

			child.lua([[ vim.fn.input = function() return "cmd-key" end ]])
			child.cmd([[MemoSaveAsNote]])

			local note = vim.env.NOTES_DIR .. "/cmd-key.asc"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(helpers.is_symmetric_file(note), false)
		end)

		it("rejects anything that is not a mode", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Never written", "<Esc>")

			child.lua([[pcall(vim.cmd, "MemoSaveAsNote bogus")]])

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/bogus.asc"), 0)
			MiniTest.expect.equality(
				child.cmd_capture("messages"):find([[expected passphrase or key, got "bogus"]]) ~= nil,
				true
			)
		end)

		it("encrypts to the key when symmetric is not asked for", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Key content", "<Esc>")

			child.lua("vim.fn.input = function() return 'keyed' end")
			child.cmd("MemoSaveAsNote")

			local note = vim.env.NOTES_DIR .. "/keyed.asc"
			MiniTest.expect.equality(helpers.is_symmetric_file(note), false)
		end)

		it("saves nothing when the passphrase prompt is dismissed", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Never written", "<Esc>")

			child.lua([[
      vim.fn.input = function() return "dismissed" end
      require("memo.gpg").prompt_passphrase = function() return "" end
    ]])

			local saved = child.lua_get([[ M.create({ encryption = { mode = "passphrase" } }) ]])

			MiniTest.expect.equality(saved, false)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/dismissed.asc"), 0)
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

			local note = vim.env.NOTES_DIR .. "/pw-plain.asc"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), vim.env.NOTES_DIR .. "/random.txt")

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Secret plain content") ~= nil, true)
		end)
	end)
end)
