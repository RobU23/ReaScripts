--[[
@description Euclidean Algorithm Library
@about
	#### Implements the Bjorklund Euclidean Algorithm
@noindex
@version 1.0
--]]

b = {}
function b.bjorklund(pulses, steps)
	local pattern, counts, remainders = {}, {}, {}
	if pulses > steps then steps = pulses - 1 end
	local divisor = steps - pulses
	table.insert(remainders, pulses)
	local level = 1
	local run = true
	while run do
		table.insert(counts, divisor / remainders[level])
		table.insert(remainders, divisor % remainders[level])
		divisor = remainders[level]
		level = level + 1
		if remainders[level] <= 1 then
			run = false
		end
	end
	table.insert(counts, divisor)
	local build
	build = function(l)
		if l == -1 then
			table.insert(pattern, false)
		elseif l == -2 then
			table.insert(pattern, true)
		else
			for i = 1, counts[l+1] do
				build(l - 1)
			end
			if remainders[l+1] ~= 0 then
				build(l - 2)
			end
		end
	end -- build = function()
	build(level - 1)
	local i = b.get_index(pattern, true)
	pattern = b.rotate(pattern, i - 1)
	return pattern
end

function b.get_index(t, key)
	for i, k in ipairs(t) do
		if k == key then
			return i
		end
	end
	return 0
end

function b.rotate(p, d)
	local res = {}
	for i = d+1, #p do
		table.insert(res, p[i])
	end
	for i = 1, d do
		table.insert(res, p[i])
	end
	return res
end

function b.print_pattern(p)
	local pat = ""
	for i, v in ipairs(p) do
		pat = pat .. (v == true and 1 or 0)
	end
	print(pat)
end

function b.generate(pulses, steps)
	local pat = b.bjorklund(pulses, steps)
	return pat
end

return b


