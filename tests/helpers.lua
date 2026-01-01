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

function M.setup_test_env(home, notes_dir)
	vim.env.HOME = home
	vim.env.GNUPGHOME = home .. "/.gnupg"

	vim.fn.mkdir(home, "p")
	vim.fn.mkdir(notes_dir, "p")
	vim.fn.mkdir(home .. "/.gnupg", "p")
	vim.fn.system({ "chmod", "700", home .. "/.gnupg" })
end

--- @param child  unknown
--- @param event_type MemoEvent One of events.MemoEvent
function M.wait_for_event(child, event_type)
	child.lua(string.format(
		[[
        _G.memo_done = false
        vim.api.nvim_create_autocmd("User", {
            pattern = %q,
            once = true,
            callback = function() _G.memo_done = true end,
        })
    ]],
		event_type
	))
	child.lua([[vim.wait(5000, function() return _G.memo_done end)]])
end

function M.wait_until(child, expr, timeout)
	timeout = timeout or 5000
	local start = child.loop.now()

	while child.loop.now() - start < timeout do
		child.lua_get(expr)
		child.loop.sleep(50) -- small sleep to allow child to process scheduled callbacks
	end

	error("wait_until timed out: " .. expr)
end

function M.new_child_neovim()
	local child = MiniTest.new_child_neovim()

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

	function child.wait_for_event(event_type, timeout)
		child.api.nvim_create_autocmd("User", {
			pattern = event_type,
			once = true,
			callback = function()
				child.done = true
			end,
		})

		-- 2. Use your working polling loop in the parent
		local max = timeout or 5000
		local inc = 100

		for _ = 0, max, inc do
			-- Check if the child's global variable flipped to true
			if child.done == true then
				return -- Success!
			else
				--- @diagnostic disable-next-line: undefined-field
				vim.uv.sleep(inc)
			end
		end

		-- 3. If we reach here, it timed out
		error(
			string.format(
				"Timed out waiting for event: %q after %d ms\n\nChild Messages:\n%s",
				event_type,
				max,
				tostring(child.cmd_capture("messages"))
			)
		)
	end

	return child
end

return M
