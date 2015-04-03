local m = {}

m.device = nil; 


local function dbg(...)
   print("lprobe-backend-dummy:", unpack(arg))
end


-- return a handle to be passed in all calls below 
m.open = function(...)
   dbg("opening device ", devname);
   local devhandle = 123; 
   return devhandle
end

-- Basic stuff we need for register memory IO

-- Get a memory block. 
-- We can read/write it via calls below
m.request_mem = function(devhandle, ...)
   dbg("request")
   local reghandle = { } ;
   reghandle.dev = devhandle;
   return reghandle; 
end

-- Write memory
m.write = function(reghandle, mtype, ...)
   dbg(lutil_dump(arg));
end

-- Read memory
m.read = function(reghandle, mtype, ...)
   dbg(lutil_dump(arg));
end

m.info = function(devhandle) 
{
   return nil;
}

m.list_memories = function(devhandle)
   local mem = { } 
   mem["registers"] = { 
      ["start"] = 0x100,
      ["end"]   = 0x200
   };

   mem["imem"] = { 
      ["start"] = 0x100,
      ["end"]   = 0x200
   };
   return mem; 
end


m.list_irqs = function(devhandle)
   local irq = { } ;
   irq["irq"] = 100500; -- Handle 
   return;
end


return m;