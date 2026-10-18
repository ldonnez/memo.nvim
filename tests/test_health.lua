local helpers = require("tests.helpers")
local child = helpers.new_child_neovim()

local NOTES_DIR = "/tmp/memo-health-notes"

describe("health", function()
	before_each(function()
		child.restart({
			"-u",
			"scripts/minimal_init.lua",
		})
	end)

	after_each(function()
		child.stop()
	end)

	---Runs `:checkhealth memo` against `notes_dir` and returns its report. The
	---plugin is sourced at startup, so the config is refreshed afterwards.
	---@param notes_dir string
	---@return string
	local function checkhealth(notes_dir)
		child.lua(
			[[
        vim.g.memo_notes_dir = ...
        require("memo.config").setup()
      ]],
			{ notes_dir }
		)

		child.lua([[ vim.cmd("checkhealth memo") ]])

		return child.lua_get([[ table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") ]])
	end

	---Puts a fake `memo` that prints `version` at the front of the child PATH.
	---@param version string
	local function fake_memo(version)
		local bin_dir = "/tmp/memo-health-fakebin"
		helpers.write_fake_binary(bin_dir, "memo", version)
		child.lua([[ vim.env.PATH = ... .. ":" .. vim.env.PATH ]], { bin_dir })
	end

	it("reports a healthy install", function()
		vim.fn.mkdir(NOTES_DIR, "p")

		local report = checkhealth(NOTES_DIR)

		MiniTest.expect.equality(report:find("OK gpg binary is installed", 1, true) ~= nil, true)
		MiniTest.expect.equality(report:find("OK memo v", 1, true) ~= nil, true)
		MiniTest.expect.equality(report:find("OK Notes directory exists: " .. NOTES_DIR, 1, true) ~= nil, true)
	end)

	it("warns when the notes directory is missing", function()
		local missing = NOTES_DIR .. "-missing"

		local report = checkhealth(missing)

		MiniTest.expect.equality(report:find("Notes directory not found: " .. missing, 1, true) ~= nil, true)
	end)

	it("warns on a malformed memo version", function()
		fake_memo("not-a-version")

		vim.fn.mkdir(NOTES_DIR, "p")

		local report = checkhealth(NOTES_DIR)

		MiniTest.expect.equality(report:find("could not parse memo version", 1, true) ~= nil, true)
	end)
end)
