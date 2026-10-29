local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("note_io", function()
	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		child.lua(
			[[
			vim.g.memo_notes_dir = ...
			require("memo.config").setup()

			local crypto = require("memo.crypto")
			crypto.decrypt_to_stdout = function()
				vim.g.decrypt_calls = (vim.g.decrypt_calls or 0) + 1
				if vim.g.decrypt_cancel then
					return nil
				end
				if vim.g.decrypt_error then
					return nil, vim.g.decrypt_error
				end
				return { code = 0, stdout = vim.g.decrypt_output or "" }
			end

			crypto.encrypt_from_stdin = function(path, lines, bufnr, opts)
				vim.g.write_path = path
				vim.g.write_lines = lines
				vim.g.write_bufnr = bufnr
				vim.g.write_mode = opts and opts.mode
				vim.g.write_force_mode = opts and opts.force_mode
				if vim.g.write_error then
					return false, vim.g.write_error
				end
				if vim.g.write_cancel then
					return false
				end
				vim.fn.writefile(lines, path)
				return true
			end

			M = require("memo.note_io")
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

	describe("read_lines", function()
		it("does not decrypt a missing file", function()
			local path = vim.env.NOTES_DIR .. "/missing.md.asc"
			MiniTest.expect.equality(child.lua_get([[ M.read_lines(..., 7) ]], { path }), {})
			MiniTest.expect.equality(child.lua_get("vim.g.decrypt_calls or 0"), 0)
		end)

		it("does not decrypt an empty file", function()
			local path = vim.env.NOTES_DIR .. "/empty.md.asc"
			helpers.write_file(path, "")
			MiniTest.expect.equality(child.lua_get([[ M.read_lines(..., 7) ]], { path }), {})
			MiniTest.expect.equality(child.lua_get("vim.g.decrypt_calls or 0"), 0)
		end)

		it("splits decrypted output without a trailing newline", function()
			local path = vim.env.NOTES_DIR .. "/note.md.asc"
			helpers.write_file(path, "ciphertext")
			child.lua([[ vim.g.decrypt_output = "one\ntwo" ]])
			MiniTest.expect.equality(child.lua_get([[ M.read_lines(..., 7) ]], { path }), { "one", "two" })
			MiniTest.expect.equality(child.lua_get("vim.g.decrypt_calls"), 1)
		end)

		it("removes only the final empty line from newline-terminated output", function()
			local path = vim.env.NOTES_DIR .. "/note.md.asc"
			helpers.write_file(path, "ciphertext")
			child.lua([[ vim.g.decrypt_output = "one\ntwo\n" ]])
			MiniTest.expect.equality(child.lua_get([[ M.read_lines(..., 7) ]], { path }), { "one", "two" })
		end)

		it("preserves interior and repeated blank lines", function()
			local path = vim.env.NOTES_DIR .. "/note.md.asc"
			helpers.write_file(path, "ciphertext")
			child.lua([[ vim.g.decrypt_output = "one\n\ntwo\n\n" ]])
			MiniTest.expect.equality(child.lua_get([[ M.read_lines(..., 7) ]], { path }), { "one", "", "two", "" })
		end)

		it("returns a decryption error unchanged", function()
			local path = vim.env.NOTES_DIR .. "/note.md.asc"
			helpers.write_file(path, "ciphertext")
			child.lua([[ vim.g.decrypt_error = "bad passphrase" ]])
			local result = child.lua_get(
				[[
				(function(...)
					local lines, err = M.read_lines(...)
					return { lines or vim.NIL, err or vim.NIL }
				end)(...)
				]],
				{ path }
			)
			MiniTest.expect.equality(result, { vim.NIL, "bad passphrase" })
		end)

		it("keeps a dismissed prompt distinguishable from an error", function()
			local path = vim.env.NOTES_DIR .. "/note.md.asc"
			helpers.write_file(path, "ciphertext")
			child.lua([[ vim.g.decrypt_cancel = true ]])
			local result = child.lua_get(
				[[
				(function(...)
					local lines, err = M.read_lines(...)
					return { lines or vim.NIL, err or vim.NIL }
				end)(...)
				]],
				{ path }
			)
			MiniTest.expect.equality(result, { vim.NIL, vim.NIL })
		end)
	end)

	describe("write_lines", function()
		it("passes the path, lines, buffer, and requested mode to encryption", function()
			local path = vim.env.NOTES_DIR .. "/written.md.asc"
			MiniTest.expect.equality(
				child.lua_get([[ M.write_lines(..., { "one", "two" }, 17, { mode = "passphrase" }) ]], { path }),
				true
			)
			MiniTest.expect.equality(child.lua_get("vim.g.write_path"), path)
			MiniTest.expect.equality(child.lua_get("vim.g.write_lines"), { "one", "two" })
			MiniTest.expect.equality(child.lua_get("vim.g.write_bufnr"), 17)
			MiniTest.expect.equality(child.lua_get("vim.g.write_mode"), "passphrase")
			MiniTest.expect.equality(vim.fn.readfile(path), { "one", "two" })
		end)

		it("restores an existing file when encryption fails", function()
			local path = vim.env.NOTES_DIR .. "/existing.md.asc"
			helpers.write_file(path, "original\n")
			child.lua([[ vim.g.write_error = "encryption failed" ]])
			local result = child.lua_get([[ { M.write_lines(..., { "replacement" }, nil) } ]], { path })
			MiniTest.expect.equality(result, { false, "encryption failed" })
			MiniTest.expect.equality(vim.fn.readfile(path), { "original" })
		end)

		it("removes a partial file when a new-file write fails", function()
			local path = vim.env.NOTES_DIR .. "/new.md.asc"
			child.lua([[
				require("memo.crypto").encrypt_from_stdin = function(path)
					vim.fn.writefile({ "partial" }, path)
					return false, "write failed"
				end
			]])
			local result = child.lua_get(
				[[
				(function(...)
					local success, err = M.write_lines(..., { "content" }, nil)
					return { success, err or vim.NIL }
				end)(...)
				]],
				{ path }
			)
			MiniTest.expect.equality(result, { false, "write failed" })
			MiniTest.expect.equality(vim.fn.filereadable(path), 0)
		end)

		it("restores an empty existing file when the replacement fails", function()
			local path = vim.env.NOTES_DIR .. "/empty.md.asc"
			helpers.write_file(path, "")
			child.lua([[ vim.g.write_error = "write failed" ]])
			local result = child.lua_get([[ { M.write_lines(..., { "replacement" }, nil) } ]], { path })
			MiniTest.expect.equality(result, { false, "write failed" })
			MiniTest.expect.equality(vim.fn.filereadable(path), 1)
			MiniTest.expect.equality(vim.fn.getfsize(path), 0)
		end)
	end)

	describe("insert_lines", function()
		it("appends by default without adding padding", function()
			local path = vim.env.NOTES_DIR .. "/append.md.asc"
			helpers.write_file(path, "ciphertext")
			child.lua([[ vim.g.decrypt_output = "existing\\nline" ]])

			local success = child.lua_get([[ M.insert_lines(..., { "new" }, 17) ]], { path })

			MiniTest.expect.equality(success, true)
			MiniTest.expect.equality(child.lua_get("vim.g.write_lines"), { "existing", "line", "new" })
			MiniTest.expect.equality(child.lua_get("vim.g.write_bufnr"), 17)
		end)

		it("prepends lines when requested", function()
			local path = vim.env.NOTES_DIR .. "/prepend.md.asc"
			helpers.write_file(path, "ciphertext")
			child.lua([[ vim.g.decrypt_output = "existing\\nline" ]])

			local success = child.lua_get([[ M.insert_lines(..., { "first", "second" }, nil, { prepend = true }) ]], { path })

			MiniTest.expect.equality(success, true)
			MiniTest.expect.equality(child.lua_get("vim.g.write_lines"), { "first", "second", "existing", "line" })
		end)

		it("preserves refile padding when appending", function()
			local path = vim.env.NOTES_DIR .. "/padding.md.asc"
			helpers.write_file(path, "ciphertext")
			child.lua([[ vim.g.decrypt_output = "existing" ]])

			local success = child.lua_get(
				[[ M.insert_lines(..., { "new" }, nil, { padding = { top = 0, bottom = 2 } }) ]],
				{ path }
			)

			MiniTest.expect.equality(success, true)
			MiniTest.expect.equality(child.lua_get("vim.g.write_lines"), { "existing", "", "new", "", "" })
		end)

		it("applies padding around prepended content", function()
			local path = vim.env.NOTES_DIR .. "/prepend-padding.md.asc"
			helpers.write_file(path, "ciphertext")
			child.lua([[ vim.g.decrypt_output = "existing" ]])

			local success = child.lua_get(
				[[ M.insert_lines(..., { "new" }, nil, { prepend = true, padding = { top = 1, bottom = 2 } }) ]],
				{ path }
			)

			MiniTest.expect.equality(success, true)
			MiniTest.expect.equality(child.lua_get("vim.g.write_lines"), { "", "new", "", "", "existing" })
		end)

		it("uses the requested encryption mode for an empty destination", function()
			local path = vim.env.NOTES_DIR .. "/empty-destination.md.asc"
			helpers.write_file(path, "")

			local success = child.lua_get(
				[[ M.insert_lines(..., { "new" }, nil, { mode = "passphrase" }) ]],
				{ path }
			)

			MiniTest.expect.equality(success, true)
			MiniTest.expect.equality(child.lua_get("vim.g.write_mode"), "passphrase")
		end)

		it("does not overwrite a destination when reading fails", function()
			local path = vim.env.NOTES_DIR .. "/read-failure.md.asc"
			helpers.write_file(path, "ciphertext")
			child.lua([[ vim.g.decrypt_error = "bad passphrase" ]])

			local result = child.lua_get(
				[[
				(function(path)
					local success, err = M.insert_lines(path, { "new" })
					return { success, err }
				end)(...)
				]],
				{ path }
			)

			MiniTest.expect.equality(result, { false, "bad passphrase" })
			MiniTest.expect.equality(child.lua_get("vim.g.write_path or vim.NIL"), vim.NIL)
			MiniTest.expect.equality(vim.fn.readfile(path), { "ciphertext" })
		end)

		it("rejects a directory destination", function()
			local path = vim.env.NOTES_DIR .. "/destination-directory"
			vim.fn.mkdir(path)

			local result = child.lua_get(
				[[
				(function(path)
					local success, err = M.insert_lines(path, { "new" })
					return { success, err }
				end)(...)
				]],
				{ path }
			)

			MiniTest.expect.equality(result[1], false)
			MiniTest.expect.equality(result[2]:find("destination is not a regular file", 1, true) ~= nil, true)
			MiniTest.expect.equality(child.lua_get("vim.g.write_path or vim.NIL"), vim.NIL)
		end)

		it("restores the destination when the follow-up fails", function()
			local path = vim.env.NOTES_DIR .. "/insert-follow-up.md.asc"
			helpers.write_file(path, "ciphertext")
			child.lua([[ vim.g.decrypt_output = "original" ]])

			local result = child.lua_get(
				[[
				(function(path)
					local success, err = M.insert_lines(path, { "new" }, nil, {
						after = function()
							return false, "follow-up failed"
						end,
					})
					return { success, err }
				end)(...)
				]],
				{ path }
			)

			MiniTest.expect.equality(result, { false, "follow-up failed" })
			MiniTest.expect.equality(vim.fn.readfile(path), { "ciphertext" })
		end)
	end)

	describe("follow-up writes", function()
		it("keeps the write when the follow-up succeeds", function()
			local path = vim.env.NOTES_DIR .. "/follow-up.md.asc"
			helpers.write_file(path, "original\n")

			local success = child.lua_get(
				[[
				(function(path)
					return M.write_lines(path, { "replacement" }, nil, { mode = "key" }, function()
						vim.g.follow_up_ran = true
						return true
					end)
				end)(...)
			]],
				{ path }
			)

			MiniTest.expect.equality(success, true)
			MiniTest.expect.equality(child.lua_get("vim.g.follow_up_ran"), true)
			MiniTest.expect.equality(vim.fn.readfile(path), { "replacement" })
			MiniTest.expect.equality(child.fn.glob(path:gsub("%.asc$", ".memo-backup-*.asc")), "")
		end)

		it("restores the original when the follow-up fails", function()
			local path = vim.env.NOTES_DIR .. "/follow-up-fail.md.asc"
			helpers.write_file(path, "original\n")

			local result = child.lua_get(
				[[
				(function(path)
					local success, err = M.write_lines(path, { "replacement" }, nil, { mode = "key" }, function()
						return false, "follow-up failed"
					end)
					return { success, err or vim.NIL, vim.fn.readfile(path) }
				end)(...)
			]],
				{ path }
			)

			MiniTest.expect.equality(result, { false, "follow-up failed", { "original" } })
			MiniTest.expect.equality(child.fn.glob(path:gsub("%.asc$", ".memo-backup-*.asc")), "")
		end)

		it("removes a note it created when the follow-up fails", function()
			local path = vim.env.NOTES_DIR .. "/follow-up-new.md.asc"

			local result = child.lua_get(
				[[
				(function(path)
					local success, err = M.write_lines(path, { "replacement" }, nil, { mode = "key" }, function()
						return false, "follow-up failed"
					end)
					return { success, err or vim.NIL, vim.fn.filereadable(path) }
				end)(...)
			]],
				{ path }
			)

			MiniTest.expect.equality(result, { false, "follow-up failed", 0 })
		end)

		it("restores the original when the follow-up raises", function()
			local path = vim.env.NOTES_DIR .. "/follow-up-raise.md.asc"
			helpers.write_file(path, "original\n")

			local result = child.lua_get(
				[[
				(function(path)
					local ok, err = pcall(function()
						M.write_lines(path, { "replacement" }, nil, { mode = "key" }, function()
							error("boom")
						end)
					end)
					return { ok, tostring(err), vim.fn.readfile(path) }
				end)(...)
			]],
				{ path }
			)

			MiniTest.expect.equality(result[1], false)
			MiniTest.expect.equality(result[2]:find("boom", 1, true) ~= nil, true)
			MiniTest.expect.equality(result[3], { "original" })
		end)
	end)

	describe("write protection", function()
		it("restores the original when replacement encryption fails", function()
			local path = vim.env.NOTES_DIR .. "/protected.md.asc"
			helpers.write_file(path, "original\n")
			child.lua([[ vim.g.write_error = "failed" ]])
			local result =
				child.lua_get([[ { M.write_lines(..., { "replacement" }, nil, { mode = "key" }) } ]], { path })
			MiniTest.expect.equality(result, { false, "failed" })
			MiniTest.expect.equality(vim.fn.readfile(path), { "original" })
		end)
		it("removes a new file when encryption is cancelled", function()
			local path = vim.env.NOTES_DIR .. "/cancelled.md.asc"
			child.lua([[ vim.g.write_cancel = true ]])

			local result = child.lua_get(
				[[
				(function(...)
					local success, err = M.write_lines(..., { "content" }, nil)
					return { success, err or vim.NIL }
				end)(...)
				]],
				{ path }
			)

			MiniTest.expect.equality(result, { false, vim.NIL })
			MiniTest.expect.equality(vim.fn.filereadable(path), 0)
		end)

		it("restores an existing note when encryption raises", function()
			local path = vim.env.NOTES_DIR .. "/raised.md.asc"
			helpers.write_file(path, "original\n")
			child.lua([[ require("memo.crypto").encrypt_from_stdin = function() error("boom") end ]])

			local result = child.lua_get(
				[[
				(function(path)
					return { pcall(function() M.write_lines(path, { "replacement" }, nil) end) }
				end)(...)
			]],
				{ path }
			)

			MiniTest.expect.equality(result[1], false)
			MiniTest.expect.equality(result[2]:find("boom", 1, true) ~= nil, true)
			MiniTest.expect.equality(vim.fn.readfile(path), { "original" })
		end)

		it("keeps the replacement and discards the backup after success", function()
			local path = vim.env.NOTES_DIR .. "/protected-success.md.asc"
			helpers.write_file(path, "original\n")

			local success = child.lua_get([[ M.write_lines(..., { "replacement" }, nil, { mode = "key" }) ]], { path })

			MiniTest.expect.equality(success, true)
			MiniTest.expect.equality(vim.fn.readfile(path), { "replacement" })
			MiniTest.expect.equality(child.fn.glob(path:gsub("%.asc$", ".memo-backup-*.asc")), "")
		end)

		it("keeps the original in place when forcing the encryption mode", function()
			local path = vim.env.NOTES_DIR .. "/force-mode.md.asc"
			helpers.write_file(path, "original\n")
			child.lua([[
				local crypto = require("memo.crypto")
				local encrypt = crypto.encrypt_from_stdin

				crypto.encrypt_from_stdin = function(path, ...)
					vim.g.existed_during_encrypt = vim.fn.filereadable(path)
					return encrypt(path, ...)
				end
			]])

			local success = child.lua_get(
				[[ M.write_lines(..., { "replacement" }, nil, { mode = "key", force_mode = true }) ]],
				{ path }
			)

			MiniTest.expect.equality(success, true)
			MiniTest.expect.equality(child.lua_get("vim.g.existed_during_encrypt"), 1)
			MiniTest.expect.equality(child.lua_get("vim.g.write_force_mode"), true)
			MiniTest.expect.equality(vim.fn.readfile(path), { "replacement" })
		end)

		it("reports backup cleanup failure without reporting the write as failed", function()
			local path = vim.env.NOTES_DIR .. "/backup-cleanup.md.asc"
			helpers.write_file(path, "original\n")
			child.lua([[
				local delete = vim.fn.delete
				local message = require("memo.message")
				message.warn = function(fmt, ...)
					vim.g.backup_warning = fmt:format(...)
				end
				vim.fn.delete = function(path)
					if path:find(".memo-backup-", 1, true) then
						return -1
					end
					return delete(path)
				end
			]])

			local result =
				child.lua_get([[ { M.write_lines(..., { "replacement" }, nil, { mode = "key" }) } ]], { path })

			MiniTest.expect.equality(result[1], true)
			MiniTest.expect.equality(result[2], "note was written but its backup could not be removed")
			local backup_path = child.fn.glob(path:gsub("%.asc$", ".memo-backup-*.asc"))
			MiniTest.expect.equality(
				child.lua_get("vim.g.backup_warning"),
				"Memo: note was written but its backup could not be removed: " .. backup_path
			)
			MiniTest.expect.equality(vim.fn.readfile(path), { "replacement" })
			MiniTest.expect.equality(child.fn.glob(path:gsub("%.asc$", ".memo-backup-*.asc")) ~= "", true)
		end)
	end)
end)
