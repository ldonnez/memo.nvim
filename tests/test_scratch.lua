local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("scratch", function()
	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		child.lua([[ M = require('memo.scratch') ]])
	end)

	after_each(function()
		child.stop()
	end)

	local function cwd_key()
		return (vim.fn.getcwd():gsub("[^%w%-]", "%%"))
	end

	describe("is_scratch_file", function()
		local scratch_dir = "/tmp/memo-scratch"

		it("matches a valid scratch file", function()
			local path = scratch_dir .. "/_home_user_project-20260920T012345-a1b2c3.asc"

			MiniTest.expect.equality(require("memo.scratch").is_scratch_file(path), true)
		end)

		it("matches a scratch file written with the other extension", function()
			local path = scratch_dir .. "/_home_user_project-20260920T012345-a1b2c3.gpg"

			MiniTest.expect.equality(require("memo.scratch").is_scratch_file(path), true)
		end)

		it("matches scratch files with percent characters in cwd key", function()
			local path = scratch_dir .. "/%home%user%project-20260920T012345-a1b2c3.asc"

			MiniTest.expect.equality(require("memo.scratch").is_scratch_file(path), true)
		end)

		it("rejects a regular note file", function()
			local path = scratch_dir .. "/important.gpg"

			MiniTest.expect.equality(require("memo.scratch").is_scratch_file(path), false)
		end)

		it("rejects a file with an invalid timestamp", function()
			local path = scratch_dir .. "/_home_user_project-20260920-invalid-a1b2c3.gpg"

			MiniTest.expect.equality(require("memo.scratch").is_scratch_file(path), false)
		end)

		it("rejects a file with an invalid hash", function()
			local path = scratch_dir .. "/_home_user_project-20260920T012345-xyz123.gpg"

			MiniTest.expect.equality(require("memo.scratch").is_scratch_file(path), false)
		end)

		it("rejects a file without a note extension", function()
			local path = scratch_dir .. "/_home_user_project-20260920T012345-a1b2c3.md"

			MiniTest.expect.equality(require("memo.scratch").is_scratch_file(path), false)
		end)

		it("rejects a scratch-looking filename without the hash", function()
			local path = scratch_dir .. "/_home_user_project-20260920T012345.gpg"

			MiniTest.expect.equality(require("memo.scratch").is_scratch_file(path), false)
		end)
	end)

	describe("cwd_key", function()
		it("escapes non-word characters with percent", function()
			child.lua("vim.fn.delete('/tmp/memo-cwd key', 'rf')")
			child.lua("vim.fn.mkdir('/tmp/memo-cwd key', 'p')")
			child.lua("vim.fn.chdir('/tmp/memo-cwd key')")

			local expected = (child.fn.getcwd():gsub("[^%w%-]", "%%"))

			MiniTest.expect.equality(child.lua_get("M.cwd_key()"), expected)
		end)
	end)

	describe("display_scratch / filename_from_display", function()
		local function roundtrip(name)
			return require("memo.scratch").filename_from_display(require("memo.scratch").display_scratch(name))
		end

		it("decodes the cwd key into a readable path", function()
			local name = "%Users%dev%project-20260920T012345-a1b2c3.asc"

			MiniTest.expect.equality(
				require("memo.scratch").display_scratch(name),
				"/Users/dev/project-20260920T012345-a1b2c3.asc"
			)
		end)

		it("round-trips to the real filename", function()
			local names = {
				"%Users%dev%project-20260920T012345-a1b2c3.asc",
				"my-project-20260920T012345-a1b2c3.gpg",
				"%tmp%memo-scratch-20260920T023456-deadbe.gpg",
			}

			for _, name in ipairs(names) do
				MiniTest.expect.equality(roundtrip(name), name)
			end
		end)

		it("passes through names that are not scratch files", function()
			local name = "important.asc"

			MiniTest.expect.equality(require("memo.scratch").display_scratch(name), name)
			MiniTest.expect.equality(require("memo.scratch").filename_from_display(name), name)
		end)
	end)

	describe("files_for_cwd", function()
		before_each(function()
			child.lua([[
        vim.fn.delete('/tmp/memo-cwd-scratch', 'rf')
        vim.fn.delete('/tmp/memo-cwd-workdir', 'rf')
        vim.g.memo_scratch_dir = '/tmp/memo-cwd-scratch'
        require('memo.config').setup()

        vim.fn.mkdir('/tmp/memo-cwd-scratch', 'p')
        vim.fn.mkdir('/tmp/memo-cwd-workdir', 'p')
        vim.fn.chdir('/tmp/memo-cwd-workdir')

        local dir = '/tmp/memo-cwd-scratch'
        local prefix = require('memo.scratch').cwd_key() .. '-'
        vim.fn.writefile({}, dir .. '/' .. prefix .. '20260920T012345-a1b2c3.asc')
        vim.fn.writefile({}, dir .. '/' .. prefix .. '20260920T023456-deadbe.gpg')
      ]])
		end)

		it("lists only scratch files for the current cwd", function()
			local prefix = child.lua_get("require('memo.scratch').cwd_key() .. '-'")
			local files = child.lua_get("M.files_for_cwd()")

			MiniTest.expect.equality(files, {
				"/tmp/memo-cwd-scratch/" .. prefix .. "20260920T012345-a1b2c3.asc",
				"/tmp/memo-cwd-scratch/" .. prefix .. "20260920T023456-deadbe.gpg",
			})
		end)

		it("excludes files of other cwds, invalid names, and non-files", function()
			child.lua([[
        local dir = '/tmp/memo-cwd-scratch'
        local prefix = require('memo.scratch').cwd_key() .. '-'
        vim.fn.writefile({}, dir .. '/zzz-20260920T012345-a1b2c4.asc')
        vim.fn.writefile({}, dir .. '/' .. prefix .. '20260920T012345-xyz123.asc')
        vim.fn.mkdir(dir .. '/' .. prefix .. '20260920T012345-feedcd.asc')
      ]])

			local prefix = child.lua_get("require('memo.scratch').cwd_key() .. '-'")
			local files = child.lua_get("M.files_for_cwd()")

			MiniTest.expect.equality(files, {
				"/tmp/memo-cwd-scratch/" .. prefix .. "20260920T012345-a1b2c3.asc",
				"/tmp/memo-cwd-scratch/" .. prefix .. "20260920T023456-deadbe.gpg",
			})
		end)
	end)

	describe("with gpg key without password", function()
		setup(function()
			helpers.setup_test_env()
			helpers.create_gpg_key("mock@example.com")
		end)

		teardown(function()
			helpers.cleanup_test_env()
		end)

		it("opens a scratch buffer named as a real file in the nvim data dir", function()
			child.lua("M.create()")

			local buffer = child.api.nvim_get_current_buf()
			local name = child.api.nvim_buf_get_name(buffer)

			MiniTest.expect.equality(vim.startswith(name, vim.fn.stdpath("data") .. "/memo-scratch/"), true)
			MiniTest.expect.equality(vim.fn.fnamemodify(name, ":e"), "asc")
		end)

		it("uses vim.g.memo_scratch_dir when set", function()
			child.lua([[
        vim.g.memo_scratch_dir = vim.env.HOME .. '/memo-custom-scratch'

        -- Rerun setup to ensurethe custom global is picked up.
        require("memo.config").setup()
      ]])
			child.lua("M.create()")
			local buffer = child.api.nvim_get_current_buf()
			local name = child.api.nvim_buf_get_name(buffer)

			MiniTest.expect.equality(vim.startswith(name, vim.env.HOME .. "/memo-custom-scratch/"), true)
			MiniTest.expect.equality(vim.fn.fnamemodify(name, ":e"), "asc")
		end)

		it("names the scratch file with the cwd path and a timestamp", function()
			child.lua("M.create()")

			local name = child.api.nvim_buf_get_name(0)

			MiniTest.expect.equality(name:find(cwd_key() .. "-", 1, true) ~= nil, true)
			MiniTest.expect.equality(name:match("T%d%d%d%d%d%d%-%x%x%x%x%x%x%.asc$") ~= nil, true)
		end)

		it("opens in a new tab when the window split is tab", function()
			child.lua("M.create({ window = { split = 'tab' } })")

			local buffer = child.api.nvim_get_current_buf()
			local name = child.api.nvim_buf_get_name(buffer)

			MiniTest.expect.equality(child.fn.tabpagenr("$"), 2)
			MiniTest.expect.equality(vim.startswith(name, vim.fn.stdpath("data") .. "/memo-scratch/"), true)
		end)

		it("opens beside the current window when the window split is vsplit", function()
			local wins_before = #child.api.nvim_list_wins()

			child.lua("M.create({ window = { split = 'vsplit' } })")

			MiniTest.expect.equality(#child.api.nvim_list_wins(), wins_before + 1)
		end)

		it("does not show the [Not edited] flag", function()
			child.lua("M.create()")

			local info = child.cmd_capture("file")
			MiniTest.expect.equality(info:find("[Not edited]", 1, true) == nil, true)
		end)

		it("encrypts scratch content to the nvim data dir on write", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "Secret scratch content", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(child.fn.filereadable(name), 1)
			MiniTest.expect.equality(child.fn.readfile(name)[1], "-----BEGIN PGP MESSAGE-----")

			local result = helpers.decrypt_file(name)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Secret scratch content") ~= nil, true)
		end)

		it("encrypts with a passphrase when the passphrase mode is configured", function()
			child.lua([[ require("memo.gpg").prompt_passphrase = function() return "scratch-sym" end ]])
			child.lua("M.create({ encryption = { mode = 'passphrase' } })")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "secret scratch", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(child.fn.filereadable(name), 1)
			MiniTest.expect.equality(helpers.is_symmetric_file(name), true)

			-- A later write keeps the passphrase, now read back from the file.
			child.type_keys("A", " more", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(helpers.is_symmetric_file(name), true)

			local result = helpers.decrypt_symmetric_file(name, "scratch-sym")
			MiniTest.expect.equality(result.code, 0)
			MiniTest.expect.equality(vim.trim(result.stdout or ""), "secret scratch more")
		end)

		it("takes the mode as a command argument", function()
			child.lua([[ require("memo.gpg").prompt_passphrase = function() return "cmd-sym" end ]])
			child.cmd("MemoScratch passphrase")

			local name = child.api.nvim_buf_get_name(0)
			child.type_keys("i", "cmd scratch", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(helpers.is_symmetric_file(name), true)

			local result = helpers.decrypt_symmetric_file(name, "cmd-sym")
			MiniTest.expect.equality(result.code, 0)
			MiniTest.expect.equality(vim.trim(result.stdout or ""), "cmd scratch")
		end)

		it("opens the split given after the mode", function()
			local wins_before = #child.api.nvim_list_wins()

			child.cmd("MemoScratch passphrase vsplit")

			MiniTest.expect.equality(#child.api.nvim_list_wins(), wins_before + 1)
		end)

		it("encrypts to the key when the command is given key mode", function()
			child.cmd("MemoScratch key")

			local name = child.api.nvim_buf_get_name(0)
			child.type_keys("i", "keyed scratch", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(child.fn.filereadable(name), 1)
			MiniTest.expect.equality(helpers.is_symmetric_file(name), false)
		end)

		it("rejects an unknown split argument", function()
			local wins_before = #child.api.nvim_list_wins()

			child.lua([[pcall(vim.cmd, "MemoScratch bogus")]])

			MiniTest.expect.equality(
				child.cmd_capture("messages"):find([[MemoScratch: expected split, vsplit or tab, got "bogus"]], 1, true)
					~= nil,
				true
			)
			MiniTest.expect.equality(#child.api.nvim_list_wins(), wins_before)
		end)

		it("keeps the buffer open after writing", function()
			child.lua("M.create()")
			local buffer = child.api.nvim_get_current_buf()
			local name = child.api.nvim_buf_get_name(buffer)

			child.type_keys("i", "content", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(child.api.nvim_buf_is_valid(buffer), true)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(buffer), name)
		end)

		it("survives switching away", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "sticky", "<Esc>")
			child.cmd("write")

			child.cmd("enew")

			MiniTest.expect.equality(child.fn.bufexists(name), 1)

			child.cmd("buffer " .. vim.fn.fnameescape(name))
			local buffer = child.api.nvim_get_current_buf()
			local lines = child.api.nvim_buf_get_lines(buffer, 0, -1, false)

			MiniTest.expect.equality(lines, { "sticky" })
		end)

		it("re-encrypts updated content on subsequent writes", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "First line", "<Esc>")
			child.cmd("write")

			child.type_keys("A", "\nSecond line", "<Esc>")
			child.cmd("write")

			local result = helpers.decrypt_file(name)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("First line") ~= nil, true)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Second line") ~= nil, true)
		end)

		it("restores scratch buffers from a session", function()
			child.lua("M.create()")

			child.type_keys("i", "Session restored content", "<Esc>")
			child.cmd("write")
			local name = child.api.nvim_buf_get_name(0)

			child.cmd("mksession! /tmp/memo_session.vim")
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.lua([[ M = require('memo.scratch') ]])

			child.cmd("source /tmp/memo_session.vim")

			MiniTest.expect.equality(child.fn.bufexists(name), 1)

			local buffer = child.fn.bufnr(name)
			child.wait_until(function()
				local l = child.api.nvim_buf_get_lines(buffer, 0, -1, false)
				return #l > 0 and l[1] ~= ""
			end)

			local lines = child.api.nvim_buf_get_lines(buffer, 0, -1, false)
			MiniTest.expect.equality(lines, { "Session restored content" })
		end)

		it("opens unique scratch buffers on repeated calls", function()
			child.lua("M.create()")
			local first = child.api.nvim_buf_get_name(0)

			child.lua("M.create()")
			local second = child.api.nvim_buf_get_name(0)

			MiniTest.expect.equality(first == second, false)
		end)

		it("loads content when opening an existing scratch file directly", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "durable content", "<Esc>")
			child.cmd("write")

			child.cmd("enew")
			child.cmd("edit " .. vim.fn.fnameescape(name))

			child.wait_until(function()
				local l = child.api.nvim_buf_get_lines(0, 0, -1, false)
				return #l > 0 and l[1] ~= ""
			end)

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(lines, { "durable content" })
		end)

		it("deletes the encrypted file when the buffer is deleted", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "content", "<Esc>")
			child.cmd("write")

			child.cmd("bdelete")

			MiniTest.expect.equality(child.fn.buflisted(name), 0)
			MiniTest.expect.equality(child.fn.filereadable(name), 0)
		end)

		it("does not delete unrelated note files in scratch dir", function()
			local scratch_dir = vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "memo-scratch")
			local encrypted = vim.fs.joinpath(scratch_dir, "important.gpg")

			vim.fn.mkdir(scratch_dir, "p")
			helpers.encrypt_file(encrypted, "Do not delete")

			child.cmd("edit " .. encrypted)
			child.cmd("bdelete!")

			MiniTest.expect.equality(child.fn.filereadable(encrypted), 1)
		end)

		it("deletes the encrypted file when the buffer is wiped", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "content", "<Esc>")
			child.cmd("write")

			child.cmd("bwipeout")

			MiniTest.expect.equality(child.fn.bufexists(name), 0)
			MiniTest.expect.equality(child.fn.filereadable(name), 0)
		end)

		it("saves a scratch buffer as a note in the notes dir", function()
			child.cmd("MemoScratch")
			local scratch_buf = child.api.nvim_get_current_buf()
			local scratch = child.api.nvim_buf_get_name(scratch_buf)

			child.type_keys("i", "Scratch to note", "<Esc>")
			child.cmd("write")

			-- stub the interactive prompt with the note name
			child.lua("vim.fn.input = function() return 'ideas' end")
			child.cmd("MemoSaveAsNote")

			local note = vim.env.NOTES_DIR .. "/ideas.asc"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(child.api.nvim_buf_is_valid(scratch_buf), true)
			MiniTest.expect.equality(child.fn.filereadable(scratch), 1)

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Scratch to note") ~= nil, true)
		end)

		it("respects the typed name and appends the note extension", function()
			child.cmd("MemoScratch")
			child.type_keys("i", "content", "<Esc>")
			child.lua("vim.fn.input = function() return 'ideas.md' end")
			child.cmd("MemoSaveAsNote")

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/ideas.md.asc"), 1)
		end)

		it("saves a regular note buffer as a note and keeps it open", function()
			local note = vim.env.NOTES_DIR .. "/scratch-check.md"
			child.cmd("edit " .. vim.fn.fnameescape(note))

			child.lua("vim.fn.input = function() return 'cloned' end")
			child.cmd("MemoSaveAsNote")

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/cloned.asc"), 1)
			local buf = child.api.nvim_get_current_buf()
			MiniTest.expect.equality(child.api.nvim_buf_is_valid(buf), true)
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

		it("encrypts scratch content when gpg key has password", function()
			child.lua("M.create()")
			local name = child.api.nvim_buf_get_name(0)

			child.type_keys("i", "Secret scratch content", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(child.fn.filereadable(name), 1)

			helpers.cache_gpg_password(gpg_key_password)

			local result = helpers.decrypt_file(name)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Secret scratch content") ~= nil, true)
		end)

		it("saves a scratch buffer as a note when gpg key has password", function()
			child.cmd("MemoScratch")
			local scratch_buf = child.api.nvim_get_current_buf()

			child.type_keys("i", "Password note content", "<Esc>")
			helpers.cache_gpg_password(gpg_key_password)

			child.lua("vim.fn.input = function() return 'password-note' end")
			child.cmd("MemoSaveAsNote")

			local note = vim.env.NOTES_DIR .. "/password-note.asc"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(child.api.nvim_buf_is_valid(scratch_buf), true)

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Password note content") ~= nil, true)
		end)
	end)
end)
