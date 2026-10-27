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

	describe("overwrite and write protection", function()
		it("restores the original when replacement encryption fails", function()
			local path = vim.env.NOTES_DIR .. "/protected.md.asc"
			helpers.write_file(path, "original\n")
			child.lua([[ vim.g.write_error = "failed" ]])
			local result = child.lua_get([[ { M.overwrite(..., { "replacement" }, { mode = "key" }) } ]], { path })
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

		it("prepares the buffer after removing the old file", function()
			local path = vim.env.NOTES_DIR .. "/prepared.md.asc"
			helpers.write_file(path, "original\n")
			local result = child.lua_get(
				[[
				(function(path)
					return M.overwrite(path, { "replacement" }, { mode = "passphrase" }, function()
						MiniTest.expect.equality(vim.fn.filereadable(path), 0)
						return 17
					end)
				end)(...)
			]],
				{ path }
			)
			MiniTest.expect.equality(result, true)
			MiniTest.expect.equality(child.lua_get("vim.g.write_bufnr"), 17)
			MiniTest.expect.equality(child.lua_get("vim.g.write_mode"), "passphrase")
		end)

		it("keeps the replacement and discards the backup after success", function()
			local path = vim.env.NOTES_DIR .. "/protected-success.md.asc"
			helpers.write_file(path, "original\n")

			local success = child.lua_get([[ M.overwrite(..., { "replacement" }, { mode = "key" }) ]], { path })

			MiniTest.expect.equality(success, true)
			MiniTest.expect.equality(vim.fn.readfile(path), { "replacement" })
			MiniTest.expect.equality(child.fn.glob(path:gsub("%.asc$", ".memo-backup-*.asc")), "")
		end)
	end)
end)
