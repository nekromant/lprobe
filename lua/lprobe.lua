require "class"

local m = { };

m.EVT_IRQ_DISPATCH=1;
m.EVT_IRQ_DISABLED=2;
m.EVT_IRQ_HWFAULT=3;

m.debug = true;
local function dbg(...)
   if (m.debug) then
      print("lprobe:", unpack(arg))
   end
end

m.default_backend = "lnx"

m.debug = false;

--- Open a device and return a handle to it
--
-- @param self 
-- @param devname 
--
-- @return 
--
m.open = function(self, devname)
   return require("lprobe-device")("lprobelnx", self, devname);
end

m.loop = function(devhandle)
   
end

m.looponce_nonblock = function(devhandle)
   
end

m.looponce = function(devhandle)
   
end

m.loopbreak = function(devhandle)
   
end

m.bitmap = function(name, mapname, regs)
   local rmap = require("bitmaps/"..mapname);
   local rm = require("lprobe-bitmap")(name, rmap, regs);
   return rm;
end


return m;