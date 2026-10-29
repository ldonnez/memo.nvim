local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("new_note", function()
	local gpg_key_password = "test"

	setup(function()
		helpers.setup_test_env()
		helpers.create_gpg_key("mock-password@example.com", gpg_key_password)
		helpers.cache_gpg_password(gpg_key_password)
	end)

	---The screen size the window defaults are taken from, which is not the size
	---of the current window once earlier tests have left splits open.
	local function screen_size()
		local lines = child.api.nvim_get_option_value("lines", { scope = "global" })
		local columns = child.api.nvim_get_option_value("columns", { scope = "global" })

		return lines, columns
	end

	---Opens a buffer to select from, and returns its path.
	local function open_source()
		local source = vim.env.NOTES_DIR .. "/random.txt"
		child.cmd("edit " .. vim.fn.fnameescape(source))
		child.api.nvim_buf_set_lines(0, 0, -1, false, {
			"alpha beta gamma",
			"delta epsilon",
		})

		return source
	end

	teardown(function()
		helpers.cleanup_test_env()
	end)

	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		child.lua(
			[[
    vim.g.memo_notes_dir = ...

    new_note = require("memo.new_note")
  ]],
			{ vim.env.NOTES_DIR }
		)
	end)

	after_each(function()
		child.stop()
	end)

	describe("create", function()
		it("creates an encrypted note and opens it", function()
			local created = child.lua_get([[ new_note.create({ path = "inbox.md" }) ]])

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/inbox.md.asc"), 1)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/inbox.md"), 0)

			local decrypted = helpers.decrypt_file(vim.env.NOTES_DIR .. "/inbox.md.asc")
			MiniTest.expect.equality(decrypted.code, 0)
		end)

		it("recreates a note after its file is deleted repeatedly", function()
			local path = "recreated.md"
			local file = vim.env.NOTES_DIR .. "/" .. path .. ".asc"

			local function create_and_delete()
				MiniTest.expect.equality(child.lua_get([[ new_note.create({ path = "recreated.md" }) ]]), true)

				-- Exercise the normal edit/autocmd path and wait for decryption.
				child.cmd("edit " .. vim.fn.fnameescape(file))
				child.wait_until(function()
					return child.lua_get("vim.b.decrypting") == false
				end, 10000)

				local bufnr = child.api.nvim_get_current_buf()

				MiniTest.expect.equality(child.api.nvim_buf_get_name(bufnr), file)
				MiniTest.expect.equality(child.api.nvim_buf_is_loaded(bufnr), true)
				MiniTest.expect.equality(child.fn.filereadable(file), 1)

				-- Delete the file but deliberately leave its buffer loaded.
				MiniTest.expect.equality(child.fn.delete(file), 0)
				MiniTest.expect.equality(child.api.nvim_buf_is_valid(bufnr), true)
				MiniTest.expect.equality(child.api.nvim_buf_is_loaded(bufnr), true)
				MiniTest.expect.equality(child.api.nvim_buf_get_name(bufnr), file)
			end

			child.lua("vim.v.errmsg = ''")

			create_and_delete()
			create_and_delete()

			MiniTest.expect.equality(child.lua_get([[ new_note.create({ path = "recreated.md" }) ]]), true)
			local errmsg = child.lua_get("vim.v.errmsg")
			MiniTest.expect.equality(errmsg:find("E211") ~= nil, false)
			MiniTest.expect.equality(child.fn.filereadable(file), 1)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), file)
		end)
		it("sets the filetype from the note name, without the note extension", function()
			child.lua_get([[ new_note.create({ path = "typed.md" }) ]])

			MiniTest.expect.equality(child.bo.filetype, "markdown")
		end)

		it("creates a passphrase note when the symmetric mode is configured", function()
			child.lua([[
      require("memo.gpg").prompt_passphrase = function() return "new-sym" end
    ]])

			local created =
				child.lua_get([[ new_note.create({ path = "sym.md", encryption = { mode = "passphrase" } }) ]])

			MiniTest.expect.equality(created, true)

			local note = vim.env.NOTES_DIR .. "/sym.md.asc"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(helpers.is_symmetric_file(note), true)
		end)

		it("takes the mode as a command argument", function()
			child.lua([[ require("memo.gpg").prompt_passphrase = function() return "cmd-sym" end ]])
			child.cmd([[MemoNewNote passphrase cmd-flag.md]])

			local note = vim.env.NOTES_DIR .. "/cmd-flag.md.asc"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(helpers.is_symmetric_file(note), true)
		end)

		it("encrypts to the key when the command is given no mode", function()
			child.cmd([[MemoNewNote cmd-default.md]])

			local note = vim.env.NOTES_DIR .. "/cmd-default.md.asc"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(helpers.is_symmetric_file(note), false)
		end)

		it("prompts for the passphrase twice when it creates a passphrase note", function()
			child.lua([[
      local prompts = 0
      local gpg = require("memo.gpg")

      gpg.prompt_passphrase = function()
        prompts = prompts + 1
        return "new-sym"
      end

      function _G.memo_passphrase_prompts()
        return prompts
      end
    ]])

			child.lua_get([[ new_note.create({ path = "twice.md", encryption = { mode = "passphrase" } }) ]])

			MiniTest.expect.equality(child.lua_get([[ memo_passphrase_prompts() ]]), 2)
			MiniTest.expect.equality(helpers.is_symmetric_file(vim.env.NOTES_DIR .. "/twice.md.asc"), true)
		end)

		it("does not create the note when the confirmation does not match", function()
			child.lua([[
      local answers = { "first answer", "second answer" }
      local prompts = 0
      local gpg = require("memo.gpg")

      gpg.prompt_passphrase = function()
        prompts = prompts + 1
        return answers[prompts]
      end
    ]])

			child.lua_get([[ new_note.create({ path = "mismatch.md", encryption = { mode = "passphrase" } }) ]])

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/mismatch.md.asc"), 0)
			MiniTest.expect.equality(child.cmd_capture("messages"):find("the passphrases do not match") ~= nil, true)
		end)

		it("keeps the passphrase note encrypted when the buffer is written again", function()
			child.lua([[
      require("memo.gpg").prompt_passphrase = function() return "new-sym" end
    ]])

			child.lua_get([[ new_note.create({ path = "sym-again.md", encryption = { mode = "passphrase" } }) ]])
			child.api.nvim_buf_set_lines(0, 0, -1, false, { "changed body" })
			child.cmd("silent write")

			local note = vim.env.NOTES_DIR .. "/sym-again.md.asc"
			MiniTest.expect.equality(helpers.is_symmetric_file(note), true)

			local result = helpers.decrypt_symmetric_file(note, "new-sym")
			MiniTest.expect.equality(vim.trim(result.stdout or ""), "changed body")
		end)

		it("does not re-encrypt when a new note is written again unchanged", function()
			child.lua_get([[ new_note.create({ path = "unchanged.md" }) ]])

			child.lua([[
      crypto = require("memo.crypto")
      local real = crypto.encrypt_from_stdin
      encrypt_calls = 0
      crypto.encrypt_from_stdin = function(...)
        encrypt_calls = encrypt_calls + 1
        return real(...)
      end
    ]])

			-- Not `silent`: it keeps `vim.notify` out of `:messages`.
			child.cmd("write")

			MiniTest.expect.equality(child.cmd_capture("messages"), "No changes detected")
			MiniTest.expect.equality(child.lua_get("encrypt_calls"), 0)
		end)

		it("does not create the note when the passphrase prompt is dismissed", function()
			child.lua([[
      require("memo.gpg").prompt_passphrase = function() return "" end
    ]])

			child.lua_get([[ new_note.create({ path = "no-sym.md", encryption = { mode = "passphrase" } }) ]])

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/no-sym.md.asc"), 0)
			-- A dismissed prompt is a cancellation, not an error to report.
			MiniTest.expect.equality(child.cmd_capture("messages"), "")
		end)

		it("prompts for the path and uses the default when the prompt is accepted", function()
			child.lua([[ vim.fn.input = function(_, default) return default end ]])

			local created = child.lua_get([[ new_note.create() ]])
			local default_path = vim.env.NOTES_DIR .. "/" .. os.date("%Y-%m-%d.md") .. ".asc"

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(child.fn.filereadable(default_path), 1)
		end)

		it("prompts for the path and uses what is entered", function()
			child.lua([[ vim.fn.input = function() return "prompted.md" end ]])

			local created = child.lua_get([[ new_note.create() ]])

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/prompted.md.asc"), 1)
		end)

		it("aborts when the path prompt is emptied", function()
			child.lua([[ vim.fn.input = function() return "" end ]])

			MiniTest.expect.equality(child.lua_get([[ new_note.create() ]]), false)
			MiniTest.expect.equality(child.cmd_capture("messages"), "MemoNewNote: empty note path")
		end)

		it("opens the note in a configured split", function()
			local win_before = child.api.nvim_get_current_win()
			local wins_before = #child.api.nvim_list_wins()

			local created = child.lua_get([[
		new_note.create({
			path = "split.md",
			template = "## Notes ${cursor} (kept)",
			window = { split = "vsplit", size = 0.5, position = "botright" },
		})
	]])

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(#child.api.nvim_list_wins(), wins_before + 1)

			local win = child.api.nvim_get_current_win()
			MiniTest.expect.equality(win ~= win_before, true)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), vim.env.NOTES_DIR .. "/split.md.asc")

			-- The template cursor lands in the note's window, not the one the
			-- call was made from.
			MiniTest.expect.equality(child.api.nvim_win_get_cursor(win), { 1, 9 })
		end)

		it("defaults a partial window config", function()
			local _, columns = screen_size()

			local created = child.lua_get([[
		new_note.create({ path = "partial.md", window = { split = "vsplit" } })
	]])

			MiniTest.expect.equality(created, true)

			local win = child.api.nvim_get_current_win()
			-- A vsplit, half the screen wide.
			MiniTest.expect.equality(child.api.nvim_win_get_width(win), math.floor(columns / 2))
		end)

		it("treats a size of 1 or less as a share of the screen", function()
			local lines, columns = screen_size()

			local created = child.lua_get([[ new_note.create({ path = "ratio.md", window = { size = 0.25 } }) ]])

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(
				child.api.nvim_win_get_height(child.api.nvim_get_current_win()),
				math.floor(lines / 4)
			)

			local second = child.lua_get(
				[[ new_note.create({ path = "ratio-width.md", window = { split = "vsplit", size = 0.25 } }) ]]
			)

			MiniTest.expect.equality(second, true)
			MiniTest.expect.equality(
				child.api.nvim_win_get_width(child.api.nvim_get_current_win()),
				math.floor(columns / 4)
			)
		end)

		it("defaults the size and position of an empty window config", function()
			local lines = screen_size()
			local width_before = child.api.nvim_win_get_width(0)

			local created = child.lua_get([[ new_note.create({ path = "emptywin.md", window = {} }) ]])

			MiniTest.expect.equality(created, true)

			local win = child.api.nvim_get_current_win()
			-- Half the screen tall, and a horizontal split, so the width is
			-- untouched.
			MiniTest.expect.equality(child.api.nvim_win_get_height(win), math.floor(lines / 2))
			MiniTest.expect.equality(child.api.nvim_win_get_width(win), width_before)
		end)

		it("keeps the current window when no window config is given", function()
			local win_before = child.api.nvim_get_current_win()
			local wins_before = #child.api.nvim_list_wins()

			local created = child.lua_get([[ new_note.create({ path = "samewin.md" }) ]])

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(#child.api.nvim_list_wins(), wins_before)
			MiniTest.expect.equality(child.api.nvim_get_current_win(), win_before)
		end)

		it("takes a selection from the source window into the split", function()
			open_source()

			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })

			local created = child.lua_get([[
		new_note.create({
			path = "split-selection.md",
			template = "## Notes\n- ${cursor}",
			window = { split = "split", size = 0.5, position = "botright" },
		})
	]])

			MiniTest.expect.equality(created, true)

			local result = helpers.decrypt_file(vim.env.NOTES_DIR .. "/split-selection.md.asc")
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "## Notes\n- beta\n")
		end)

		it("creates notes in nested directories", function()
			local created = child.lua_get([[ new_note.create({ path = "journals/2026-01-01.md" }) ]])

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/journals/2026-01-01.md.asc"), 1)
		end)

		it("fills the note with the template", function()
			child.lua_get([[ new_note.create({ path = "templated.md", template = "# ${date:%Y}\n\n${cursor}" }) ]])

			MiniTest.expect.equality(helpers.decrypt_file(vim.env.NOTES_DIR .. "/templated.md.asc").code, 0)

			child.lua([[ vim.cmd("silent edit " .. vim.env.NOTES_DIR .. "/templated.md.asc") ]])
			child.wait_until(function()
				return child.lua_get("vim.b.decrypting") == false
			end, 10000)

			MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "# " .. os.date("%Y"), "", "" })
		end)

		it("places the cursor at the template marker", function()
			child.lua_get([[ new_note.create({ path = "cursor.md", template = "# title\nbody${cursor} here\n" }) ]])

			local cursor = child.api.nvim_win_get_cursor(0)
			MiniTest.expect.equality(cursor[1], 2)
			MiniTest.expect.equality(cursor[2], 4)
		end)

		it("uses the template passed to the call", function()
			child.lua_get([[ new_note.create({ path = "configured.md", template = "from call${cursor} here" }) ]])

			local cursor = child.api.nvim_win_get_cursor(0)
			MiniTest.expect.equality(cursor[1], 1)
			MiniTest.expect.equality(cursor[2], 9)
		end)

		it("prompts before overwriting an existing note and keeps it when declined", function()
			local existing = vim.env.NOTES_DIR .. "/existing.md.gpg"
			helpers.encrypt_file(existing, "old content\n")

			child.lua("vim.fn.confirm = function() return 2 end")

			MiniTest.expect.equality(child.lua_get([[ new_note.create({ path = "existing.md.gpg" }) ]]), false)
			MiniTest.expect.equality(child.cmd_capture("messages"), "MemoNewNote: aborted")

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/existing.md.asc"), 0)

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout:find("old content") ~= nil, true)
		end)

		it("overwrites a note written with the other extension in place", function()
			local existing = vim.env.NOTES_DIR .. "/legacy.md.gpg"
			helpers.encrypt_file(existing, "old content\n")

			child.lua("vim.fn.confirm = function() return 1 end")

			MiniTest.expect.equality(
				child.lua_get([[ new_note.create({ path = "legacy.md.gpg", template = "fresh${cursor} content" }) ]]),
				true
			)
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), existing)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/legacy.md.asc"), 0)

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout, "fresh content\n")
		end)

		it("keeps the .gpg extension when it is configured", function()
			child.lua([[
    	require("memo.config").extension = "gpg"
    	new_note = require("memo.new_note")
  	]])

			local created = child.lua_get([[ new_note.create({ path = "legacy-default.md" }) ]])

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/legacy-default.md.gpg"), 1)
		end)

		it("overwrites an existing note when the user confirms", function()
			local existing = vim.env.NOTES_DIR .. "/existing.md.gpg"
			helpers.encrypt_file(existing, "old content\n")

			child.lua("vim.fn.confirm = function() return 1 end")

			MiniTest.expect.equality(
				child.lua_get([[ new_note.create({ path = "existing.md.gpg", template = "fresh${cursor} content" }) ]]),
				true
			)

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout, "fresh content\n")
		end)

		it("discards the backup once an existing note is overwritten", function()
			local existing = vim.env.NOTES_DIR .. "/overwrite-backup.md.asc"
			helpers.encrypt_file(existing, "old content\n")

			child.lua("vim.fn.confirm = function() return 1 end")

			MiniTest.expect.equality(
				child.lua_get([[ new_note.create({ path = "overwrite-backup.md.asc", template = "fresh${cursor} content" }) ]]),
				true
			)

			local stem = existing:gsub("%.asc$", "")
			MiniTest.expect.equality(vim.fn.glob(stem .. ".memo-backup-*", false, true), {})

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout, "fresh content\n")
		end)

		it("keeps an existing note when a confirmed overwrite selects nothing", function()
			local existing = vim.env.NOTES_DIR .. "/existing-selection.md.asc"
			helpers.encrypt_file(existing, "old content\n")
			local before = vim.fn.readfile(existing, "b")

			open_source()
			child.api.nvim_win_set_cursor(0, { 1, 5 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 5 })

			child.lua("vim.fn.confirm = function() return 1 end")

			MiniTest.expect.equality(
				child.lua_get([[ new_note.create({ path = "existing-selection.md.asc" }) ]]),
				false
			)
			MiniTest.expect.equality(child.cmd_capture("messages"), "MemoNewNote: aborted, selection is empty")

			-- The note is untouched, still decryptable to its old content.
			MiniTest.expect.equality(vim.fn.readfile(existing, "b"), before)

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout:find("old content") ~= nil, true)
		end)

		it("keeps an existing note when a confirmed overwrite passphrase is dismissed", function()
			local existing = vim.env.NOTES_DIR .. "/existing-dismissed.md.asc"
			helpers.encrypt_file(existing, "old content\n")
			local before = vim.fn.readfile(existing, "b")

			child.lua("vim.fn.confirm = function() return 1 end")
			child.lua([[ require("memo.gpg").prompt_passphrase = function() return "" end ]])

			MiniTest.expect.equality(
				child.lua_get(
					[[ new_note.create({ path = "existing-dismissed.md.asc", encryption = { mode = "passphrase" } }) ]]
				),
				false
			)

			-- The replacement buffer is dropped, but the note on disk is the old one.
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), "")
			MiniTest.expect.equality(vim.fn.readfile(existing, "b"), before)

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout:find("old content") ~= nil, true)
		end)

		it("keeps an existing note when a confirmed overwrite fails to encrypt", function()
			local existing = vim.env.NOTES_DIR .. "/existing-failed.md.asc"
			helpers.encrypt_file(existing, "old content\n")
			local before = vim.fn.readfile(existing, "b")

			child.lua("vim.fn.confirm = function() return 1 end")
			child.lua([[
        require("memo.crypto").encrypt_from_stdin = function()
          return nil, "encryption failed"
        end
      ]])

			MiniTest.expect.equality(child.lua_get([[ new_note.create({ path = "existing-failed.md.asc" }) ]]), false)

			-- The failed replacement buffer is dropped, the original stays on disk.
			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), "")
			MiniTest.expect.equality(vim.fn.readfile(existing, "b"), before)
			MiniTest.expect.equality(child.cmd_capture("messages"):find("encryption failed") ~= nil, true)

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(decrypted.stdout:find("old content") ~= nil, true)
		end)

		it("refuses a path outside the notes dir", function()
			MiniTest.expect.equality(child.lua_get([[ new_note.create({ path = "../escape.md" }) ]]), false)
		end)

		it("encrypts an overwrite when the existing buffer hash matches the template", function()
			local existing = vim.env.NOTES_DIR .. "/same-content.md.asc"
			helpers.encrypt_file(existing, "same content\n")

			-- Load the note so its decrypted content and hash are in the buffer.
			child.cmd("edit " .. vim.fn.fnameescape(existing))
			child.wait_until(function()
				return child.lua_get("vim.b.decrypting") == false
			end, 10000)

			child.lua("vim.fn.confirm = function() return 1 end")

			local created = child.lua_get([[
		new_note.create({
			path = "same-content.md.asc",
			template = "same content${cursor}",
		})
	]])

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(child.fn.filereadable(existing), 1)

			local decrypted = helpers.decrypt_file(existing)
			MiniTest.expect.equality(decrypted.code, 0)
			MiniTest.expect.equality(decrypted.stdout, "same content\n")
		end)

		it("prompts for a new passphrase when overwriting a symmetric note", function()
			local existing = vim.env.NOTES_DIR .. "/existing-symmetric.md.asc"
			helpers.encrypt_symmetric_file(existing, "old content\n", "old-pass")

			-- Open the note so its old passphrase is cached in the buffer.
			child.lua([[
		require("memo.gpg").prompt_passphrase = function()
			return "old-pass"
		end
	]])
			child.cmd("edit " .. vim.fn.fnameescape(existing))
			child.wait_until(function()
				return child.lua_get("vim.b.decrypting") == false
			end, 10000)

			-- The replacement must prompt twice for its new passphrase.
			child.lua([[
		local prompts = 0
		local gpg = require("memo.gpg")

		gpg.prompt_passphrase = function()
			prompts = prompts + 1
			return "new-pass"
		end

		_G.memo_passphrase_prompts = function()
			return prompts
		end

		vim.fn.confirm = function()
			return 1
		end
	]])

			local created = child.lua_get([[
		new_note.create({
			path = "existing-symmetric.md.asc",
			template = "fresh content${cursor}",
			encryption = { mode = "passphrase" },
		})
	]])

			MiniTest.expect.equality(created, true)
			MiniTest.expect.equality(child.lua_get("memo_passphrase_prompts()"), 2)

			local decrypted = helpers.decrypt_symmetric_file(existing, "new-pass")
			MiniTest.expect.equality(decrypted.code, 0)
			MiniTest.expect.equality(decrypted.stdout, "fresh content\n")
		end)
	end)

	describe("range selection", function()
		it("seeds the note with whole lines from a characterwise visual range via the user command", function()
			open_source()

			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })

			child.lua("vim.fn.input = function() return 'visual' end")
			child.type_keys(":", "MemoNewNote", "<CR>")

			local note = vim.env.NOTES_DIR .. "/visual.asc"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "alpha beta gamma\n")
		end)

		it("seeds the note with a linewise range via the user command", function()
			open_source()

			child.cmd("2,2normal! V")
			child.lua("vim.fn.input = function() return 'linewise' end")
			child.type_keys(":", "MemoNewNote", "<CR>")

			local note = vim.env.NOTES_DIR .. "/linewise.asc"
			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "delta epsilon\n")
		end)

		it("inserts a range selection at the template cursor position", function()
			open_source()

			child.lua("vim.fn.input = function() return 'ranged' end")

			child.lua_get(
				[[ new_note.create({ path = "ranged.md", range = 2, line1 = 2, line2 = 2, template = "## Notes\n- ${cursor} (kept)" }) ]]
			)

			local result = helpers.decrypt_file(vim.env.NOTES_DIR .. "/ranged.md.asc")
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "## Notes\n- delta epsilon (kept)\n")

			local cursor = child.api.nvim_win_get_cursor(0)
			MiniTest.expect.equality(cursor[1], 2)
			MiniTest.expect.equality(cursor[2], 15)
		end)

		it("uses the selection as the whole note when the template has no marker", function()
			open_source()

			child.lua("vim.fn.input = function() return 'unmarked' end")

			child.lua_get(
				[[ new_note.create({ path = "unmarked.md", range = 2, line1 = 2, line2 = 2, template = "## Notes" }) ]]
			)

			local result = helpers.decrypt_file(vim.env.NOTES_DIR .. "/unmarked.md.asc")
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "delta epsilon\n")
		end)

		it("inserts a visual selection at the template cursor position", function()
			open_source()

			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })
			child.lua_get([[ require("memo").new_note({ path = "fromvisual.md", template = "## Notes\n- ${cursor} (kept)" }) ]])

			local result = helpers.decrypt_file(vim.env.NOTES_DIR .. "/fromvisual.md.asc")
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "## Notes\n- beta (kept)\n")
		end)

		it("inserts a selection into an explicit template", function()
			open_source()

			child.lua("vim.fn.input = function() return 'explicit' end")

			child.lua_get(
				[[ new_note.create({ path = "explicit.md", range = 2, line1 = 2, line2 = 2, template = "call ${cursor} arg" }) ]]
			)

			local result = helpers.decrypt_file(vim.env.NOTES_DIR .. "/explicit.md.asc")
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "call delta epsilon arg\n")
		end)

		it("places the cursor at the end of the selection", function()
			open_source()

			child.cmd("2,2normal! V")
			child.lua("vim.fn.input = function() return 'cursor' end")
			child.type_keys(":", "MemoNewNote", "<CR>")

			local cursor = child.api.nvim_win_get_cursor(0)
			MiniTest.expect.equality(cursor[1], 1)
			MiniTest.expect.equality(cursor[2], 0)
		end)
	end)

	describe("nested note autocmds", function()
		it("decrypts a nested note when opened", function()
			vim.fn.mkdir(vim.env.NOTES_DIR .. "/journals", "p")
			helpers.encrypt_file(vim.env.NOTES_DIR .. "/journals/nested.md.gpg", "nested body\n")

			child.lua([[ vim.cmd("silent edit " .. vim.env.NOTES_DIR .. "/journals/nested.md.gpg") ]])
			child.wait_until(function()
				return child.lua_get("vim.b.decrypting") == false
			end, 10000)

			MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), { "nested body" })
		end)
	end)
end)
