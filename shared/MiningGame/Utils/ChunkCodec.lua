--!strict
-- ChunkCodec.lua
-- Efficient compression for chunk data (4096 bits per chunk)

local ChunkCodec = {}

-- Run-length encoding for better compression
-- Format: "1x7,0x23,1x5,..." means 7 ones, 23 zeros, 5 ones, etc.

-- Encode runs of bits into a compact string
local function encodeRuns(runs: { { bit: number, len: number } }): string
	local parts = table.create(#runs)
	for i, run in ipairs(runs) do
		parts[i] = string.format("%dx%d", run.bit, run.len)
	end
	return table.concat(parts, ",")
end

-- Decode run-length string back to runs
local function decodeRuns(encoded: string): { { bit: number, len: number } }
	local runs = {}
	for bit, len in string.gmatch(encoded, "(%d)x(%d+)") do
		table.insert(runs, {
			bit = tonumber(bit) :: number,
			len = tonumber(len) :: number,
		})
	end
	return runs
end

-- Pack boolean array into run-length encoded string
function ChunkCodec.pack(bits: { boolean }, expectedCount: number): string
	assert(#bits == expectedCount, "Bit count mismatch")

	if expectedCount == 0 then
		return ""
	end

	local runs = {}
	local currentBit = bits[1] and 1 or 0
	local currentLen = 1

	for i = 2, expectedCount do
		local bit = bits[i] and 1 or 0
		if bit == currentBit then
			currentLen = currentLen + 1
		else
			table.insert(runs, { bit = currentBit, len = currentLen })
			currentBit = bit
			currentLen = 1
		end
	end

	-- Don't forget the last run
	table.insert(runs, { bit = currentBit, len = currentLen })

	return encodeRuns(runs)
end

-- Unpack run-length encoded string to boolean array
function ChunkCodec.unpack(encoded: string, expectedCount: number): { boolean }
	if expectedCount == 0 then
		return {}
	end

	if encoded == "" then
		-- Empty string means all false (undug)
		return table.create(expectedCount, false)
	end

	local runs = decodeRuns(encoded)
	local bits = table.create(expectedCount, false)
	local index = 1

	for _, run in ipairs(runs) do
		local bitValue = (run.bit == 1)
		for _ = 1, run.len do
			if index <= expectedCount then
				bits[index] = bitValue
				index = index + 1
			else
				break
			end
		end
	end

	return bits
end

-- Create an empty chunk (all solid/undug)
function ChunkCodec.empty(size: number): string
	-- All zeros can be represented very compactly
	return string.format("0x%d", size)
end

-- Create a full chunk (all dug)
function ChunkCodec.full(size: number): string
	-- All ones can be represented very compactly
	return string.format("1x%d", size)
end

-- Check if a chunk is completely empty (undug)
function ChunkCodec.isEmpty(encoded: string, size: number): boolean
	return encoded == string.format("0x%d", size) or encoded == ""
end

-- Check if a chunk is completely full (dug)
function ChunkCodec.isFull(encoded: string, size: number): boolean
	return encoded == string.format("1x%d", size)
end

-- Get approximate memory usage of encoded string
function ChunkCodec.getByteSize(encoded: string): number
	return #encoded
end

-- Merge two chunks (OR operation for dig operations)
function ChunkCodec.merge(encoded1: string, encoded2: string, size: number): string
	local bits1 = ChunkCodec.unpack(encoded1, size)
	local bits2 = ChunkCodec.unpack(encoded2, size)

	for i = 1, size do
		bits1[i] = bits1[i] or bits2[i]
	end

	return ChunkCodec.pack(bits1, size)
end

-- Count the number of dug cells in a chunk
function ChunkCodec.countDug(encoded: string, _size: number): number
	if encoded == "" then
		return 0
	end

	local runs = decodeRuns(encoded)
	local count = 0

	for _, run in ipairs(runs) do
		if run.bit == 1 then
			count = count + run.len
		end
	end

	return count
end

-- Get a single bit value from encoded chunk
function ChunkCodec.getBit(encoded: string, index: number, size: number): boolean
	assert(index >= 1 and index <= size, "Index out of bounds")

	if encoded == "" then
		return false
	end

	local runs = decodeRuns(encoded)
	local currentIndex = 1

	for _, run in ipairs(runs) do
		local endIndex = currentIndex + run.len - 1
		if index >= currentIndex and index <= endIndex then
			return run.bit == 1
		end
		currentIndex = endIndex + 1
	end

	return false
end

-- Set a single bit value in encoded chunk
function ChunkCodec.setBit(encoded: string, index: number, value: boolean, size: number): string
	local bits = ChunkCodec.unpack(encoded, size)
	bits[index] = value
	return ChunkCodec.pack(bits, size)
end

-- Optimized batch set for multiple bits
function ChunkCodec.setBits(encoded: string, indices: { number }, value: boolean, size: number): string
	local bits = ChunkCodec.unpack(encoded, size)
	for _, index in ipairs(indices) do
		if index >= 1 and index <= size then
			bits[index] = value
		end
	end
	return ChunkCodec.pack(bits, size)
end

return ChunkCodec
