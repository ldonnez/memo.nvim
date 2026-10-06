local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("gpg", function()
	before_each(function()
		helpers.setup_test_env()

		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		-- Load tested plugin
		child.lua([[ M = require('memo.gpg') ]])
	end)

	after_each(function()
		helpers.cleanup_test_env()
		child.stop()
		helpers.kill_gpg_agent()
	end)

	it("correctly asks password of default key without target_path", function()
		local password = "testpassword"
		helpers.create_gpg_key("mock-password@example.com", password)

		local result = child.lua(
			[[
        local password = ...
        local gpg = require("memo.gpg")

        gpg.prompt_passphrase = function(label)
          captured_prompt = label
          return password
        end

        return M.unlock_key()
    ]],
			{ password }
		)

		MiniTest.expect.equality(result, true)
	end)

	it("does not cache password when its wrong", function()
		local password = "testpassword"
		local keyid = "mock-wrong-password@example.com"
		helpers.create_gpg_key(keyid, password)

		local result = child.lua(
			[[
        local password = ...
        local gpg = require("memo.gpg")

        gpg.prompt_passphrase = function()
          return password
        end

        return M.unlock_key()
    ]],
			{ "wrong-password" }
		)

		MiniTest.expect.equality(result, false)

		child.wait_until(function()
			return child.cmd_capture("messages") == "GPG: incorrect passphrase"
		end)
	end)

	it("gets correct gpg key from encrypted file", function()
		local encrypted = "/tmp/plain.txt.gpg"
		local key_id = helpers.create_gpg_key("mock@example.com")

		helpers.encrypt_file(encrypted, "Hello world!")

		local result = child.lua_get("M.get_file_key_ids(...)", { encrypted })

		MiniTest.expect.equality(result, { key_id })
	end)

	it("does not get key from file when its not encrypted", function()
		local encrypted = "/tmp/plain.txt.gpg"
		helpers.create_gpg_key("mock@example.com")
		helpers.write_file(encrypted, "Hello World")
		local result = child.lua_get("M.get_file_key_ids(...)", { encrypted })

		MiniTest.expect.equality(result, {})
	end)

	it("detects multiple key IDs in a single encrypted file", function()
		local encrypted = "/tmp/multi.txt.gpg"

		local key1 = "user1@example.com"
		local key2 = "user2@example.com"

		local id1 = helpers.create_gpg_key(key1, "pass1")
		local id2 = helpers.create_gpg_key(key2, "pass2")

		helpers.encrypt_file(encrypted, "Hello world!", { env = { GPG_RECIPIENTS = key1 .. "," .. key2 } })

		local result = child.lua_get("M.get_file_key_ids(...)", { encrypted })

		-- Sort to ensure order
		table.sort(result)
		local expected = { id1, id2 }
		table.sort(expected)

		MiniTest.expect.equality(result, expected)
	end)

	it("selects the correct secret key from a list of recipients", function()
		local encrypted = "/tmp/mixed.txt.gpg"
		local password = "mypass"
		local my_id = helpers.create_gpg_key("me@example.com", password)
		local foreign_id = "ABCDEF1234567890"

		helpers.encrypt_file(encrypted, "Hello world!", { env = { GPG_RECIPIENTS = my_id .. "," .. foreign_id } })

		-- It should ask for my_id, NOT foreign_id
		local result_id = child.lua(
			[[
        local password, encrypted = ...
        local captured_prompt = ""

        require("memo.gpg").prompt_passphrase = function(label)
            captured_prompt = label
            return password
        end

        M.unlock_key(encrypted)
        return captured_prompt
       ]],
			{ password, encrypted }
		)

		MiniTest.expect.equality(result_id, "Mock Test Key <me@example.com> (" .. my_id .. ")")
	end)

	it("aborts execution when the key cannot be unlocked", function()
		local encrypted = "/tmp/gpg_abort.txt.gpg"
		helpers.create_gpg_key("mock@example.com")
		helpers.encrypt_file(encrypted, "Hello world!")

		local result = child.lua(
			[[
       local encrypted = ...
       M.unlock_key = function() return false end

       return M.decrypt(encrypted)
        ]],
			{ encrypted }
		)

		MiniTest.expect.equality(result, vim.NIL)
	end)

	it("decrypts a key note once the key is unlocked", function()
		local encrypted = "/tmp/gpg_key_note.txt.gpg"
		helpers.create_gpg_key("mock@example.com")
		helpers.encrypt_file(encrypted, "Hello world!")

		local result = child.lua_get([[ M.decrypt(...):wait() ]], { encrypted })

		MiniTest.expect.equality(result.code, 0)
		MiniTest.expect.equality(vim.trim(result.stdout or ""), "Hello world!")
	end)

	it("returns the failing result without notifying; callers own error reporting", function()
		local encrypted = "/tmp/gpg_corrupt.txt.gpg"
		helpers.create_gpg_key("mock@example.com")
		helpers.write_file(encrypted, "not a note")

		local result = child.lua(
			[[
        local encrypted = ...
        M.unlock_key = function() return true end

        return M.decrypt(encrypted):wait()
    ]],
			{ encrypted }
		)

		MiniTest.expect.equality(result.code ~= 0, true)

		MiniTest.expect.equality(child.cmd_capture("messages"), "")
	end)

	it("hands the passphrase of a passphrase note to memo in the environment", function()
		local encrypted = "/tmp/gpg_symmetric.txt.gpg"
		local passphrase = "sym-pass"

		helpers.encrypt_symmetric_file(encrypted, "Hello world!", passphrase)

		local result = child.lua(
			[[
        local passphrase, encrypted = ...
        M.prompt_passphrase = function() return passphrase end

        return M.decrypt(encrypted):wait()
    ]],
			{ passphrase, encrypted }
		)

		MiniTest.expect.equality(result.code, 0)
		MiniTest.expect.equality(vim.trim(result.stdout or ""), "Hello world!")
	end)

	it("asks for the passphrase of a passphrase note by file name", function()
		local encrypted = "/tmp/gpg_symmetric_label.txt.gpg"

		helpers.encrypt_symmetric_file(encrypted, "Hello world!", "sym-pass")

		local label = child.lua(
			[[
        local encrypted = ...
        local asked = nil

        M.prompt_passphrase = function(l)
          asked = l
          return l
        end

        M.decrypt(encrypted):wait()

        return asked
    ]],
			{ encrypted }
		)

		MiniTest.expect.equality(label, "note gpg_symmetric_label.txt.gpg (symmetric)")
	end)

	it("encrypts a key note without asking for anything", function()
		local note = "/tmp/gpg_encrypt_key.txt.gpg"
		helpers.create_gpg_key("mock@example.com")

		local result = child.lua(
			[[
        local note = ...
        local prompts = 0

        M.prompt_passphrase = function()
          prompts = prompts + 1
          return ""
        end

        return { prompts = prompts, code = M.encrypt(note, { "Hello world!" }).code }
    ]],
			{ note }
		)

		MiniTest.expect.equality(result, { prompts = 0, code = 0 })

		local decrypted = helpers.decrypt_file(note)
		MiniTest.expect.equality(vim.trim(decrypted.stdout or ""), "Hello world!")
	end)

	it("encrypts a passphrase note with a passphrase", function()
		local note = "/tmp/gpg_encrypt_symmetric.txt.gpg"
		local passphrase = "sym-pass"

		helpers.encrypt_symmetric_file(note, "Line 1\n", passphrase)

		local result = child.lua(
			[[
        local passphrase, note = ...
        M.prompt_passphrase = function() return passphrase end

        return { code = M.encrypt(note, { "Hello world!" }).code }
    ]],
			{ passphrase, note }
		)

		MiniTest.expect.equality(result.code, 0)
		MiniTest.expect.equality(helpers.is_symmetric_file(note), true)

		local decrypted = helpers.decrypt_symmetric_file(note, passphrase)
		MiniTest.expect.equality(vim.trim(decrypted.stdout or ""), "Hello world!")
	end)

	it("encrypts to the passphrase of a note that does not exist yet when asked", function()
		local note = "/tmp/gpg_encrypt_new_symmetric.txt.gpg"
		local passphrase = "sym-pass"

		local result = child.lua(
			[[
        local passphrase, note = ...
        M.prompt_passphrase = function() return passphrase end

        return { code = M.encrypt(note, { "Hello world!" }, { mode = "passphrase" }).code }
    ]],
			{ passphrase, note }
		)

		MiniTest.expect.equality(result.code, 0)
		MiniTest.expect.equality(helpers.is_symmetric_file(note), true)

		local decrypted = helpers.decrypt_symmetric_file(note, passphrase)
		MiniTest.expect.equality(vim.trim(decrypted.stdout or ""), "Hello world!")
	end)

	it("encrypts to the key of a note that does not exist yet by default", function()
		local note = "/tmp/gpg_encrypt_new_key.txt.gpg"
		helpers.create_gpg_key("mock@example.com")

		local result = child.lua(
			[[
        local note = ...
        local prompts = 0

        M.prompt_passphrase = function()
          prompts = prompts + 1
          return ""
        end

        return { prompts = prompts, code = M.encrypt(note, { "Hello world!" }).code }
    ]],
			{ note }
		)

		MiniTest.expect.equality(result, { prompts = 0, code = 0 })
		MiniTest.expect.equality(helpers.is_symmetric_file(note), false)

		local decrypted = helpers.decrypt_file(note)
		MiniTest.expect.equality(vim.trim(decrypted.stdout or ""), "Hello world!")
	end)

	it("writes nothing when the passphrase of a new passphrase note is dismissed", function()
		local note = "/tmp/gpg_encrypt_new_dismissed.txt.gpg"

		local result = child.lua(
			[[
        local note = ...
        M.prompt_passphrase = function() return "" end

        local written = M.encrypt(note, { "Hello world!" }, { mode = "passphrase" })

        return { code = written.code, stderr = written.stderr }
    ]],
			{ note }
		)

		MiniTest.expect.equality(result.code ~= 0, true)
		MiniTest.expect.equality(result.stderr:find("passphrase was not given", 1, true) ~= nil, true)
		MiniTest.expect.equality(vim.fn.filereadable(note), 0)
	end)

	it("writes nothing when the passphrase of a passphrase note is dismissed", function()
		local note = "/tmp/gpg_encrypt_dismissed.txt.gpg"
		local passphrase = "sym-pass"

		helpers.encrypt_symmetric_file(note, "Line 1\n", passphrase)

		local result = child.lua(
			[[
        local note = ...
        M.prompt_passphrase = function() return "" end

        local written = M.encrypt(note, { "Hello world!" })

        return { code = written.code, stderr = written.stderr }
    ]],
			{ note }
		)

		MiniTest.expect.equality(result.code ~= 0, true)
		MiniTest.expect.equality(result.stderr:find("passphrase was not given", 1, true) ~= nil, true)

		-- The note keeps what it held instead of becoming an empty or broken one.
		local kept = helpers.decrypt_symmetric_file(note, passphrase)
		MiniTest.expect.equality(vim.trim(kept.stdout or ""), "Line 1")
	end)

	it("writes nothing when the confirmation of a new passphrase note does not match", function()
		local note = "/tmp/gpg_encrypt_new_mismatch.txt.gpg"

		local result = child.lua(
			[[
        local note = ...
        local answers = { "first answer", "second answer" }
        local prompts = 0

        M.prompt_passphrase = function()
          prompts = prompts + 1
          return answers[prompts]
        end

        local written = M.encrypt(note, { "Hello world!" }, { mode = "passphrase" })

        return { prompts = prompts, code = written.code, stderr = written.stderr }
    ]],
			{ note }
		)

		MiniTest.expect.equality(result.prompts, 2)
		MiniTest.expect.equality(result.code ~= 0, true)
		MiniTest.expect.equality(result.stderr:find("passphrases do not match", 1, true) ~= nil, true)
		MiniTest.expect.equality(vim.fn.filereadable(note), 0)
	end)

	it("keeps the passphrase out of the command it hands it over in", function()
		local encrypted = "/tmp/gpg_symmetric_argv.txt.gpg"
		local passphrase = "sym-pass"

		helpers.encrypt_symmetric_file(encrypted, "Hello world!", passphrase)

		local result = child.lua(
			[[
        local passphrase, encrypted = ...
        M.prompt_passphrase = function() return passphrase end

        local seen = {}
        local system = vim.system
        vim.system = function(cmd, opts, on_exit)
          table.insert(seen, { cmd = cmd, env = opts and opts.env })
          return system(cmd, opts, on_exit)
        end

        M.decrypt(encrypted):wait()

        -- The first call is gpg detecting the passphrase note, so pick the one
        -- that hands the passphrase to memo.
        local decrypt_call
        for _, call in ipairs(seen) do
          if vim.tbl_contains(call.cmd, "memo") then
            decrypt_call = call
          end
        end

        return {
          cmd = decrypt_call and decrypt_call.cmd or {},
          env = decrypt_call and vim.inspect(decrypt_call.env) or "",
        }
    ]],
			{ passphrase, encrypted }
		)

		MiniTest.expect.equality(
			result.cmd,
			{ "memo", "decrypt", encrypted, "--passphrase-env", "MEMO_NOTE_PASSPHRASE" }
		)
		-- The passphrase has to travel in the environment, not in the arguments.
		MiniTest.expect.equality(vim.tbl_contains(result.cmd, passphrase), false)
		MiniTest.expect.equality(result.env:find(passphrase, 1, true) ~= nil, true)
	end)

	it("keeps the caller's options when it hands the passphrase over", function()
		local encrypted = "/tmp/gpg_symmetric_opts.txt.gpg"
		local passphrase = "sym-pass"

		helpers.encrypt_symmetric_file(encrypted, "Hello world!", passphrase)

		local result = child.lua(
			[[
        local passphrase, encrypted = ...
        M.prompt_passphrase = function() return passphrase end

        return M.decrypt(encrypted, nil, { text = true }):wait()
    ]],
			{ passphrase, encrypted }
		)

		MiniTest.expect.equality(result.code, 0)
		-- Only the caller's `text` option turns stdout into a string.
		MiniTest.expect.equality(type(result.stdout), "string")
		MiniTest.expect.equality(vim.trim(result.stdout or ""), "Hello world!")
	end)

	it("reports the result through the callback when given one", function()
		local encrypted = "/tmp/gpg_callback.txt.gpg"
		helpers.create_gpg_key("mock@example.com")
		helpers.encrypt_file(encrypted, "Hello world!")

		child.lua(
			[[
        local encrypted = ...
        _G.called_with = nil

        M.decrypt(encrypted, nil, {}, function(obj)
          _G.called_with = obj.code
        end)
    ]],
			{ encrypted }
		)

		child.wait_until(function()
			return child.lua_get("_G.called_with ~= nil") == true
		end)

		MiniTest.expect.equality(child.lua_get("_G.called_with"), 0)
	end)

	it("asks once for a passphrase and keeps it in the buffer", function()
		local encrypted = "/tmp/gpg_symmetric_cache.txt.gpg"
		local passphrase = "sym-pass"

		helpers.encrypt_symmetric_file(encrypted, "Hello world!", passphrase)

		local result = child.lua(
			[[
        local passphrase, encrypted = ...
        local prompts = 0

        M.prompt_passphrase = function()
          prompts = prompts + 1
          return passphrase
        end

        local bufnr = vim.api.nvim_create_buf(true, false)

        -- The second read takes the passphrase the first one left in the buffer.
        local first = M.decrypt(encrypted, bufnr):wait()
        local second = M.decrypt(encrypted, bufnr):wait()

        return {
          prompts = prompts,
          cached = vim.b[bufnr].memo_symmetric_passphrase,
          codes = { first.code, second.code },
        }
    ]],
			{ passphrase, encrypted }
		)

		MiniTest.expect.equality(result, { prompts = 1, cached = passphrase, codes = { 0, 0 } })
	end)

	it("keeps nothing in the buffer when the passphrase prompt is dismissed", function()
		local encrypted = "/tmp/gpg_symmetric_dismissed.txt.gpg"

		helpers.encrypt_symmetric_file(encrypted, "Hello world!", "sym-pass")

		local result = child.lua(
			[[
        local encrypted = ...
        M.prompt_passphrase = function() return "" end

        local bufnr = vim.api.nvim_create_buf(true, false)

        return {
          is_nil = M.decrypt(encrypted, bufnr) == nil,
          cached = vim.b[bufnr].memo_symmetric_passphrase ~= nil,
        }
    ]],
			{ encrypted }
		)

		MiniTest.expect.equality(result, { is_nil = true, cached = false })
	end)

	it("forgets the passphrase when the buffer holding it is wiped", function()
		local encrypted = "/tmp/gpg_symmetric_wiped.txt.gpg"

		helpers.encrypt_symmetric_file(encrypted, "Hello world!", "sym-pass")

		local result = child.lua(
			[[
        local encrypted = ...
        M.prompt_passphrase = function() return "sym-pass" end

        local bufnr = vim.api.nvim_create_buf(true, false)
        M.decrypt(encrypted, bufnr):wait()
        local wipes = vim.api.nvim_get_autocmds({ event = "BufWipeout", buffer = bufnr })

        -- Wiping frees the buffer variables anyway, so what clears a passphrase
        -- early is the callback: running it shows what it clears.
        vim.api.nvim_exec_autocmds("BufWipeout", { buffer = bufnr })

        return {
          is_nil = vim.b[bufnr].memo_symmetric_passphrase == nil,
          wipes = #wipes,
        }
    ]],
			{ encrypted }
		)

		MiniTest.expect.equality(result, { is_nil = true, wipes = 1 })
	end)
end)
