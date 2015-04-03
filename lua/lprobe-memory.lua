
require "class";
require "lutil"

--- Class representing memory buffer (regsiters and DMA memory alike)
-- @module lprobe-memory
local m = class();

--m.handle = nil;
--m.backend = nil;
--m.tracefunc = nil;

--m.internal_offset = 0;
--m.size = 0;

--DMA corruption detector
--m.protected = false;
--m.margins = 0;
--m.margin_mask = 0;


-- builtin allocator private data
-- Buffer doesn't support free method 
--m.alloc_offset = 0;

-- m.parent = nil;

m.tbl = { 
   { 01, "u8"  }, 
   { 02, "u16" },
   { 04, "u32" },
   { 08, "u64" }, 
   { 11, "s8"  }, 
   { 12, "s16" },
   { 14, "s32" },
   { 18, "s64" }, 
}

local function dbg(...)
   print("lprobe-mem: ", unpack(arg))
end

--- Allocate part of this buffer of size len and return it.
--  optional 'protlen' argument specifies the length of protection margins, if needed
--  for details about protection.
--  The allocator is _very_ dumb. It doesn't support freeing memory. 
--
-- @see protected 
--
-- @param self 
-- @param len length to allocate
-- @param protlen margin length (optional)
--
-- @return newly allocated buffer or nil
--
m.alloc = function(self, len, protlen)

   while (self.alloc_offset % 4 ~= 0) do 
      self.alloc_offset = self.alloc_offset + 1;
   end
   
   if (protlen == nil) then
      protlen = 0;
   end
   
   local new = self:slice(self.alloc_offset, len + protlen*2)
   if (new == nil) then
      return new
   end

   self.alloc_offset = self.alloc_offset + len + protlen*2;

   if (protlen > 0) then
      new = new:protected(protlen);
   end
   
   return new;
end

--- Returns parent memory buffer or nil if this is the top-level buffer. 
-- @param self 
--
-- @return parent buffer
--
m.get_parent = function(self)
   return self.parent
end

m.__do_io = function(self, iotype, offset, value)
   local address = self.internal_offset + offset;

   local ret = nil;
   if (value) then
      if (self.tracefunc ~= nil) then
	 self:tracefunc("w", offset, iotype, value);
      end
      self.backend.write(self.handle, address, iotype, value);
   else
      ret=self.backend.read(self.handle, self.internal_offset + offset, iotype);
      if (self.tracefunc ~= nil) then
	 self:tracefunc("r", offset, iotype, ret);
      end
   end
   return ret
end

--- Set a register tracer function. 
--  tracefunc function will be called every time there's IO on this buffer object. See example tracer below:
--  
-- function simple_tracer(self, op, offset, iotype, value)
--    if (op=="w") then
--       print(string.format("[write/%s/%d] 0x%x <= 0x%x", self.name, iotype, self:phys() + offset, value))
--    else
--       print(string.format("[read/%s/%d] 0x%x == 0x%x", self.name, iotype, self:phys() + offset, value))      
--    end
-- end
--
-- @param self 
-- @param tracefunc tracer callback
--
-- @return 
--
m.trace = function(self, tracefunc)
   self.tracefunc = tracefunc;
end

--m.__wait = function(self, iotype, off, value, timeout)
-- self:u
--end


m.init = function(self, info, device, handle, backend)
   -- initialize base values
   self.internal_offset = 0;
   self.size = 0;
   self.is_protected = false;
   self.margins = 0;
   self.margin_mask = 0; 
   self.alloc_offset = 0;  
 
   -- Merge stuff from info
   for k,v in pairs(info) do 
      self[k] = v 
   end

   self.device = device; --lprobe device we belong to
   self.backend = backend; -- backend for write/read calls
   self.handle = handle; -- handle to pass along the backend calls


   -- Now setup some basic IO ops
   for i,j in ipairs(self.tbl) do

      self[j[2]] = function(hndl, offset, value)
	 return hndl:__do_io(j[1], offset, value);  
      end

--      self["wait"..j[2]] = function(hndl, offset, value, timeout)
--	 return hndl:__wait(j[1], offset, value);  
--     end

   end
end

--- Get physical address of the data buffer
--  Returns a physical address to the buffer, optionally adding offset bytes to it
--
-- @param self 
-- @param offset
--
-- @return physical address
--
m.phys = function(self, offset)
   if (nil == offset) then
      offset = 0
   end
   return self.physaddr + self.internal_offset + offset;
end

