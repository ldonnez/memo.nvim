local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

describe("gpg", function()
	local TEST_HOME = vim.fn.tempname()
	local NOTES_DIR = TEST_HOME .. "/notes"

	before_each(function()
		helpers.setup_test_env(TEST_HOME, NOTES_DIR)

		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		-- Load tested plugin
		child.lua([[ M = require('memo.gpg') ]])
	end)

	after_each(function()
		vim.fn.delete(TEST_HOME, "rf")
		child.stop()
		helpers.kill_gpg_agent()
	end)

	it("correctly asks password of default key without target_path", function()
		local password = "testpassword"
		helpers.create_gpg_key("mock-password@example.com", password)

		local result = child.lua(string.format(
			[[
        local gpg = require("memo.gpg")

        gpg.prompt_passphrase = function(label)
          captured_prompt = label
          return %q
        end

        return M.get_gpg_passphrase()
    ]],
			password
		))

		MiniTest.expect.equality(result, true)
	end)

	it("does not cache password when its wrong", function()
		local password = "testpassword"
		local keyid = "mock-wrong-password@example.com"
		helpers.create_gpg_key(keyid, password)

		local result = child.lua(string.format(
			[[
        local gpg = require("memo.gpg")

        gpg.prompt_passphrase = function(label)
          captured_prompt = label
          return %q
        end

        return M.get_gpg_passphrase()
    ]],
			"wrong-password"
		))

		MiniTest.expect.equality(result, false)
	end)

	it("gets correct gpg key from encrypted file", function()
		local plain = "/tmp/plain.txt"
		local encrypted = "/tmp/plain.txt.gpg"
		local key_id = helpers.create_gpg_key("mock@example.com")

		local cmd = {
			"memo",
			"encrypt",
			encrypted,
			plain,
		}
		vim.system(cmd, { stdin = "Hello world!", text = true }):wait()

		local result = child.lua(string.format([[ return M.get_file_key_ids(%q) ]], encrypted))

		MiniTest.expect.equality(result, { key_id })
	end)

	it("does not get key from file when its not encrypted", function()
		local encrypted = "/tmp/plain.txt.gpg"
		helpers.create_gpg_key("mock@example.com")
		helpers.write_file(encrypted, "Hello World")
		local result = child.lua(string.format([[ return M.get_file_key_ids(%q) ]], encrypted))

		MiniTest.expect.equality(result, {})
	end)

	it("detects multiple key IDs in a single encrypted file", function()
		local encrypted = "/tmp/multi.txt.gpg"

		local key1 = "user1@example.com"
		local key2 = "user2@example.com"

		local id1 = helpers.create_gpg_key(key1, "pass1")
		local id2 = helpers.create_gpg_key(key2, "pass2")

		local cmd = {
			"memo",
			"encrypt",
			encrypted,
		}
		vim.system(cmd, { env = { GPG_RECIPIENTS = key1 .. "," .. key2 }, stdin = "Hello world!", text = true }):wait()

		local result = child.lua(string.format([[ return M.get_file_key_ids(%q) ]], encrypted))

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

		local cmd = {
			"memo",
			"encrypt",
			encrypted,
		}
		vim.system(cmd, { env = { GPG_RECIPIENTS = my_id .. "," .. foreign_id }, stdin = "Hello world!", text = true })
			:wait()

		-- It should ask for my_id, NOT foreign_id
		local result_id = child.lua(string.format(
			[[
        local captured_prompt = ""

        require("memo.gpg").prompt_passphrase = function(label)
            captured_prompt = label
            return %q
        end

        M.get_gpg_passphrase(%q)
        return captured_prompt
       ]],
			password,
			encrypted
		))

		MiniTest.expect.equality(result_id, "key: " .. my_id)
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

	it("correctly notifies when cmd returns errors", function()
		local result = child.lua([[
        M.get_gpg_passphrase = function() return true end

        local cmd = { "sh", "-c", "echo 'forced error' >&2; exit 1" }
        return M.exec_with_gpg_auth(cmd)
    ]])

		MiniTest.expect.equality(result.code, 1)

		local messages = child.cmd_capture("messages")
		MiniTest.expect.equality(messages, "forced error\n")
	end)
end)
