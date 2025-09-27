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

	it("correctly asks password and caches it", function()
		local password = "testpassword"
		helpers.create_gpg_key("mock-password@example.com", password)

		local result = child.lua(string.format(
			[[
        local utils = require("memo.utils")

        utils.prompt_passphrase = function()
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
        local utils = require("memo.utils")

        utils.prompt_passphrase = function()
          return %q
        end

        return M.get_gpg_passphrase()
    ]],
			"wrong-password"
		))

		MiniTest.expect.equality(result, false)
	end)

	it("correctly encrypts file", function()
		helpers.create_gpg_key("mock@example.com")

		local input = child.fn.tempname() .. ".md"
		local encrypted = input .. ".gpg"

		child.fn.writefile({ "hello world" }, input)

		-- Call your function inside child neovim
		local result = child.lua(string.format([[ return M.encrypt_file(%q, %q) ]], input, encrypted))

		MiniTest.expect.equality(result.code, 0)

		-- Validate that memo actually encrypted it (binary header check)
		local head = child.fn.readfile(encrypted)[1]
		MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")
	end)

	it("correctly encrypts file when key has password", function()
		local password = "testpass"
		helpers.create_gpg_key("mock-password@example.com", password)

		local input = child.fn.tempname() .. ".md"
		local encrypted = input .. ".gpg"

		child.fn.writefile({ "hello world" }, input)

		local result = child.lua(string.format(
			[[
        local utils = require("memo.utils")

        utils.prompt_passphrase = function()
          return %q
        end

        return M.encrypt_file(%q, %q)
    ]],
			password,
			input,
			encrypted
		))

		MiniTest.expect.equality(result.code, 0)

		-- Validate that memo actually encrypted it (binary header check)
		local head = child.fn.readfile(encrypted)[1]
		MiniTest.expect.equality(head, "-----BEGIN PGP MESSAGE-----")
	end)

	it("fails encrypting - unsupported extension jpeg", function()
		helpers.create_gpg_key("mock@example.com")
		local input = child.fn.tempname() .. ".jpeg"
		local encrypted = input .. ".gpg"

		child.fn.writefile({ "hello world" }, input)

		-- Call your function inside child neovim
		local result = child.lua(string.format([[ return M.encrypt_file(%q, %q) ]], input, encrypted))

		MiniTest.expect.equality(result.code, 1)
	end)

	it("correctly decrypts file", function()
		local plain = "/tmp/plain.txt"
		local encrypted = "/tmp/plain.txt.gpg"
		helpers.create_gpg_key("mock@example.com")

		helpers.write_file(plain, "Hello world!")

		local cmd = {
			"memo",
			"encrypt",
			plain,
			encrypted,
		}
		vim.system(cmd, { stdin = "test", text = true }):wait()

		local result = child.lua(string.format([[ return M.decrypt_file(%q) ]], encrypted))

		MiniTest.expect.equality(result.code, 0)
		MiniTest.expect.equality(result.stdout, "Hello world!")
	end)

	it("correctly decrypts file when key has password", function()
		local plain = "/tmp/plain.txt"
		local encrypted = "/tmp/plain.txt.gpg"

		local password = "testpass"
		helpers.create_gpg_key("mock-password@example.com", password)

		helpers.write_file(plain, "Hello world!")
		helpers.cache_gpg_password(password)

		local cmd = {
			"memo",
			"encrypt",
			plain,
			encrypted,
		}
		vim.system(cmd, { stdin = "test", text = true }):wait()

		-- Ensures gpg password will not be cached anymore for our test case
		helpers.kill_gpg_agent()

		local result = child.lua(string.format(
			[[
        local utils = require("memo.utils")

        utils.prompt_passphrase = function()
          return %q
        end

        return M.decrypt_file(%q)
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
		local result = child.lua([[ return M.decrypt_file("/tmp/does_not_exist.gpg") ]])

		MiniTest.expect.equality(result.code, 1)
		MiniTest.expect.equality(result.stderr, "")
	end)

	it("encrypts buffer", function()
		helpers.create_gpg_key("mock@example.com")

		local result = child.lua([[
    -- create a test buffer
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(bufnr)

    -- write content
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "secret", "data" })
    vim.bo.modified = true

    local target = vim.fn.tempname() .. ".gpg"

    -- run function
    M.encrypt_from_buffer(target)

    return {
      modified = vim.bo.modified,
      exists = vim.fn.filereadable(target) == 1,
    }
  ]])

		MiniTest.expect.equality(result.modified, false)
		MiniTest.expect.equality(result.exists, true)
	end)

	it("load decrypted buffer", function()
		local result = child.lua([[
	  local bufnr = vim.api.nvim_create_buf(true, false)

	  vim.api.nvim_set_current_buf(bufnr)

	  local lines = { "hello", "world" }
	  local meta_key = "gpg_original"
	  local original = "/tmp/test.md.gpg"

	  M.load_decrypted(bufnr, original, lines, meta_key)

	  return {
	    name = vim.api.nvim_buf_get_name(bufnr),
	    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
	    meta = vim.b[bufnr][meta_key],
	    modified = vim.api.nvim_get_option_value("modified", { buf = bufnr }),
	    ft = vim.bo[bufnr].filetype,
	  }
	]])

		MiniTest.expect.equality(result.name, vim.fn.resolve("/tmp/test.md"))
		MiniTest.expect.equality(result.lines, { "hello", "world" })
		MiniTest.expect.equality(result.meta, "/tmp/test.md.gpg")
		MiniTest.expect.equality(result.modified, false)
		MiniTest.expect.equality(result.ft, "markdown")
	end)
end)
