local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("autocmd", function()
	setup(function()
		helpers.setup_test_env()
		helpers.create_gpg_key("mock@example.com")
	end)

	teardown(function()
		helpers.cleanup_test_env()
		helpers.kill_gpg_agent()
	end)

	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		child.lua([[require('tests.helpers').register_autocmds(...)]], { vim.env.NOTES_DIR })
	end)

	it("disables swap and unsafe files for GPG notes", function()
		local plain = vim.env.NOTES_DIR .. "/secret.md"
		local encrypted = plain .. ".gpg"

		helpers.encrypt_file(encrypted, "Hello World!")

		child.cmd("edit " .. encrypted)

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		local swap = child.bo.swapfile
		local undo = child.bo.undofile
		local encoding = child.bo.fileencoding

		MiniTest.expect.equality(swap, false)
		MiniTest.expect.equality(undo, false)
		MiniTest.expect.equality(encoding, "utf-8")
	end)

	it("triggers decryption when opening a .gpg file", function()
		local plain = vim.env.NOTES_DIR .. "/secret.md"
		local encrypted = plain .. ".gpg"

		helpers.encrypt_file(encrypted, "Hello world!")

		helpers.track_autocmds(child, { "BufReadPre", "BufReadPost" }, encrypted)

		child.cmd("edit " .. encrypted)

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
		local buffer_name = child.api.nvim_buf_get_name(0)

		local buf = child.api.nvim_get_current_buf()
		local filetype = child.api.nvim_get_option_value("filetype", { buf = buf })
		MiniTest.expect.equality(filetype, "markdown")

		MiniTest.expect.equality(lines, { "Hello world!" })
		MiniTest.expect.equality(vim.fn.fnamemodify(buffer_name, ":t"), "secret.md.gpg")
		MiniTest.expect.equality(helpers.autocmd_fired(child, "BufReadPre"), true)
		MiniTest.expect.equality(helpers.autocmd_fired(child, "BufReadPost"), true)
	end)

	it("ensures not writing when decrypting", function()
		local plain = vim.env.NOTES_DIR .. "/secret.md"
		local encrypted = plain .. ".gpg"

		helpers.encrypt_file(encrypted, "Hello world!")

		child.lua([[
      local core = require('memo.core')

      core.decrypt_to_buffer = function(path, bufnr, on_exit)
        return vim.defer_fn(function()
          vim.bo[bufnr].modifiable = true
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {"Hello world!"})
          vim.bo[bufnr].modified = false
          vim.bo[bufnr].modifiable = false

          on_exit({ code = 0 })
        end, 1000)
      end
    ]])

		child.cmd("edit " .. encrypted)

		MiniTest.expect.equality(child.b.decrypting, true)
		MiniTest.expect.equality(child.b.hash ~= vim.NIL, false)

		child.cmd("write")

		MiniTest.expect.equality(child.b.decrypting, true)
		MiniTest.expect.equality(child.b.hash ~= vim.NIL, false)

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		MiniTest.expect.equality(child.b.decrypting, false)
		MiniTest.expect.equality(child.b.hash ~= vim.NIL, true)

		local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)

		MiniTest.expect.equality(lines, { "Hello world!" })
	end)

	it("does not trigger decryption when existing .md file is opened; reencrypts it after saving", function()
		local plain = vim.env.NOTES_DIR .. "/existing.md"
		helpers.write_file(plain, "Hello world")

		child.cmd("edit " .. plain)

		local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
		local buffer_name = child.api.nvim_buf_get_name(0)

		MiniTest.expect.equality(lines, { "Hello world" })
		MiniTest.expect.equality(buffer_name, plain)

		child.cmd("write")

		local new_buffer_name_after_write = child.api.nvim_buf_get_name(0)

		local decrypted_result = helpers.decrypt_file(plain .. ".gpg")

		MiniTest.expect.equality(decrypted_result.stdout, "Hello world\n")
		MiniTest.expect.equality(new_buffer_name_after_write, plain .. ".gpg")
	end)

	it("automatically encrypts a new .md file saved in notes dir", function()
		local plain = vim.env.NOTES_DIR .. "/new_note.md"
		local encrypted = plain .. ".gpg"

		vim.system({ "touch", plain }):wait()

		helpers.track_autocmds(child, { "BufNewFile", "BufReadPre", "BufReadPost" }, plain)

		child.cmd("edit " .. plain)
		child.api.nvim_buf_set_lines(0, 0, -1, false, { "My new private note" })
		child.cmd("write")

		local new_buffer_name = child.api.nvim_buf_get_name(0)
		local plaintext_file_exists = vim.fn.filereadable(plain) == 1
		local gpg_file_exists = vim.fn.filereadable(encrypted) == 1

		MiniTest.expect.equality(new_buffer_name, plain .. ".gpg")
		MiniTest.expect.equality(plaintext_file_exists, false)
		MiniTest.expect.equality(gpg_file_exists, true)
		MiniTest.expect.equality(helpers.autocmd_fired(child, "BufNewFile"), true)
		MiniTest.expect.equality(helpers.autocmd_fired(child, "BufReadPre"), false)
		MiniTest.expect.equality(helpers.autocmd_fired(child, "BufReadPost"), false)
	end)

	it("automatically encrypts a new file without extension saved in notes dir", function()
		local plain = vim.env.NOTES_DIR .. "/new_note"
		local encrypted = plain .. ".gpg"

		vim.system({ "touch", plain }):wait()

		child.cmd("edit " .. plain)
		child.api.nvim_buf_set_lines(0, 0, -1, false, { "My new private note" })
		child.cmd("write")

		local new_buffer_name = child.api.nvim_buf_get_name(0)
		local plaintext_file_exists = vim.fn.filereadable(plain) == 1
		local gpg_file_exists = vim.fn.filereadable(encrypted) == 1

		MiniTest.expect.equality(new_buffer_name, plain .. ".gpg")
		MiniTest.expect.equality(plaintext_file_exists, false)
		MiniTest.expect.equality(gpg_file_exists, true)
	end)

	it("automatically encrypts a new .md.gpg file saved in notes dir", function()
		local plain = vim.env.NOTES_DIR .. "/new_note.md"
		local encrypted = plain .. ".gpg"

		vim.system({ "touch", encrypted }):wait()

		child.cmd("edit " .. encrypted)

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		child.api.nvim_buf_set_lines(0, 0, -1, false, { "My new private note" })
		child.cmd("write")

		local new_buffer_name = child.api.nvim_buf_get_name(0)
		local plaintext_file_exists = vim.fn.filereadable(plain) == 1
		local gpg_file_exists = vim.fn.filereadable(encrypted) == 1

		MiniTest.expect.equality(new_buffer_name, plain .. ".gpg")
		MiniTest.expect.equality(plaintext_file_exists, false)
		MiniTest.expect.equality(gpg_file_exists, true)
	end)

	it("does not re-encrypt (no-op) if content hasn't changed", function()
		local encrypted = vim.env.NOTES_DIR .. "/unchanged.md.gpg"

		helpers.encrypt_file(encrypted, "Hello world!")

		helpers.track_autocmds(child, { "BufWritePre", "BufWritePost" }, encrypted)

		child.cmd("edit " .. encrypted)

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		child.cmd("write")

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		local messages = child.cmd_capture("messages")
		MiniTest.expect.equality(messages, "No changes detected")

		child.cmd("messages clear")
		child.api.nvim_buf_set_lines(0, 0, -1, false, { "My new private note" })
		child.cmd("write")

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		local messages2 = child.cmd_capture("messages")
		MiniTest.expect.equality(messages2, "")

		child.cmd("write")

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		local messages3 = child.cmd_capture("messages")
		MiniTest.expect.equality(messages3, "No changes detected")
		MiniTest.expect.equality(helpers.autocmd_fired(child, "BufWritePre"), true)
		MiniTest.expect.equality(helpers.autocmd_fired(child, "BufWritePost"), true)
	end)

	it("wipes buffer if decryption fails", function()
		local test_file = vim.env.NOTES_DIR .. "/broken.md.gpg"
		vim.fn.writefile({ "-----BEGIN PGP MESSAGE-----", "not really encrypted" }, test_file)

		local target_bufnr = child.lua(
			[[
        local path = ...
        pcall(vim.cmd, "edit " .. vim.fn.fnameescape(path))

        return vim.api.nvim_get_current_buf()
    ]],
			{ test_file }
		)

		child.wait_until(function()
			return not child.api.nvim_buf_is_valid(target_bufnr)
		end)
		local is_valid = child.api.nvim_buf_is_valid(target_bufnr)
		MiniTest.expect.equality(is_valid, false)
	end)

	it("does not trigger logic for files outside notes_dir", function()
		local outside_dir = vim.env.HOME .. "/outside"
		vim.fn.mkdir(outside_dir, "p")
		local outside_file = outside_dir .. "/normal.md"

		child.cmd("edit " .. outside_file)
		child.api.nvim_buf_set_lines(0, 0, -1, false, { "Normal stuff" })
		child.cmd("write")

		local result = child.lua_get([[
            {
                swap = vim.opt_local.swapfile:get(),
                is_gpg = vim.api.nvim_buf_get_name(0):match("%.gpg$") ~= nil
            }
        ]])

		MiniTest.expect.equality(result.swap, true)
		MiniTest.expect.equality(result.is_gpg, false)
	end)

	it("triggers decryption when opening a scratch .gpg file", function()
		local scratch_dir = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "memo-scratch")
		local encrypted = vim.fs.joinpath(scratch_dir, "test.gpg")

		vim.fn.mkdir(scratch_dir, "p")
		helpers.encrypt_file(encrypted, "Scratch secret!")

		child.cmd("edit " .. encrypted)

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
		local buffer_name = child.api.nvim_buf_get_name(0)

		MiniTest.expect.equality(lines, { "Scratch secret!" })
		MiniTest.expect.equality(buffer_name, encrypted)
	end)

	it("encrypts changes when writing a scratch .gpg file", function()
		local scratch_dir = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "memo-scratch")
		local encrypted = vim.fs.joinpath(scratch_dir, "test.gpg")

		vim.fn.mkdir(scratch_dir, "p")
		helpers.encrypt_file(encrypted, "Original")

		child.cmd("edit " .. encrypted)

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		child.api.nvim_buf_set_lines(0, 0, -1, false, { "Updated scratch" })
		child.cmd("write")

		local decrypted = helpers.decrypt_file(encrypted)

		MiniTest.expect.equality(decrypted.stdout, "Updated scratch\n")
		MiniTest.expect.equality(child.api.nvim_buf_get_name(0), encrypted)
	end)

	it("deletes a scratch .gpg file when its buffer is deleted", function()
		local scratch_dir = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "memo-scratch")
		local encrypted = vim.fs.joinpath(scratch_dir, "_home_user_project-20260920T012345-a1b2c3.gpg")

		vim.fn.mkdir(scratch_dir, "p")
		helpers.encrypt_file(encrypted, "Temporary scratch")

		child.cmd("edit " .. encrypted)

		child.wait_until(function()
			return child.b.decrypting == false
		end)

		MiniTest.expect.equality(vim.fn.filereadable(encrypted), 1)

		child.cmd("bdelete!")

		MiniTest.expect.equality(vim.fn.filereadable(encrypted), 0)
	end)

	it("does not delete a regular gpg file outside notes and scratch directories", function()
		local outside_dir = vim.fs.joinpath(vim.env.HOME, "outside")
		local encrypted = vim.fs.joinpath(outside_dir, "important.gpg")

		vim.fn.mkdir(outside_dir, "p")
		helpers.encrypt_file(encrypted, "Do not delete")

		child.cmd("edit " .. encrypted)

		MiniTest.expect.equality(vim.fn.filereadable(encrypted), 1)

		child.cmd("bdelete!")

		MiniTest.expect.equality(vim.fn.filereadable(encrypted), 1)
	end)

	it("does not decrypt .gitignore files in the notes dir", function()
		local plain = vim.env.NOTES_DIR .. "/.gitignore"
		helpers.write_file(plain, "*.gpg\n")

		child.cmd("edit " .. plain)

		MiniTest.expect.equality(child.api.nvim_buf_get_name(0), plain)
		MiniTest.expect.equality(child.b.decrypting, vim.NIL)
		MiniTest.expect.equality(vim.fn.filereadable(plain .. ".gpg"), 0)
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "*.gpg" })
	end)

	it("does not decrypt files under a .git directory", function()
		local config = vim.env.NOTES_DIR .. "/.git/config"
		vim.fn.mkdir(vim.fn.fnamemodify(config, ":h"), "p")
		helpers.write_file(config, "[core]\n")

		child.cmd("edit " .. config)

		MiniTest.expect.equality(child.api.nvim_buf_get_name(0), config)
		MiniTest.expect.equality(child.b.decrypting, vim.NIL)
		MiniTest.expect.equality(vim.fn.filereadable(config .. ".gpg"), 0)
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "[core]" })
	end)

	it("honors custom ignore patterns set via vim.g.memo_ignore_patterns", function()
		child.lua([[
      vim.g.memo_ignore_patterns = { "**/pending/**" }

      -- Rerun setup to ensure the custom global is picked up.
      require("memo.config").setup()
    ]])

		local plain = vim.env.NOTES_DIR .. "/pending/draft.md"
		vim.fn.mkdir(vim.fn.fnamemodify(plain, ":h"), "p")
		helpers.write_file(plain, "draft")

		child.cmd("edit " .. plain)

		MiniTest.expect.equality(child.api.nvim_buf_get_name(0), plain)
		MiniTest.expect.equality(child.b.decrypting, vim.NIL)
		MiniTest.expect.equality(vim.fn.filereadable(plain .. ".gpg"), 0)
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "draft" })
	end)

	it("does not write encrypted .gpg for ignored files", function()
		local plain = vim.env.NOTES_DIR .. "/.gitignore"
		helpers.write_file(plain, "*.gpg\n")

		child.cmd("edit " .. plain)
		child.api.nvim_buf_set_lines(0, 0, -1, false, { "*.md" })
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_name(0), plain)
		MiniTest.expect.equality(vim.fn.filereadable(plain .. ".gpg"), 0)
		MiniTest.expect.equality(vim.fn.readfile(plain), { "*.md" })
	end)

	it("keeps _scratch-priority_ files ignored even when args.file is a bare relative basename", function()
		local plain = vim.env.NOTES_DIR .. "/.gitignore"
		helpers.write_file(plain, "*.gpg\n")

		-- Reproduce `args.file == ".gitignore"` (no directory prefix), which is
		-- how the name arrives when editing the file from inside the notes dir.
		child.cmd("cd " .. vim.env.NOTES_DIR)
		child.cmd("edit .gitignore")

		MiniTest.expect.equality(child.api.nvim_buf_get_name(0), plain)
		MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "*.gpg" })

		child.api.nvim_buf_set_lines(0, 0, -1, false, { "*.md" })
		child.cmd("write")

		MiniTest.expect.equality(child.api.nvim_buf_get_name(0), plain)
		MiniTest.expect.equality(vim.fn.filereadable(plain .. ".gpg"), 0)
		MiniTest.expect.equality(vim.fn.readfile(plain), { "*.md" })
	end)

	describe("default ignored files", function()
		local ignored_files = {
			{ ".gitignore", "*.gpg\n" },
			{ ".gitattributes", "*.md text\n" },
			{ ".gitmodules", "[submodule]\n" },
			{ ".git/config", "[core]\n" },
			{ ".githooks/test.sh", "echo 'test'" },
			{ ".ignore", "*.test\n" },
		}

		for _, file in ipairs(ignored_files) do
			it("does not decrypt " .. file[1], function()
				local path = vim.env.NOTES_DIR .. "/" .. file[1]

				vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
				helpers.write_file(path, file[2])

				helpers.track_autocmds(child, { "BufReadPre", "BufReadPost" }, path)
				child.cmd("edit " .. path)

				MiniTest.expect.equality(child.api.nvim_buf_get_name(0), path)
				MiniTest.expect.equality(child.b.decrypting, vim.NIL)
				MiniTest.expect.equality(vim.fn.filereadable(path .. ".gpg"), 0)
				MiniTest.expect.equality(
					child.api.nvim_buf_get_lines(0, 0, -1, false),
					vim.split(file[2], "\n", { trimempty = true })
				)
				MiniTest.expect.equality(helpers.autocmd_fired(child, "BufReadPre"), true)
				MiniTest.expect.equality(helpers.autocmd_fired(child, "BufReadPost"), true)
			end)

			it("does not encrypt " .. file[1], function()
				local path = vim.env.NOTES_DIR .. "/" .. file[1]

				vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
				helpers.write_file(path, file[2])

				helpers.track_autocmds(child, { "BufWritePre", "BufWritePost" }, path)

				child.cmd("edit " .. path)
				child.api.nvim_buf_set_lines(0, 0, -1, false, { "updated content" })
				child.cmd("write")

				MiniTest.expect.equality(child.api.nvim_buf_get_name(0), path)
				MiniTest.expect.equality(vim.fn.filereadable(path .. ".gpg"), 0)
				MiniTest.expect.equality(vim.fn.readfile(path), { "updated content" })
				MiniTest.expect.equality(helpers.autocmd_fired(child, "BufWritePre"), true)
				MiniTest.expect.equality(helpers.autocmd_fired(child, "BufWritePost"), true)
			end)
		end
	end)

	describe("overlapping notes and scratch directories", function()
		before_each(function()
			child.restart({
				"-u",
				"scripts/minimal_init.lua",
			})
		end)

		it("registers only one pattern when scratch dir equals notes dir", function()
			child.lua([[
				vim.g.memo_scratch_dir = vim.env.NOTES_DIR

				-- Rerun setup so the custom scratch directory is picked up.
				require("memo.config").setup()
	      require("plugin.memo")
			]])

			local read_autocmds = child.api.nvim_get_autocmds({
				group = "MemoGpg",
				event = "BufReadCmd",
			})
			local write_autocmds = child.api.nvim_get_autocmds({
				group = "MemoGpg",
				event = "BufWriteCmd",
			})

			MiniTest.expect.equality(#read_autocmds, 1)
			MiniTest.expect.equality(#write_autocmds, 1)
			MiniTest.expect.equality(read_autocmds[1].pattern, vim.env.NOTES_DIR .. "/*")
			MiniTest.expect.equality(write_autocmds[1].pattern, vim.env.NOTES_DIR .. "/*")
		end)

		it("registers only one pattern when scratch dir is inside notes dir", function()
			child.lua([[
				vim.g.memo_scratch_dir = vim.env.NOTES_DIR .. "/scratch"

				-- Rerun setup so the custom scratch directory is picked up.
				require("memo.config").setup()
	      require("plugin.memo")
			]])

			local read_autocmds = child.api.nvim_get_autocmds({
				group = "MemoGpg",
				event = "BufReadCmd",
			})
			local write_autocmds = child.api.nvim_get_autocmds({
				group = "MemoGpg",
				event = "BufWriteCmd",
			})

			MiniTest.expect.equality(#read_autocmds, 1)
			MiniTest.expect.equality(#write_autocmds, 1)
			MiniTest.expect.equality(read_autocmds[1].pattern, vim.env.NOTES_DIR .. "/*")
			MiniTest.expect.equality(write_autocmds[1].pattern, vim.env.NOTES_DIR .. "/*")
		end)

		it("registers separate patterns when scratch dir is outside notes dir", function()
			child.lua([[
				vim.g.memo_scratch_dir = vim.env.HOME .. "/memo-scratch"

				-- Rerun setup so the custom scratch directory is picked up.
				require("memo.config").setup()
	      require("plugin.memo")
			]])

			local read_autocmds = child.api.nvim_get_autocmds({
				group = "MemoGpg",
				event = "BufReadCmd",
			})
			local write_autocmds = child.api.nvim_get_autocmds({
				group = "MemoGpg",
				event = "BufWriteCmd",
			})

			MiniTest.expect.equality(#read_autocmds, 2)
			MiniTest.expect.equality(#write_autocmds, 2)
			MiniTest.expect.equality(read_autocmds[1].pattern, vim.env.NOTES_DIR .. "/*")
			MiniTest.expect.equality(write_autocmds[1].pattern, vim.env.NOTES_DIR .. "/*")
			MiniTest.expect.equality(read_autocmds[2].pattern, vim.env.HOME .. "/memo-scratch" .. "/*")
			MiniTest.expect.equality(write_autocmds[2].pattern, vim.env.HOME .. "/memo-scratch" .. "/*")
		end)
	end)
end)
