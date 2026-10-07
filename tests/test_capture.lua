local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("capture", function()
	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		-- Load tested plugin
		child.lua(
			[[
    crypto = require("memo.crypto")

    vim.g.memo_notes_dir = ...

    M = require('memo.capture')
    ]],
			{ vim.env.NOTES_DIR }
		)
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

		it("uses the default capture file when none is given", function()
			child.lua([[ M.create({}) ]])

			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), "capture://inbox.md.asc")
		end)

		it("refuses an empty capture file", function()
			local before = child.api.nvim_list_bufs()

			child.lua([[ M.create({ capture_file = "" }) ]])

			MiniTest.expect.equality(child.api.nvim_list_bufs(), before)
			MiniTest.expect.equality(
				child.cmd_capture("messages"),
				"MemoCapture: a capture file is required, or set g:memo_default_capture_file"
			)
		end)

		it("appends to an inbox written with the other extension", function()
			helpers.encrypt_file(vim.env.NOTES_DIR .. "/inbox.md.gpg", "Inbox\n")

			child.lua([[
				vim.g.memo_default_capture_file = "inbox.md.gpg"
				require("memo.config").setup()
				M.create({})
			]])
			child.lua([[ vim.api.nvim_buf_set_lines(0, 0, -1, false, { "captured" }) ]])
			child.cmd("write")

			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/inbox.md.asc"), 0)

			local result = helpers.decrypt_file(vim.env.NOTES_DIR .. "/inbox.md.gpg")
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout, "captured\nInbox\n")
		end)

		it("uses vim.g.memo_default_capture_file when no capture file is given", function()
			helpers.encrypt_file(vim.env.NOTES_DIR .. "/quick.gpg", "Quick\n")

			child.lua([[
				vim.g.memo_default_capture_file = "quick.gpg"
				require("memo.config").setup()
				M.create({})
			]])

			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), "capture://quick.gpg")
		end)

		it("prefers the given capture file over vim.g.memo_default_capture_file", function()
			helpers.encrypt_file(vim.env.NOTES_DIR .. "/inbox.md.gpg", "Inbox\n")
			helpers.encrypt_file(vim.env.NOTES_DIR .. "/given.gpg", "Given\n")

			child.lua([[
				vim.g.memo_default_capture_file = "quick.gpg"
				require("memo.config").setup()
				M.create({ capture_file = "given.md" })
			]])

			MiniTest.expect.equality(child.api.nvim_buf_get_name(0), "capture://given.md")
		end)

		it("captures window contains correct buffer options", function()
			local capture_file = "capture.md"
			local capture_file_path = vim.env.NOTES_DIR .. "/" .. capture_file
			local encrypted = capture_file_path .. ".gpg"

			helpers.encrypt_file(encrypted, "CAPTURE\n")

			helpers.track_autocmds(child, { "BufReadPre", "BufReadPost" })

			child.lua([[ M.create({ capture_file = ... }) ]], { capture_file .. ".gpg" })

			local swap = child.bo.swapfile
			local bufhidden = child.bo.bufhidden
			local encoding = child.bo.fileencoding

			MiniTest.expect.equality(swap, false)
			MiniTest.expect.equality(bufhidden, "wipe")
			MiniTest.expect.equality(encoding, "utf-8")
			MiniTest.expect.equality(helpers.autocmd_fired(child, "BufReadPre"), true)
			MiniTest.expect.equality(helpers.autocmd_fired(child, "BufReadPost"), true)
		end)

		it("captures text when capture file exists and keeps new lines in place", function()
			local capture_file = "capture.md"
			local capture_file_path = vim.env.NOTES_DIR .. "/" .. capture_file
			local encrypted = capture_file_path .. ".gpg"

			helpers.encrypt_file(encrypted, "CAPTURE\n")

			child.lua([[ M.create({ capture_file = ... }) ]], { capture_file .. ".gpg" })

			helpers.track_autocmds(child, { "BufWritePre", "BufWritePost" })

			child.type_keys("i", "Integration Test Content", "<Esc>")

			local buf = child.api.nvim_get_current_buf()
			local filetype = child.api.nvim_get_option_value("filetype", { buf = buf })
			MiniTest.expect.equality(filetype, "markdown")

			child.cmd("write")

			local exists = child.fn.filereadable(encrypted)
			MiniTest.expect.equality(exists, 1)

			local head = child.fn.readfile(encrypted)[1]
			MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

			local result = helpers.decrypt_file(encrypted)

			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			local lines = vim.split(result.stdout, "\n", { plain = true })
			MiniTest.expect.equality(lines, { "Integration Test Content", "CAPTURE", "" })
			MiniTest.expect.equality(helpers.autocmd_fired(child, "BufWritePre"), true)
			MiniTest.expect.equality(helpers.autocmd_fired(child, "BufWritePost"), true)
		end)

		it("aborts capture when capture window only contains header", function()
			local capture_file = "capture.md"
			local capture_file_path = vim.env.NOTES_DIR .. "/" .. capture_file
			local encrypted = capture_file_path .. ".gpg"

			helpers.encrypt_file(encrypted, "CAPTURE")

			child.lua([[ M.create({ capture_file = ... }) ]], { capture_file .. ".gpg" })

			child.cmd("write")
			local messages = child.cmd_capture("messages")
			MiniTest.expect.equality(messages, "Capture aborted: empty content")
		end)

		it("aborts capture when capture window has no content", function()
			local capture_file = "capture.md"

			child.lua([[ M.create({ capture_file = ... }) ]], { capture_file .. ".gpg" })

			-- empty the buffer
			local buf = child.api.nvim_get_current_buf()
			child.api.nvim_buf_set_lines(buf, 0, -1, false, {})

			child.cmd("write")
			local messages = child.cmd_capture("messages")
			MiniTest.expect.equality(messages, "Capture aborted: empty content")
		end)

		it("captures text when capture file and target header does not exists", function()
			local capture_file = "capture.md.gpg"
			local capture_file_path = vim.env.NOTES_DIR .. "/capture.md.gpg"

			child.lua(
				[[
	       M.create({ capture_file = ..., target_header = "inbox" })
	   ]],
				{ capture_file }
			)

			child.type_keys("i", "Integration Test Content", "<Esc>")

			child.cmd("write")

			local exists = child.fn.filereadable(capture_file_path)
			MiniTest.expect.equality(exists, 1)

			local head = child.fn.readfile(capture_file_path)[1]
			MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

			local result = helpers.decrypt_file(capture_file_path)

			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Integration Test Content") ~= nil, true)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("inbox") ~= nil, true)
		end)

		it("inserts the capture below an existing target header", function()
			local capture_file = "capture.md.gpg"
			local encrypted = vim.env.NOTES_DIR .. "/" .. capture_file

			helpers.encrypt_file(encrypted, "# Inbox\n\nPrevious Note\n")

			child.lua(
				[[ M.create({ capture_file = ..., target_header = "# Inbox", header_padding = 0 }) ]],
				{ capture_file }
			)

			child.type_keys("i", "New Content", "<Esc>")
			child.cmd("write")

			local result = helpers.decrypt_file(encrypted)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			local lines = vim.split(result.stdout, "\n", { plain = true })
			MiniTest.expect.equality(lines, { "# Inbox", "New Content", "Previous Note", "" })
		end)

		it("inserts the capture below the first of two target headers", function()
			local capture_file = "capture.md.gpg"
			local encrypted = vim.env.NOTES_DIR .. "/" .. capture_file

			helpers.encrypt_file(encrypted, "# Inbox\n\nSecond Note\n# Inbox\n\nFirst Note\n")

			child.lua([[ M.create({ capture_file = ..., target_header = "# Inbox" }) ]], { capture_file })

			child.type_keys("i", "New Content", "<Esc>")
			child.cmd("write")

			local result = helpers.decrypt_file(encrypted)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			local lines = vim.split(result.stdout, "\n", { plain = true })
			MiniTest.expect.equality(
				lines,
				{ "# Inbox", "New Content", "Second Note", "# Inbox", "", "First Note", "" }
			)
		end)

		it("ignores partial matches for the target header", function()
			local capture_file = "capture.md.gpg"
			local encrypted = vim.env.NOTES_DIR .. "/" .. capture_file

			helpers.encrypt_file(encrypted, "# Inbox is here\n\nPrevious Note\n")

			child.lua([[ M.create({ capture_file = ..., target_header = "# Inbox" }) ]], { capture_file })

			child.type_keys("i", "New Content", "<Esc>")
			child.cmd("write")

			local result = helpers.decrypt_file(encrypted)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			local lines = vim.split(result.stdout, "\n", { plain = true })
			MiniTest.expect.equality(lines, { "# Inbox", "New Content", "# Inbox is here", "", "Previous Note", "" })
		end)

		it("prepends the target header when the capture file does not contain it", function()
			local capture_file = "capture.md.gpg"
			local encrypted = vim.env.NOTES_DIR .. "/" .. capture_file

			helpers.encrypt_file(encrypted, "# test\nexisting content\n")

			child.lua([[ M.create({ capture_file = ..., target_header = "# Inbox" }) ]], { capture_file })

			child.type_keys("i", "New Content", "<Esc>")
			child.cmd("write")

			local result = helpers.decrypt_file(encrypted)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			local lines = vim.split(result.stdout, "\n", { plain = true })
			MiniTest.expect.equality(lines, { "# Inbox", "New Content", "# test", "existing content", "" })
		end)

		it("keeps header_padding blank lines between the header and the capture", function()
			local capture_file = "capture.md.gpg"
			local encrypted = vim.env.NOTES_DIR .. "/" .. capture_file

			helpers.encrypt_file(encrypted, "# Inbox\n\nPrevious Note\n")

			child.lua(
				[[ M.create({ capture_file = ..., target_header = "# Inbox", header_padding = 2 }) ]],
				{ capture_file }
			)

			child.type_keys("i", "New Content", "<Esc>")
			child.cmd("write")

			local result = helpers.decrypt_file(encrypted)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			local lines = vim.split(result.stdout, "\n", { plain = true })
			MiniTest.expect.equality(lines, { "# Inbox", "", "", "New Content", "Previous Note", "" })
		end)

		it("ensures relative directories from capture_file are created", function()
			local capture_file = "journals/capture.md.gpg"
			local capture_file_path = vim.env.NOTES_DIR .. "/journals/capture.md.gpg"

			child.lua(
				[[
	       M.create({ capture_file = ..., target_header = "inbox" })
	   ]],
				{ capture_file }
			)

			child.type_keys("i", "Integration Test Content", "<Esc>")

			child.cmd("write")

			local exists = child.fn.filereadable(capture_file_path)
			MiniTest.expect.equality(exists, 1)

			local head = child.fn.readfile(capture_file_path)[1]
			MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

			local result = helpers.decrypt_file(capture_file_path)

			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Integration Test Content") ~= nil, true)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("inbox") ~= nil, true)
		end)

		it("pre-fills the capture window with the selection at the template cursor", function()
			local capture_file = "visual-capture.md.gpg"

			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/source.txt"))
			child.api.nvim_buf_set_lines(0, 0, -1, false, {
				"alpha beta gamma",
				"delta epsilon",
			})

			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })

			child.lua([[ M.create({ capture_file = ..., template = "## Notes\n- |" }) ]], { capture_file })

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(lines, { "## Notes", "- beta" })
		end)

		it("captures a selection under the template header", function()
			local capture_file = "visual-template.md.gpg"
			local encrypted = vim.env.NOTES_DIR .. "/" .. capture_file

			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/source.txt"))
			child.api.nvim_buf_set_lines(0, 0, -1, false, {
				"alpha beta gamma",
				"delta epsilon",
			})

			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })

			child.lua([[ M.create({ capture_file = ..., template = "## Notes\n- |" }) ]], { capture_file })

			child.cmd("write")

			local result = helpers.decrypt_file(encrypted)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			local lines = vim.split(result.stdout, "\n", { plain = true })
			MiniTest.expect.equality(lines, { "## Notes", "- beta", "" })
		end)

		it("pre-fills the capture window with the characterwise visual selection", function()
			local capture_file = "visual-capture.md.gpg"

			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/source.txt"))
			child.api.nvim_buf_set_lines(0, 0, -1, false, {
				"alpha beta gamma",
				"delta epsilon",
			})

			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })

			child.lua([[ M.create({ capture_file = ... }) ]], { capture_file })

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(lines, { "beta" })
		end)

		it("pre-fills the capture window with the linewise visual selection", function()
			local capture_file = "visual-line-capture.md.gpg"

			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/source.txt"))
			child.api.nvim_buf_set_lines(0, 0, -1, false, {
				"alpha",
				"beta",
				"gamma",
				"delta",
			})

			-- Put cursor on beta.
			child.api.nvim_win_set_cursor(0, { 2, 0 })
			-- Select beta + gamma linewise
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 3, 4 })

			child.lua([[ M.create({ capture_file = ... }) ]], { capture_file })

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(lines, { "beta", "gamma" })
		end)

		it("pre-fills the capture window when visual selection is made backwards", function()
			local capture_file = "reverse-visual-capture.md.gpg"

			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/source.txt"))
			child.api.nvim_buf_set_lines(0, 0, -1, false, {
				"alpha beta gamma",
			})

			child.api.nvim_win_set_cursor(0, { 1, 9 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 6 })

			child.lua([[ M.create({ capture_file = ... }) ]], { capture_file })

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(lines, { "beta" })
		end)

		it("captures the visual selection through the capture mapping", function()
			child.lua([[
		vim.keymap.set({ "n", "v" }, "<leader>mc", function()
			require("memo.capture").create({
				capture_file = "visual-mapping.md.gpg",
			})
		end, { desc = "Capture to braindump" })
	]])

			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/source.txt"))
			child.api.nvim_buf_set_lines(0, 0, -1, false, {
				"alpha beta gamma",
				"delta epsilon",
			})

			-- Select "beta".
			child.api.nvim_win_set_cursor(0, { 1, 6 })
			child.cmd("normal! v")
			child.api.nvim_win_set_cursor(0, { 1, 9 })

			-- Invoke the visual mapping while the selection is active.
			child.lua([[
		vim.api.nvim_feedkeys(
			vim.api.nvim_replace_termcodes("<leader>mc", true, false, true),
			"x",
			false
		)
	]])

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(lines, { "beta" })
		end)

		it("aborts when the source buffer is empty", function()
			local capture_file = "empty-capture.md.gpg"

			child.cmd("edit " .. vim.fn.fnameescape(vim.env.NOTES_DIR .. "/source.txt"))

			child.lua([[ M.create({ capture_file = ..., range = { 1, -1 } }) ]], { capture_file })

			local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
			MiniTest.expect.equality(lines, { "" })

			child.cmd("write")
			local messages = child.cmd_capture("messages")
			MiniTest.expect.equality(messages, "Capture aborted: empty content")
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/empty-capture.md.gpg"), 0)
		end)

		it("keeps the buffer and reports an error when encryption fails", function()
			local capture_file = "fail.md.gpg"

			-- Simulate a failed encryption (e.g. memo CLI error).
			child.lua([[
				crypto.encrypt_from_stdin = function()
					return { code = 1, stderr = "boom" }
				end
			]])

			child.lua([[ M.create({ capture_file = ... }) ]], { capture_file })

			child.type_keys("i", "precious content", "<Esc>")

			local buf = child.api.nvim_get_current_buf()
			child.cmd("write")

			MiniTest.expect.equality(child.api.nvim_buf_is_valid(buf), true)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/fail.md.gpg"), 0)

			child.wait_until(function()
				return child.cmd_capture("messages") == "Capture failed: content was not saved"
			end)

			-- The BufWriteCmd handler must survive the failed attempt: retrying
			-- the write must save the content (and not fail with E676).
			child.lua([[
				crypto.encrypt_from_stdin = function(path, lines)
					vim.fn.writefile(lines, path)
					return { code = 0 }
				end
			]])

			child.cmd("write")

			MiniTest.expect.equality(child.api.nvim_buf_is_valid(buf), false)
			MiniTest.expect.equality(child.fn.filereadable(vim.env.NOTES_DIR .. "/fail.md.gpg"), 1)
		end)

		it("creates the capture file with passphrase encryption when the passphrase mode is configured", function()
			child.lua([[ require("memo.gpg").prompt_passphrase = function() return "cap-sym" end ]])
			child.lua([[ M.create({ capture_file = "sym-capture.md", encryption = { mode = "passphrase" } }) ]])

			child.type_keys("i", "symmetric capture", "<Esc>")
			child.cmd("write")

			local note = vim.env.NOTES_DIR .. "/sym-capture.md.asc"
			MiniTest.expect.equality(child.fn.filereadable(note), 1)
			MiniTest.expect.equality(helpers.is_symmetric_file(note), true)

			local result = helpers.decrypt_symmetric_file(note, "cap-sym")
			MiniTest.expect.equality(result.code, 0)
			MiniTest.expect.equality(vim.trim(result.stdout or ""), "symmetric capture")
		end)

		it("keeps an existing capture file encrypted to the key even when the passphrase mode is configured", function()
			local note = vim.env.NOTES_DIR .. "/switch-capture.md.asc"
			helpers.encrypt_file(note, "existing\n")

			child.lua([[ require("memo.gpg").prompt_passphrase = function() return "switch-sym" end ]])
			child.lua([[ M.create({ capture_file = "switch-capture.md", encryption = { mode = "passphrase" } }) ]])

			child.type_keys("i", "new capture", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(helpers.is_symmetric_file(note), false)

			local result = helpers.decrypt_file(note)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("new capture") ~= nil, true)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("existing") ~= nil, true)
		end)

		it("keeps an existing passphrase capture file even when the key mode is configured", function()
			local note = vim.env.NOTES_DIR .. "/keep-sym-key.md.asc"
			helpers.encrypt_symmetric_file(note, "existing\n", "keep-key")

			child.lua([[ require("memo.gpg").prompt_passphrase = function() return "keep-key" end ]])
			child.lua([[ M.create({ capture_file = "keep-sym-key.md", encryption = { mode = "key" } }) ]])

			child.type_keys("i", "appended", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(helpers.is_symmetric_file(note), true)

			local result = helpers.decrypt_symmetric_file(note, "keep-key")
			MiniTest.expect.equality(result.code, 0)
			MiniTest.expect.equality(vim.trim(result.stdout or ""), "appended\nexisting")
		end)

		it("keeps an existing passphrase capture file without a mode", function()
			local note = vim.env.NOTES_DIR .. "/keep-sym.md.asc"
			helpers.encrypt_symmetric_file(note, "existing\n", "keep-sym")

			child.lua([[ require("memo.gpg").prompt_passphrase = function() return "keep-sym" end ]])
			child.lua([[ M.create({ capture_file = "keep-sym.md" }) ]])

			child.type_keys("i", "appended", "<Esc>")
			child.cmd("write")

			MiniTest.expect.equality(helpers.is_symmetric_file(note), true)

			local result = helpers.decrypt_symmetric_file(note, "keep-sym")
			MiniTest.expect.equality(result.code, 0)
			MiniTest.expect.equality(vim.trim(result.stdout or ""), "appended\nexisting")
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

		it("captures text when capture file does not exists and gpg key has password", function()
			local capture_file = "capture-test-password.md.gpg"
			local capture_file_path = vim.env.NOTES_DIR .. "/capture-test-password.md.gpg"

			child.lua([[ M.create({ capture_file = ... }) ]], { capture_file })

			child.type_keys("i", "Integration Test Content 1", "<Esc>")

			child.cmd("write")

			local exists = child.fn.filereadable(capture_file_path)
			MiniTest.expect.equality(exists, 1)

			local head = child.fn.readfile(capture_file_path)[1]
			MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

			helpers.cache_gpg_password(gpg_key_password)

			local result = helpers.decrypt_file(capture_file_path)

			MiniTest.expect.equality(result.code, 0)
			MiniTest.expect.equality((result.stdout or ""):find("Integration Test Content 1") ~= nil, true)
		end)

		it("captures text when capture file exists", function()
			local capture_file = "second-capture-test-with-password.md"
			local capture_file_path = vim.env.NOTES_DIR .. "/" .. capture_file
			local encrypted = capture_file_path .. ".gpg"

			helpers.encrypt_file(encrypted, "CAPTURE")

			child.lua(
				[[
        local password, capture_file = ...
        local gpg = require("memo.gpg")

        gpg.prompt_passphrase = function()
          return password
        end

	      M.create({ capture_file = capture_file })
	    ]],
				{ gpg_key_password, capture_file .. ".gpg" }
			)

			child.type_keys("i", "Integration Test Content 2", "<Esc>")

			child.cmd("write")

			local exists = child.fn.filereadable(encrypted)
			MiniTest.expect.equality(exists, 1)

			local head = child.fn.readfile(encrypted)[1]
			MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")

			local result = helpers.decrypt_file(encrypted)
			MiniTest.expect.equality(result.code, 0)
			--- @diagnostic disable-next-line: param-type-mismatch, need-check-nil
			MiniTest.expect.equality(result.stdout:find("Integration Test Content 2") ~= nil, true)
		end)
	end)
end)
