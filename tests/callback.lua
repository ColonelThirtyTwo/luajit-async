
local callback = require "lj-async.callback"
local ffi = require "ffi"

local cb_t = callback("int(*)(int)")

function initcall()
	--here we can init things
	local ffi = require"ffi"
	--here is the callback
	return function(n) 
		print(n,ffi); 
		return n 
	end 
end

local cb = cb_t(initcall)
assert(cb:funcptr()(123) == 123)
cb:free()