--- Return a subregion of this buffer.
-- This function slices a subregion if the buffer and returns it in a new 
-- buffer object. 
--
-- @param self 
-- @param offset 
-- @param len 
--
-- @return 
--
m.slice = function(self, offset, len) 
   local new = self.__copy(self);
   new.parent = self;
   new.internal_offset = new.internal_offset + offset;
   new.is_protected = false; -- subslices are NOT protected by default 

   if (len == nil) then
      new.size = new.size - offset;
   else
      if (self.size - offset < len) then
	 error("sliced area too big")
      end
      new.size = len;
   end
   
   if (new == nil) then
      print("warn: slice failed!")
   end
   
   return new
end


m.regdump32 = function(self, label, offset, length)
   for off = offset, length, 4 do
      local byte = self:u32(off)
      print(string.format("0x%x = 0x%x",off,byte));
   end
end

--- 
-- Print a hex dump of the given buffer to stdout, preceding it with 'label' 
-- If offset and length are omited - offset will be assumed as 0 and length will
-- be assumed to be the full length of the buffer
-- @param self 
-- @param label text la 
-- @param offset 
-- @param length 
--
-- @return 
--
m.hexdump = function(self, label, offset, length ) 
   if (nil==offset) then
      offset=0;
   end

   if (length==nil) then
      length=self.size;
   end

   if (label ~= nil) then
      print("--- "..label.." ---");
   end

   local str1 = "" 
   local str2 = "";
   local off
   local nb = 0;
   for off = offset, length - 1, 1 do
      local byte = self:u8(off)

      if((off) % 16 == 0) then
	 if (nb > 1) then
	    print(str1..str2.." |");
	 end
	 str1=string.format('%08X : ', off)
	 str2=" | "
	 nb = 0;
      end

      nb=nb+1;
      str1=str1..string.format("%02X ", byte)
      local n = string.char(byte)

      if (n:match("%W")) then
	 str2=str2.."."
      else
	 str2=str2..n
      end


      if ((off + 1) % 4 == 0) then
	 str1=str1.." "
      end

   end
   
   for off = nb, 15, 1 do
      str1=str1.."XX "
      str2=str2.." "
      if ((off + 1) % 4 == 0) then
	 str1=str1.." "
      end
   end

   if (nb > 0) then
      print(str1..str2.." |");
   end

   if (label ~= nil) then
      print("--------------8<--------------");
   end

end

--- Fill the buffer with a single byte value
--
-- @param self 
-- @param value value (0-255) to memset
--
-- @return 
--
m.memset = function(self, value)
   local n = self.size - 1 ;
   while n >= 0 do 
      self:u8(n, value);
      n=n-1;
   end   
end

--- Write a text string into the target buffer at the given offset
--
-- @param self 
-- @param off Offset at which to fill
-- @param str Text to fill the buffer with
--
-- @return 
--
m.fromstring = function(self, off, str)
   for n=0, #str, 1 do
      if (off+n > self.size) then
	 return 
      end
      self:u8(off+n,str:byte(n+1))       
   end
end

--- Fill the 'margins' with a single byte value. 
-- The value is stored internally to do check_margins()
-- @param self 
-- @param value value to fill margins with
--
-- @return 
-- @see protected
m.fill_margins = function(self, value)
   local n = self.margins - 1; 
   self.margin_mask = value;

   while n >= 0 do 
      self:u8(-n, value);
      n=n-1;
   end
   
   n = self.margins - 1 ;
   while n >= 0 do 
      self:u8(self.size+n, value);
      n=n-1;
   end   
end

--- Check if the margins have been modified since the last call to fill_margins()
--  
-- @param self 
--
-- @return true if the margins have NOT been modified. false otherwise
-- @see protected
m.check_margins = function(self)
   local n = self.margins-1; 
   while n >= 0 do 
      if self:u8(-n) ~= self.margin_mask then
	 error("Margin check failed @ "..-n)
	 return false;
      end

      if self:u8(self.size + n) ~= self.margin_mask then
	 error("Margin check failed @ "..self.size + n)
	 return false;
      end

      n=n-1;
   end
   return true;
end

--- Create a 'protected' buffer from source buffer. 
--  This is a handy trick to catch DMA writing beyond its allowed boundaries.
--  A protected buffer is a slice of the source buffer with margins at the beginning and the end
--  The margins are filled with some value with fill_margins() before issuing a DMA operation.  
--  After the DMA has done its job you can call check_margins() and quickly see if any of bytes beyound 
--  are corrupt. 
--
-- @param self 
-- @param margin_length 
--
-- @return 
--
m.protected = function(self, margin_length)
   local ps; 
   if (nil == margin_length) then
      ps = require("lprobelnx").pagesize();;
   else
      ps = margin_length
   end
   
   local newlen = self.size - ps*2
   local new = self:slice(ps, newlen);
 
   new.margins = ps;
   new.is_protected=true;
   new:fill_margins(0x0);
   new:check_margins(0x0);
   return new; 
end



return m;