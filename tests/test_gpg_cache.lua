local helpers = require("tests.helpers")

describe("gpg_cache", function()
	local GpgCache = require("memo.gpg_cache")

	--- How long an unlocked answer is trusted, mirrored from the module.
	local TTL_MS = 600000

	local dir = ""
	local clock = 0

	before_each(function()
		dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		clock = 1000000
	end)

	after_each(function()
		vim.fn.delete(dir, "rf")
	end)

	--- @param name string
	--- @return string
	local function path(name)
		return dir .. "/" .. name
	end

	--- A cache on a frozen clock, so no real time takes part.
	--- @return MemoGpgCache
	local function frozen()
		return GpgCache.new({
			now = function()
				return clock
			end,
		})
	end

	describe("packets", function()
		--- Bumps on `bump`, reads on `count`.
		--- @return fun(): integer
		--- @return fun(): integer
		local function counter()
			local n = 0

			return function()
				n = n + 1
				return n
			end, function()
				return n
			end
		end

		it("computes once and serves the rest from the cache", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "body")

			local cache = frozen()
			local bump = counter()
			local compute = function()
				return { key_ids = { "A" }, call = bump() }
			end

			local first = cache:packets(note, compute)
			local second = cache:packets(note, compute)

			MiniTest.expect.equality(first.call, 1)
			MiniTest.expect.equality(rawequal(first, second), true)
		end)

		it("recomputes once the file is rewritten", function()
			local note = path("note.md.asc")

			local cache = frozen()
			local bump, count = counter()
			local compute = function()
				return bump()
			end

			helpers.write_file(note, "body")
			cache:packets(note, compute)
			local after_first = count()

			helpers.write_file(note, "a deliberately longer body")
			cache:packets(note, compute)

			MiniTest.expect.equality(after_first, 1)
			MiniTest.expect.equality(count(), 2)
		end)

		it("never caches a file that is not there", function()
			local cache = frozen()
			local bump, count = counter()
			local compute = function()
				return bump()
			end

			cache:packets(path("missing.md.asc"), compute)
			cache:packets(path("missing.md.asc"), compute)

			MiniTest.expect.equality(count(), 2)
		end)

		it("does not keep a result that compute declines to cache", function()
			local note = path("note.md.asc")
			helpers.write_file(note, "body")

			local cache = frozen()
			local bump, count = counter()
			local compute = function()
				bump()
				return { key_ids = {} }, false
			end

			local first = cache:packets(note, compute)
			cache:packets(note, compute)

			MiniTest.expect.equality(first.key_ids, {})
			MiniTest.expect.equality(count(), 2)
		end)
	end)

	describe("key_unlocked", function()
		--- @param answer boolean
		--- @return fun(): boolean
		--- @return fun(): integer
		local function probe_counting(answer)
			local probes = 0

			return function()
				probes = probes + 1
				return answer
			end, function()
				return probes
			end
		end

		it("probes once and trusts the yes until the TTL is up", function()
			local cache = frozen()
			local probe, probes = probe_counting(true)

			cache:key_unlocked(nil, probe)
			cache:key_unlocked(nil, probe)
			MiniTest.expect.equality(probes(), 1)

			clock = clock + TTL_MS - 1
			cache:key_unlocked(nil, probe)
			MiniTest.expect.equality(probes(), 1)

			clock = clock + 2
			cache:key_unlocked(nil, probe)
			MiniTest.expect.equality(probes(), 2)
		end)

		it("never trusts a no", function()
			local cache = frozen()
			local probe, probes = probe_counting(false)

			MiniTest.expect.equality(cache:key_unlocked("K", probe), false)
			MiniTest.expect.equality(cache:key_unlocked("K", probe), false)
			MiniTest.expect.equality(probes(), 2)
		end)

		it("expires exactly when the TTL is reached", function()
			local cache = frozen()
			local probe, probes = probe_counting(true)

			cache:key_unlocked(nil, probe)
			clock = clock + TTL_MS
			cache:key_unlocked(nil, probe)

			MiniTest.expect.equality(probes(), 2)
		end)

		it("treats an empty key id as the default key", function()
			local cache = frozen()
			local probe, probes = probe_counting(true)

			cache:mark_key_unlocked("")

			MiniTest.expect.equality(cache:key_unlocked(nil, probe), true)
			MiniTest.expect.equality(probes(), 0)
		end)

		it("keeps each key apart", function()
			local cache = frozen()
			local seen = {}
			local probe = function(id)
				seen[id] = (seen[id] or 0) + 1
				return true
			end

			cache:key_unlocked("A", probe)
			cache:key_unlocked("B", probe)
			cache:key_unlocked("A", probe)

			MiniTest.expect.equality(seen.A, 1)
			MiniTest.expect.equality(seen.B, 1)
		end)

		it("trusts a key marked unlocked without probing", function()
			local cache = frozen()
			local probe, probes = probe_counting(false)

			cache:mark_key_unlocked("K")

			MiniTest.expect.equality(cache:key_unlocked("K", probe), true)
			MiniTest.expect.equality(probes(), 0)
		end)

		it("probes again once a key is forgotten", function()
			local cache = frozen()
			local probe, probes = probe_counting(true)

			cache:key_unlocked("K", probe)
			cache:key_unlocked("K", probe)
			MiniTest.expect.equality(probes(), 1)

			cache:forget_key_unlocked("K")
			cache:key_unlocked("K", probe)

			MiniTest.expect.equality(probes(), 2)
		end)

		it("forgets the given keys and the default one", function()
			local cache = frozen()
			local probe, probes = probe_counting(true)

			cache:key_unlocked(nil, probe)
			cache:key_unlocked("A", probe)
			cache:key_unlocked("B", probe)
			MiniTest.expect.equality(probes(), 3)

			cache:forget_unlocked_keys({ "A", "B" })

			cache:key_unlocked(nil, probe)
			cache:key_unlocked("A", probe)
			cache:key_unlocked("B", probe)

			MiniTest.expect.equality(probes(), 6)
		end)
	end)
end)
