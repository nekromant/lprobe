-- This is our basic device class. 
require "class"
local m = class()
m.ioMemory = require("lprobe-memory");

local function dbg(...)
   print("lprobe-device: ", unpack(arg))
end

m.handle  = nil;
m.irq = { };

m.init = function(self, backend, devicename)
   self.backend = require(backend);
   self.handle = self.backend.open(devicename)
   if (self.handle ~= nil) then
      return true;
   else
      return false;
   end
end

local function mem_by_name(name, info)
   for i,j in ipairs(info.dmamem) do
      if (j.name == name) then
	 return j;
      end
   end

   for i,j in ipairs(info.iomem) do
      if (j.name == name) then
	 return j;
      end
   end
   return nil
end

local function irq_by_name(name, info)
   for i,j in ipairs(info.irq) do
      if (j.name == name) then
	 return j;
      end
   end
   return nil
end

--- 
-- Request a memory buffer (registers or DMA)
-- @param self 
-- @param name name of memory region
--
-- @return memory buffer 
--
m.request_mem = function(self, name)
   local mem = mem_by_name(name, self.handle.info)
   if (nil == mem) then
      return nil;
   end

   local ptr = self.backend.request_mem(self.handle.fd, mem.mmapid, mem.size);
   local ret = self.ioMemory(mem, self, ptr, self.backend);
   return ret
end

local function ispending(self, idx)
   local i,j;
   for i,j in pairs({self.backend.irq_pending(self.handle.fd)}) do
      if (j==idx) then 
	 return true;
      end
   end
   return false;
end

--- Setup an irq handler
--  Sets an IRQ handler and the callback that should be called when it arrives
--
-- @param self  
-- @param name irq name
-- @param handler callback that should be invoked when IRQ arrives
-- @param arg argument to the callback
--
-- @return nil
--
m.request_irq = function(self, name, handler, arg)
   local irq = irq_by_name(name, self.handle.info);
   if (ispending(self, irq.index)) then
      print("Ooops, looks like IRQ '"..name.."' is pending. Clearing");
      self.backend.irq_ack(self.handle.fd, irq.index);
      if (ispending(self, irq.index)) then
	 print("IRQ "..irq.name.." is still pending. Trying handler");
	 handler(arg) 
	 self.backend.irq_ack(self.handle.fd, irq.index);
	 if (ispending(self, irq.index)) then
	    error("IRQ "..irq.name.." is still pending. Giving up");
	 end
      end
   end
   self.irq[irq.index] = { 
      ["handler"] = handler,
      ["arg"] = arg
   }
end

--- Handle incoming IRQ for up to timeout ms. 
--  This function invokes the IRQ callback. 
--  It returns either when one or more IRQs have been handled or 
--  when timed out.
--
-- @param self 
-- @param timeout timeout in milliseconds
--
-- @return 
--
m.handle_irqs = function(self, timeout)
   local ret = self.backend.irq_wait(self.handle.fd, timeout);
   local i,j;
   if (ret) then
      for j,i in ipairs({self.backend.irq_pending(self.handle.fd)}) do
	 print(self.irq["0"])
	 if (nil == self.irq[i]) then
	    error("Unhandled irq "..i);
	 end
	 self.irq[i].handler(self.irq[i].arg);
	 self.backend.irq_ack(self.handle.fd, i);
      end
   end
end

--- Handles incoming IRQs until a condition callback returns true 
--  arg will be passed to condition as argument
--  This function will return when either timeout is elapsed or when 
--  condition callback returns true
--
-- @param self 
-- @param arg 
-- @param interval 
-- @param condition 
--
-- @return 
--
m.handle_irqs_cond = function(self, arg, interval, condition)
   while true do 
      self:handle_irqs(interval);
      if condition~=nil and condition(arg) then
	 return
      end
   end
end


m.write = function(reghandle, mtype, ...)
   local dev = reghandle.dev; 
   return dev.backend.write(reghandle, mtype, unpack(arg));
end

m.read = function(reghandle, mtype, ...)
   local dev = reghandle.dev; 
   return dev.backend.read(reghandle, mtype, unpack(arg));
end

m.list_memories = function(self)
   return self.backend.list_memories(self);
end

--Called by lprobe core when an event occurs on a registered descriptor
m.handle_event = function(self, fd, event)
   
end

return m