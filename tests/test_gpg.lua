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

        return M.get_gpg_passphrase()
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

        return M.get_gpg_passphrase()
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

        M.get_gpg_passphrase(encrypted)
        return captured_prompt
       ]],
			{ password, encrypted }
		)

		MiniTest.expect.equality(result_id, "Mock Test Key <me@example.com> (" .. my_id .. ")")
	end)

	it("aborts execution when passphrase authentication fails", function()
		local result = child.lua([[
       M.get_gpg_passphrase = function() return false end

       return M.exec_with_gpg_auth({ "ls", "dummy.gpg" })
        ]])

		MiniTest.expect.equality(result, vim.NIL)
	end)

	it("returns command output on successful auth and execution", function()
		local result = child.lua([[
       M.get_gpg_passphrase = function() return true end

       return M.exec_with_gpg_auth({ "echo", "success_test" })
        ]])

		MiniTest.expect.equality(result.code, 0)
	end)

	it("returns the failing result without notifying; callers own error reporting", function()
		local result = child.lua([[
        M.get_gpg_passphrase = function() return true end

        local cmd = { "sh", "-c", "echo 'forced error' >&2; exit 1" }
        return M.exec_with_gpg_auth(cmd)
    ]])

		MiniTest.expect.equality(result.code, 1)
		MiniTest.expect.equality(result.stderr, "forced error\n")

		MiniTest.expect.equality(child.cmd_capture("messages"), "")
	end)

	it("hands the passphrase to whatever command it is given", function()
		local passphrase = "sym-pass"

		local result = child.lua(
			[[
        local passphrase = ...
        local cmd = { "sh", "-c", 'printf %s "$' .. M.PASSPHRASE_ENV .. '"' }

        return M.exec_with_passphrase(cmd, passphrase, { text = true }):wait()
    ]],
			{ passphrase }
		)

		MiniTest.expect.equality(result.code, 0)
		MiniTest.expect.equality(result.stdout, passphrase)
	end)

	it("names the environment variable it hands the passphrase over in", function()
		local result = child.lua_get("M.PASSPHRASE_ENV")

		MiniTest.expect.equality(result, "MEMO_NOTE_PASSPHRASE")
	end)

	it("keeps the caller's options when it adds the passphrase", function()
		local result = child.lua([[
        return M.exec_with_passphrase({ "cat" }, "any-pass", { stdin = { "payload" }, text = true }):wait()
    ]])

		MiniTest.expect.equality(result.code, 0)
		-- vim.system sends stdin lines with a trailing newline.
		MiniTest.expect.equality(result.stdout, "payload\n")
	end)

	it("reports the result through the callback when given one", function()
		child.lua([[
        _G.called_with = nil

        M.exec_with_passphrase({ "sh", "-c", "echo done" }, "pass", {}, function(obj)
          _G.called_with = obj.code
        end)
    ]])

		child.wait_until(function()
			return child.lua_get("_G.called_with ~= nil") == true
		end)

		MiniTest.expect.equality(child.lua_get("_G.called_with"), 0)
	end)

	it("counts a buffer that holds a passphrase as symmetric without reading the file", function()
		local result = child.lua([[
        local bufnr = vim.api.nvim_create_buf(true, false)
        vim.b[bufnr].memo_symmetric_passphrase = "pass"

        -- A plain file, so only the buffer can be telling us it is symmetric.
        return M.is_symmetric("/tmp/memo-test-not-a-note.gpg", bufnr)
    ]])

		MiniTest.expect.equality(result, true)
	end)

	it("asks once for a passphrase and keeps it in the buffer", function()
		local passphrase = "sym-pass"

		local result = child.lua(
			[[
        local passphrase = ...
        local prompts = 0

        M.prompt_passphrase = function()
          prompts = prompts + 1
          return passphrase
        end

        local bufnr = vim.api.nvim_create_buf(true, false)
        local asked = M.get_symmetric_passphrase("/tmp/memo-test-note.md.gpg", bufnr)
        local cached = M.get_symmetric_passphrase("/tmp/memo-test-note.md.gpg", bufnr)

        return { asked, cached, prompts, vim.b[bufnr].memo_symmetric_passphrase }
    ]],
			{ passphrase }
		)

		MiniTest.expect.equality(result, { passphrase, passphrase, 1, passphrase })
	end)

	it("keeps nothing in the buffer when the passphrase prompt is dismissed", function()
		local result = child.lua([[
        M.prompt_passphrase = function() return "" end

        local bufnr = vim.api.nvim_create_buf(true, false)
        local asked = M.get_symmetric_passphrase("/tmp/memo-test-note.md.gpg", bufnr)

        return {
          is_nil = asked == nil,
          cached = vim.b[bufnr].memo_symmetric_passphrase ~= nil,
        }
    ]])

		MiniTest.expect.equality(result, { is_nil = true, cached = false })
	end)
end)
