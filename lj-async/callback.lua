
--- Framework for creating Lua callbacks that can be asynchronously called.

local ffi = require "ffi"
local C = ffi.C

-- Setup function ran by the Lua state to create
local callback_setup_func = string.dump(function(cbtype, cbsource)
	local ffi = _G.require("ffi")
	local initfunc = _G.loadstring(cbsource)
	
	local xpcall, dtraceback, tostring, error = _G.xpcall, _G.debug.traceback, _G.tostring, _G.error
	
	local xpcall_hook = function(err) return dtraceback(tostring(err) or "<nonstring error>") end

	local cbfunc = initfunc()
	local waserror = false
	local cb = ffi.cast(cbtype, function(...)
		if not waserror then
		local ok, val = xpcall(cbfunc, xpcall_hook, ...)
		if not ok then
			print("error in callback",val)
			--error(val, 0)
			waserror = true
			return 0
		else
			return val
		end
		else
			return 0
		end
	end)
	
	return cb, tonumber(ffi.cast("int", cb))
end)

ffi.cdef[[
	static const int LUA_GLOBALSINDEX   = -10002;
	
	typedef struct lua_State lua_State;
	typedef ptrdiff_t lua_Integer;
	
	lua_State* luaL_newstate(void);
	void luaL_openlibs(lua_State *L);
	void lua_close (lua_State *L);
	void lua_call(lua_State *L, int nargs, int nresults);
	int lua_pcall (lua_State *L, int nargs, int nresults, int errfunc);
	void lua_checkstack (lua_State *L, int sz);
	void lua_settop (lua_State *L, int index);
	void  lua_pushlstring (lua_State *L, const char *s, size_t l);
	void lua_gettable (lua_State *L, int idx);
	void lua_getfield (lua_State *L, int idx, const char *k);
	void lua_settop(lua_State*, int);
	lua_Integer lua_tointeger (lua_State *L, int index);
	int lua_isnumber(lua_State*,int);
	const char *lua_tostring (lua_State *L, int index);
	const char *lua_tolstring (lua_State *L, int index, size_t *len);
]]

-- Maps callback object ctypes to the callback pointer types
local ctype2cbstr = {}

local Callback = {}
Callback.__index = Callback

--- Creates a new callback object.
-- callback_func is either a function compatible with string.dump (i.e. a Lua function without upvalues)
-- or LuaJIT source/bytecode representing such a function (ex. The output of string.dump(func). This is recommended if you
-- plan on making many callbacks).
--
-- The function is (re)created in a separate Lua state; thus, no Lua values may be shared.
-- The only way to share information between the main Lua state and the callback is by a
-- userdata pointer in the callback function, which you will need to synchronize
-- yourself.
--
-- The returned object must be kept alive for as long as the callback may still be called.
-- 
-- Errors in callbacks are not caught; thus, they will cause its Lua state's panic function
-- to run and terminate the process.
function Callback:__new(callback_func)

	local obj = ffi.new(self)
	local cbtype = assert(ctype2cbstr[tonumber(self)])
	
	if type(callback_func) == "function" then
		local name,val = debug.getupvalue(callback_func,1)
		if name then
			print("init callback function has upvalue ",name)
			error("upvalues in init callback")
		end
		callback_func = string.dump(callback_func)
	end
	
	local L = C.luaL_newstate()
	if L == nil then
		error("Could not allocate new state",2)
	end
	obj.L = L
	
	C.luaL_openlibs(L)
	C.lua_settop(L,0)
	
	if C.lua_checkstack(L, 3) == 0 then
		error("out of memory")
	end
	
	-- Load the callback setup function
	C.lua_getfield(L, C.LUA_GLOBALSINDEX, "loadstring")
	C.lua_pushlstring(L, callback_setup_func, #callback_setup_func)
	C.lua_call(L,1,1)
	
	-- Load the actual callback
	C.lua_pushlstring(L, cbtype, #cbtype)
	C.lua_pushlstring(L, callback_func, #callback_func)
	local ret = C.lua_pcall(L,2,2,0)

	if ret > 0 then
		print(ffi.string(C.lua_tolstring(L,1,nil)))
		error("error making callback",2)
		return nil
	end
	-- Get and pop the callback function pointer
	assert(C.lua_isnumber(L,2) ~= 0)
	local ptr = C.lua_tointeger(L,2)
	assert(ptr ~= 0)
	C.lua_settop(L, 1)
	obj.callback = ffi.cast(cbtype, ptr)
	assert(obj.callback ~= nil)
	
	return obj
end

--- Gets and returns the callback function pointer.
function Callback:funcptr()
	return self.callback
end

--- Frees the callback object and associated callback.
function Callback:free()
	if self.L ~= nil then
		-- TODO: Do we need to free the callback, or will lua_close free it for us?
		C.lua_close(self.L)
		self.L = nil
	end
end
Callback.__gc = Callback.free

--- Returns a newly created callback ctype.
-- cb_type is a string representation of the callback pointer type (ex. what you would pass to ffi.typeof).
-- This must be a string; actual ctype objects cannot be used.
return function(cb_type)
	assert(type(cb_type) == "string", "Bad argument #1 to async type creator; string expected")
	
	local typ = ffi.typeof([[struct {
		lua_State* L;
		$ callback;
	}]], ffi.typeof(cb_type))
	
	ctype2cbstr[tonumber(typ)] = cb_type
	
	return ffi.metatype(typ, Callback)
end
