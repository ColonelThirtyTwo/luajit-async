
local Thread = require "lj-async.thread"
local ffi = require "ffi"

local thread_func = string.dump(function() 
return function(ud)
	local ffi = require "ffi"
	ud = ffi.cast("struct { int x; }*", ud)
	print(ud.x)
	return 0
end
end)

local thread_data_t = ffi.typeof("struct { int x; }")

print("Creating thread 1")
local thread1 = Thread(thread_func, thread_data_t(123))
print("Creating thread 2")
local thread2 = Thread(thread_func, thread_data_t(456))
print("Creating thread 3")
local thread3 = Thread(thread_func, thread_data_t(789))

print("Joining thread 1")
thread1:join()
print("Joining thread 2")
thread2:join()
print("Joining thread 3")
thread3:join()

print("Freeing thread 1")
thread1:free()
print("Freeing thread 2")
thread2:free()
print("Freeing thread 3")
thread3:free()
