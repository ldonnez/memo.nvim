local M = {}

function M.write_file(path, content)
	local f = io.open(path, "w")

	if f == nil then
		return
	end

	f:write(content)
	f:close()
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
	local check = vim.system({ "gpg", "--list-secret-keys", keyid }):wait()
	if check.code == 0 then
		print("Key already exists.")
		return
	end

	local batch_content = determine_gen_key_string(keyid, passphrase)
	local batch_file = vim.fn.tempname()

	vim.fn.writefile(vim.split(batch_content, "\n"), batch_file)

	local obj = vim.system({
		"gpg",
		"--batch",
		"--pinentry-mode",
		"loopback",
		"--gen-key",
		batch_file,
	}):wait()

	if obj.code ~= 0 then
		print("GPG Error: " .. (obj.stderr or "Unknown error"))
	end

	os.remove(batch_file)
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

return M
