local helpers = require("tests.helpers")
local child = MiniTest.new_child_neovim()

describe("core", function()
	local TEST_HOME = vim.fn.tempname()
	local TEST_GNUPGHOME = TEST_HOME .. "/.gnupg"

	before_each(function()
		vim.env.HOME = TEST_HOME
		vim.env.GNUPGHOME = TEST_HOME .. "/.gnupg"

		vim.fn.mkdir(TEST_HOME, "p")
		vim.fn.system({ "chmod", "700", TEST_GNUPGHOME })

		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})

		-- Load tested plugin
		child.lua([[ M = require('memo.core') ]])
	end)

	after_each(function()
		vim.fn.delete(TEST_HOME, "rf")
		child.stop()
		helpers.kill_gpg_agent()
	end)

	it("correctly encrypts from stdin", function()
		helpers.create_gpg_key("mock@example.com")

		local encrypted = TEST_HOME .. "/stdin_test.md.gpg"
		local test_lines = { "Hello World", "Line 2" }

		local result = child.lua(
			[[
        local args = {...}
        local lines = args[1]
        local target = args[2]

        return M.encrypt_from_stdin(target, lines)
    ]],
			{ test_lines, encrypted }
		)
		MiniTest.expect.equality(result.code, 0)

		local exists = child.fn.filereadable(encrypted)
		MiniTest.expect.equality(exists, 1)

		local lines = child.fn.readfile(encrypted)
		MiniTest.expect.equality(lines[1], "-----BEGIN PGP MESSAGE-----")
	end)

	it("correctly encrypts from stdin when gpg key has password", function()
		local password = "testpass"
		helpers.create_gpg_key("mock-password@example.com", password)

		local encrypted = TEST_HOME .. "/stdin_test.md.gpg"
		local test_lines = { "Hello World", "Line 2" }

		local result = child.lua(
			[[
        local args = {...}
        local lines = args[1]
        local target = args[2]
        local password = args[3]
        local utils = require("memo.utils")

        utils.prompt_passphrase = function()
          return password
        end

        return M.encrypt_from_stdin(target, lines)
    ]],
			{ test_lines, encrypted, password }
		)
		MiniTest.expect.equality(result.code, 0)

		local exists = child.fn.filereadable(encrypted)
		MiniTest.expect.equality(exists, 1)

		local lines = child.fn.readfile(encrypted)
		MiniTest.expect.equality(lines[1], "-----BEGIN PGP MESSAGE-----")
	end)

	it("fails encrypting - unsupported extension jpeg", function()
		helpers.create_gpg_key("mock@example.com")

		local encrypted = TEST_HOME .. "/stdin_test.jpg.gpg"
		local test_lines = { "Hello World", "Line 2" }

		local result = child.lua(
			[[
        local args = {...}
        local lines = args[1]
        local target = args[2]

        return M.encrypt_from_stdin(target, lines)
    ]],
			{ test_lines, encrypted }
		)
		MiniTest.expect.equality(result.code, 1)

		local exists = child.fn.filereadable(encrypted)
		MiniTest.expect.equality(exists, 0)
	end)

	it("correctly decrypts file", function()
		local plain = "/tmp/plain.txt"
		local encrypted = "/tmp/plain.txt.gpg"
		helpers.create_gpg_key("mock@example.com")

		local cmd = {
			"memo",
			"encrypt",
			encrypted,
			plain,
		}
		vim.system(cmd, { stdin = "Hello world!", text = true }):wait()

		local result = child.lua(string.format([[ return M.decrypt_to_stdout(%q) ]], encrypted))

		MiniTest.expect.equality(result.code, 0)
		MiniTest.expect.equality(result.stdout, "Hello world!")
	end)

	it("correctly decrypts file when key has password", function()
		local plain = "/tmp/plain.txt"
		local encrypted = "/tmp/plain.txt.gpg"

		local password = "testpass"
		helpers.create_gpg_key("mock-password@example.com", password)

		helpers.cache_gpg_password(password)

		local cmd = {
			"memo",
			"encrypt",
			encrypted,
			plain,
		}
		vim.system(cmd, { stdin = "Hello world!", text = true }):wait()

		-- Ensures gpg password will not be cached anymore for our test case
		helpers.kill_gpg_agent()

		local result = child.lua(string.format(
			[[
        local utils = require("memo.utils")

        utils.prompt_passphrase = function()
          return %q
        end

        return M.decrypt_to_stdout(%q)
    ]],
			password,
			encrypted
		))

		MiniTest.expect.equality(result.stderr, "")
		MiniTest.expect.equality(result.code, 0)
		MiniTest.expect.equality(result.stdout, "Hello world!")
	end)

	it("fails to decrypt file not found", function()
		helpers.create_gpg_key("mock@example.com")
		local result = child.lua([[ return M.decrypt_to_stdout("/tmp/does_not_exist.gpg") ]])

		MiniTest.expect.equality(result.code, 1)
		MiniTest.expect.equality(result.stderr, "")
	end)
end)
