local M = {}

--- How long an unlocked answer is trusted: ten minutes, gpg-agent's own default.
local UNLOCKED_TTL_MS = 600000

--- Cache key used for the default key.
local DEFAULT_KEY = "\0default"

--- Turns an optional key id into its cache key, folding the default key's
--- missing or empty id onto a sentinel.
--- @param id string?
--- @return string
local function key_id(id)
	return id and id ~= "" and id or DEFAULT_KEY
end

--- A small cache of what gpg-agent already knows: a note's recipients and
--- which keys are unlocked. Nothing secret; gpg-agent stays the real gate.
--- @class MemoGpgCache
--- @field packet_cache table<string, { signature: string, value: any }>
--- @field unlocked_keys table<string, number>
--- @field now fun(): number
local GpgCache = {}

GpgCache.__index = GpgCache

--- Options of `M.new`. Injectable so tests need no real clock.
--- @class MemoGpgCacheOpts
--- @field now? fun(): number

--- @param opts? MemoGpgCacheOpts
--- @return MemoGpgCache
function M.new(opts)
	opts = opts or {}

	local self = setmetatable({}, GpgCache)

	self.packet_cache = {}
	self.unlocked_keys = {}
	-- Read the global lazily, so tests can replace `vim.uv.now`.
	self.now = opts.now or function()
		return vim.uv.now()
	end

	return self
end

--- A note's packets, computed only when new or the file changed. A missing file
--- is never cached. `compute` may return a second value; `false` keeps it out
--- of the cache, so a failed read is retried.
--- @param path string
--- @param compute fun(path: string): any, boolean?
--- @return any
function GpgCache:packets(path, compute)
	local signature = require("memo.utils").file_signature(path)

	if signature then
		local cached = self.packet_cache[path]

		if cached and cached.signature == signature then
			return cached.value
		end
	end

	local value, cacheable = compute(path)

	if signature and cacheable ~= false then
		self.packet_cache[path] = { signature = signature, value = value }
	end

	return value
end

--- Whether gpg-agent holds a key, probing only when there is no fresh answer.
--- A "no" is never cached.
--- @param id string?
--- @param probe fun(id: string?): boolean
--- @return boolean
function GpgCache:key_unlocked(id, probe)
	local at = self.unlocked_keys[key_id(id)]

	if at and (self.now() - at) < UNLOCKED_TTL_MS then
		return true
	end

	self.unlocked_keys[key_id(id)] = nil

	if not probe(id) then
		return false
	end

	self:mark_key_unlocked(id)

	return true
end

--- Records that gpg-agent holds a key.
--- @param id string?
function GpgCache:mark_key_unlocked(id)
	self.unlocked_keys[key_id(id)] = self.now()
end

--- Forgets a key's unlock, so the next check probes again.
--- @param id string?
function GpgCache:forget_key_unlocked(id)
	self.unlocked_keys[key_id(id)] = nil
end

--- Forgets every given key's unlock, plus the default key.
--- @param keyids string[]
function GpgCache:forget_unlocked_keys(keyids)
	for _, id in ipairs(keyids) do
		self:forget_key_unlocked(id)
	end

	self:forget_key_unlocked()
end

return M
