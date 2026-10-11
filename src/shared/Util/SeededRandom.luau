--!strict
--[[
	Deterministic PRNG (mulberry32) so a session seed reproduces the same run in Studio,
	on live servers and in the offline test runner (which has no Roblox `Random`).
]]

export type SeededRandom = {
	seed: number,
	NextNumber: (self: SeededRandom, min: number?, max: number?) -> number,
	NextInteger: (self: SeededRandom, min: number, max: number) -> number,
	Chance: (self: SeededRandom, probability: number) -> boolean,
	Pick: <T>(self: SeededRandom, list: { T }) -> T,
	Shuffle: <T>(self: SeededRandom, list: { T }) -> { T },
	WeightedPick: <T>(self: SeededRandom, list: { T }, weightOf: (T) -> number) -> T?,
	Fork: (self: SeededRandom, salt: string) -> SeededRandom,
	_state: number,
}

local SeededRandom = {}
SeededRandom.__index = SeededRandom

local function hashString(text: string): number
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		-- FNV-1a multiply, kept in 32 bits.
		h = (h * 16777619) % 4294967296
	end
	return h
end

function SeededRandom.new(seed: number): SeededRandom
	local self = setmetatable({ seed = seed, _state = math.floor(seed) % 4294967296 }, SeededRandom)
	return (self :: any) :: SeededRandom
end

local function nextUint(self: SeededRandom): number
	self._state = (self._state + 0x6D2B79F5) % 4294967296
	local t = self._state
	-- 32-bit multiply emulation: split into 16-bit halves to stay exact in doubles.
	local function mul32(a: number, b: number): number
		local aLo, aHi = a % 65536, math.floor(a / 65536)
		local lo = aLo * b
		local hi = (aHi * b) % 65536
		return (lo + hi * 65536) % 4294967296
	end
	t = mul32(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
	t = bit32.bxor(t, (t + mul32(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % 4294967296)
	return bit32.bxor(t, bit32.rshift(t, 14))
end

function SeededRandom.NextNumber(self: SeededRandom, min: number?, max: number?): number
	local unit = nextUint(self) / 4294967296
	local lo = min or 0
	local hi = max or 1
	return lo + (hi - lo) * unit
end

function SeededRandom.NextInteger(self: SeededRandom, min: number, max: number): number
	return min + math.floor(self:NextNumber() * (max - min + 1))
end

function SeededRandom.Chance(self: SeededRandom, probability: number): boolean
	return self:NextNumber() < probability
end

function SeededRandom.Pick<T>(self: SeededRandom, list: { T }): T
	assert(#list > 0, "SeededRandom:Pick on empty list")
	return list[self:NextInteger(1, #list)]
end

function SeededRandom.Shuffle<T>(self: SeededRandom, list: { T }): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = self:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

function SeededRandom.WeightedPick<T>(self: SeededRandom, list: { T }, weightOf: (T) -> number): T?
	local total = 0
	for _, item in list do
		total += math.max(0, weightOf(item))
	end
	if total <= 0 then
		return nil
	end
	local roll = self:NextNumber() * total
	for _, item in list do
		roll -= math.max(0, weightOf(item))
		if roll < 0 then
			return item
		end
	end
	return list[#list]
end

function SeededRandom.Fork(self: SeededRandom, salt: string): SeededRandom
	return SeededRandom.new(bit32.bxor(self.seed % 4294967296, hashString(salt)))
end

return SeededRandom
