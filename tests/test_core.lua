local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("core", function()
	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		-- Load tested plugin
		child.lua([[ M = require('memo.core') ]])
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

		it("correctly encrypts from stdin", function()
			local encrypted = vim.env.HOME .. "/stdin_test.md.gpg"
			local test_lines = { "Hello World", "Line 2" }

			child.lua(
				[[
        local test_lines, encrypted = ...
        M.encrypt_from_stdin(encrypted, test_lines)
    ]],
				{ test_lines, encrypted }
			)

			local exists = child.fn.filereadable(encrypted)
			local lines = child.fn.readfile(encrypted)
			MiniTest.expect.equality(exists, 1)
			MiniTest.expect.equality(lines[1], "-----BEGIN PGP MESSAGE-----")
		end)

		it("decrypt_to_buffer: decrypts content and ensures cursor stays on top of file", function()
			local path = "/tmp/test.md.gpg"

			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3\n\n")

			child.lua(string.format(
				[[
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        M.decrypt_to_buffer(%q, bufnr, function(obj)
          vim.b.decrypting = false
          return true
        end)
    ]],
				path
			))

			child.wait_until(function()
				return child.b.decrypting == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			local cursor = child.api.nvim_win_get_cursor(0)

			MiniTest.expect.equality(#lines, 4)
			MiniTest.expect.equality(lines, { "Line 1", "Line 2", "Line 3", "" })
			MiniTest.expect.equality(cursor, { 1, 0 })
		end)

		it("decrypt_to_buffer: handles empty file", function()
			local path = "/tmp/empty.md.gpg"
			helpers.encrypt_file(path, "")

			child.lua(string.format(
				[[
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        M.decrypt_to_buffer(%q, bufnr, function(obj)
          vim.b.decrypting = false
          return true
        end)
    ]],
				path
			))

			child.wait_until(function()
				return child.b.decrypting == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(#lines, 1)
			MiniTest.expect.equality(lines[1], "")
		end)

		it("decrypt_to_buffer: handles file without trailing newline", function()
			local path = "/tmp/no_newline.md.gpg"
			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3")

			child.lua(string.format(
				[[
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        M.decrypt_to_buffer(%q, bufnr, function(obj)
          vim.b.decrypting = false
          return true
        end)
    ]],
				path
			))

			child.wait_until(function()
				return child.b.decrypting == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(lines, { "Line 1", "Line 2", "Line 3" })
		end)

		it("decrypt_to_buffer: correctly assembles fragmented data chunks without adding extra new lines", function()
			local path = "/tmp/chunk_test.md.gpg"
			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3\n\n")

			child.lua(string.format(
				[[
        local gpg = require("memo.gpg")

        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        -- We mock gpg call to return chunks
        gpg.exec_with_gpg_auth = function(cmd, opts, on_exit)
          opts.stdout(nil, "Line 1\nLi")
          opts.stdout(nil, "ne 2\nLine 3")
          opts.stdout(nil, "\n\n")

          on_exit({ code = 0 })
          return
        end

        M.decrypt_to_buffer(%q, bufnr, function(obj)
          vim.b.decrypting = false
          return true
        end)
    ]],
				path
			))

			child.wait_until(function()
				return child.b.decrypting == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)

			MiniTest.expect.equality(lines, { "Line 1", "Line 2", "Line 3", "" })
		end)

		it("decrypt_to_stdout: decrypts content", function()
			local path = "/tmp/test.md.gpg"

			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3")

			local result = child.lua(string.format([[ return M.decrypt_to_stdout(%q) ]], path))

			MiniTest.expect.equality(vim.split(result.stdout, "\n"), { "Line 1", "Line 2", "Line 3" })
		end)

		it("save_to_note: saves a plain buffer in the notes dir and keeps it open", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Plain buffer content", "<Esc>")

			child.lua("vim.fn.input = function() return 'plain' end")
			child.cmd("MemoSaveToNote")

			local note = vim.env.NOTES_DIR .. "/plain.gpg"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), source)

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Plain buffer content") ~= nil, true)
		end)

		it("save_to_note: saves a buffer not under the notes dir", function()
			local source = vim.env.HOME .. "/todo.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "Unrelated content", "<Esc>")

			child.lua("vim.fn.input = function() return 'imported' end")
			child.cmd("MemoSaveToNote")

			local note = vim.env.NOTES_DIR .. "/imported.gpg"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), source)
		end)

		it("save_to_note: defaults to the buffer name without .gpg", function()
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
			child.cmd("MemoSaveToNote")

			local saved = vim.env.NOTES_DIR .. "/my-note.md.gpg"
			MiniTest.expect.equality(child.g.input_default, "my-note.md")
			MiniTest.expect.equality(child.fn.filereadable(saved), 1)

			local result = helpers.decrypt_file(saved)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("content") ~= nil, true)
		end)

		it("save_to_note: defaults to the buffer basename for non-gpg buffers", function()
			local path = vim.env.HOME .. "/todo.txt"
			child.cmd("edit " .. vim.fn.fnameescape(path))

			child.lua([[
        vim.g.input_default = nil
        vim.fn.input = function(_prompt, default)
          vim.g.input_default = default
          return default
        end
      ]])
			child.cmd("MemoSaveToNote")

			MiniTest.expect.equality(child.g.input_default, "todo.txt")
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/todo.txt.gpg"), 1)
		end)

		it("save_to_note: creates subdirectories for nested note names", function()
			local source = vim.env.NOTES_DIR .. "/random.txt"
			child.cmd("edit " .. vim.fn.fnameescape(source))
			child.type_keys("i", "nested", "<Esc>")

			child.lua("vim.fn.input = function() return 'projects/idea' end")
			child.cmd("MemoSaveToNote")

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/projects/idea.gpg"), 1)
		end)

		it("save_to_note: aborts when the note name is empty", function()
			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/random.txt"))

			child.lua("vim.fn.input = function() return '' end")
			local result = child.lua([[return { pcall(function() return M.save_to_note() end) }]])

			MiniTest.expect.equality(result[1], true)
			MiniTest.expect.equality(result[2], false)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), vim.env.NOTES_DIR .. "/random.txt")
		end)

		it("save_to_note: refuses to overwrite an existing note", function()
			local existing = vim.env.NOTES_DIR .. "/occupied.gpg"
			helpers.encrypt_file(existing, "old content\n")

			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/random.txt"))
			child.type_keys("i", "new content", "<Esc>")

			child.lua("vim.fn.input = function() return 'occupied' end")
			local result = child.lua([[return { pcall(function() return M.save_to_note() end) }]])

			MiniTest.expect.equality(result[1], true)
			MiniTest.expect.equality(result[2], false)

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout:find("old content") ~= nil, true)
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

		it("decrypt_to_buffer: decrypts content when gpg key has password", function()
			local path = "/tmp/test-password.md.gpg"

			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3")

			child.lua(string.format(
				[[
        local gpg = require("memo.gpg")

        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(0, bufnr)

        gpg.prompt_passphrase = function()
          return %q
        end

        M.decrypt_to_buffer(%q, bufnr, function(obj)
          vim.b.decrypting = false
          return true
        end)
    ]],
				gpg_key_password,
				path
			))

			child.wait_until(function()
				return child.b.decrypting == false
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)

			MiniTest.expect.equality(lines, { "Line 1", "Line 2", "Line 3" })
		end)

		it("decrypt_to_stdout: decrypts content when gpg key has password", function()
			local path = "/tmp/test.md.gpg"

			helpers.encrypt_file(path, "Line 1\nLine 2\nLine 3")

			local result = child.lua(string.format(
				[[
      local gpg = require("memo.gpg")

      gpg.prompt_passphrase = function()
        return %q
      end

      return M.decrypt_to_stdout(%q)
      ]],
				gpg_key_password,
				path
			))

			MiniTest.expect.equality(vim.split(result.stdout, "\n"), { "Line 1", "Line 2", "Line 3" })
		end)

		it("save_to_note: saves a plain buffer when gpg key has password", function()
			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/random.txt"))
			child.type_keys("i", "Secret plain content", "<Esc>")

			helpers.cache_gpg_password(gpg_key_password)
			child.lua("vim.fn.input = function() return 'pw-plain' end")
			child.cmd("MemoSaveToNote")

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
