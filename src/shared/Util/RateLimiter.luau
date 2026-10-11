--!strict
--[[
	Token bucket per key (usually player UserId + channel). Used to throttle RemoteEvents.
	`now` is injectable so the logic is testable offline.
]]

export type RateLimiter = {
	Allow: (self: RateLimiter, key: any, now: number) -> boolean,
	Forget: (self: RateLimiter, key: any) -> (),
	_capacity: number,
	_refillPerSecond: number,
	_buckets: { [any]: { tokens: number, stamp: number } },
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	local self = setmetatable({
		_capacity = capacity,
		_refillPerSecond = refillPerSecond,
		_buckets = {},
	}, RateLimiter)
	return (self :: any) :: RateLimiter
end

function RateLimiter.Allow(self: RateLimiter, key: any, now: number): boolean
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { tokens = self._capacity, stamp = now }
		self._buckets[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.stamp)
	bucket.tokens = math.min(self._capacity, bucket.tokens + elapsed * self._refillPerSecond)
	bucket.stamp = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter.Forget(self: RateLimiter, key: any)
	self._buckets[key] = nil
end

return RateLimiter
