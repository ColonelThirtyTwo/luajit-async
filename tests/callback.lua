
local callback = require "callback"
local ffi = require "ffi"

local cb_t = callback("int(*)(int)")
local cb = cb_t(function(n) print(n); return n end)
assert(cb:funcptr()(123) == 123)
