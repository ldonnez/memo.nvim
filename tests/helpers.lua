local M = {}

function M.write_file(path, content)
	local f = io.open(path, "w")

	if f == nil then
		return
	end

	f:write(content)
	f:close()
end

--- @param path string
--- @param content string
--- @param opts vim.SystemOpts?
--- @return vim.SystemCompleted
function M.encrypt_file(path, content, opts)
	local cmd = {
		"memo",
		"encrypt",
		path,
	}

	return vim.system(cmd, vim.tbl_deep_extend("force", { stdin = content }, opts or {})):wait()
end

--- @param path string
--- @return vim.SystemCompleted
function M.decrypt_file(path)
	local cmd = {
		"memo",
		"decrypt",
		path,
	}

	return vim.system(cmd):wait()
end

local function determine_gen_key_string(keyid, passphrase)
	local lines = {}

	if not passphrase or passphrase == "" then
		table.insert(lines, "%no-protection")
	end

	table.insert(lines, "Key-Type: RSA")
	table.insert(lines, "Key-Length: 3072")
	table.insert(lines, "Name-Real: Mock Test Key")
	table.insert(lines, "Name-Email: " .. keyid)
	table.insert(lines, "Expire-Date: 0")

	if passphrase and passphrase ~= "" then
		table.insert(lines, "Passphrase: " .. passphrase)
	end

	table.insert(lines, "%commit")

	return table.concat(lines, "\n")
end

function M.create_gpg_key(keyid, passphrase)
	local existing = vim.system({ "gpg", "--with-colons", "--list-secret-keys", keyid }, { text = true }):wait()

	if existing.code == 0 and existing.stdout then
		local key = existing.stdout:match("\nfpr:::::::::([%w%d]+):")
		return key and key:sub(-16)
	end

	local batch_content = determine_gen_key_string(keyid, passphrase)
	local batch_file = vim.fn.tempname()

	vim.fn.writefile(vim.split(batch_content, "\n"), batch_file)

	local obj = vim.system({
		"gpg",
		"--batch",
		"--status-fd",
		"1",
		"--pinentry-mode",
		"loopback",
		"--gen-key",
		batch_file,
	}, { text = true }):wait()

	if obj.code ~= 0 then
		print("GPG Error: " .. (obj.stderr or "Unknown error"))
		return
	end

	os.remove(batch_file)

	if obj.stdout then
		local fingerprint = obj.stdout:match("KEY_CREATED [^ ]+ ([%w%d]+)")
		if fingerprint then
			return fingerprint:sub(-16) -- Returns the 16-char Long ID (e.g., DC66CDB28DC727BC)
		end
	end
end

function M.cache_gpg_password(password)
	local cmd = {
		"gpg",
		"--batch",
		"--yes",
		"--no-tty",
		"--pinentry-mode=loopback",
		"--passphrase",
		password,
		"--sign",
	}

	return vim.system(cmd):wait()
end

function M.kill_gpg_agent()
	local cmd = {
		"gpgconf",
		"--kill",
		"gpg-agent",
	}

	return vim.system(cmd):wait()
end

function M.setup_test_env()
	local home = vim.fn.resolve("/tmp/memo.nvim")
	local notes_dir = home .. "/notes"

	vim.env.HOME = home
	vim.env.GNUPGHOME = home .. "/.gnupg"
	vim.env.NOTES_DIR = home .. "/notes"

	vim.fn.mkdir(home, "p")
	vim.fn.mkdir(notes_dir, "p")
	vim.fn.mkdir(home .. "/.gnupg", "p")
	vim.fn.system({ "chmod", "700", home .. "/.gnupg" })
end

function M.cleanup_test_env()
	vim.fn.delete(vim.env.HOME, "rf")
end

function M.new_child_neovim()
	local child = MiniTest.new_child_neovim()

	--- @param condition fun()
	--- @param timeout? integer
	--- @param interval? integer
	child.wait_until = function(condition, timeout, interval)
		local max = timeout or 5000
		local inc = interval or 100
		for _ = 0, max, inc do
			if condition() then
				return
			else
				--- @diagnostic disable-next-line: undefined-field
				vim.uv.sleep(inc)
			end
		end

		error(
			string.format(
				"Timed out waiting for condition after %d ms\n\n%s\n\n",
				max,
				tostring(child.cmd_capture("messages"))
			)
		)
	end

	child.sleep = function(ms)
		--- @diagnostic disable-next-line: undefined-field
		vim.uv.sleep(math.max(ms, 1))
	end

	return child
end

return M
