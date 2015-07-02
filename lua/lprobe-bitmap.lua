require "class";
local bm = class();

local function is_range(j)
   return (#j==3) and type(j[2]) == "number";
end

local function is_enum(j)
   return type(j[1]) == "number" and 
          type(j[2]) == "number" and 
         (type(j[4]) == "string" or 
	  type(j[4]) == "table");
end

bm.init = function(self, name, regmap, regs)
   self.name   = name;
   self.bitmap = regmap;
   self.regs   = regs;
   self.byname = { };
   self.byaddr = { };

   -- Let's assume we're 32 bit for now. 
   self.rsize = 0x4; 
   self.accessfunc = "u32";
   
   -- Let's determine register size and proper access function
   -- Currently we're limited to 32-bit by bit32 library. 
   if regmap[0x1] ~= nil then
      self.rsize = 0x1;
      self.accessfunc = "u8";
   end

   if regmap[0x2] ~= nil then
      self.rsize = 0x2; 
      self.accessfunc = "u16";
   end

   if regmap[0x4] ~= nil then
      self.rsize = 0x4; 
      self.accessfunc = "u32";
   end

   assert(self.rsize ~= nil);
   assert(self.accessfunc ~= nil);
   
   -- Generate a name lookup table for our bitmap
   for i,j in pairs(regmap) do
      assert(type(j[1]) == "string");
      self.byname[j[1]] = {
	 ["map"]  = j,
	 ["off"]  = i,
	 ["bits"] = { }
      };
      self.byaddr[i] = self.byname[j[1]];
      -- And lookup for individual bit names
      for k,l in pairs(j) do 
	 if type(l) == "table" then
	    if (type(l[2]) == "string") then
	       local name = l[2]; -- single bit
	       self.byname[j[1]]["bits"][name] = l;
	    else 
	       if is_range(l) then
		  local name = l[3]; -- range
		  self.byname[j[1]]["bits"][name] = l;
	       else
		  if is_enum(l) then -- enums need a lot more hardcore stuff
		     self.byname[j[1]]["enum"] = {  }
		     for m,n in pairs(l) do
			if type(n) == "string" then
			   self.byname[j[1]]["bits"][n] = l;
			   self.byname[j[1]]["enum"][n] = m-3;
			else if type(n) == "table" then
			      self.byname[j[1]]["bits"][n[2]] = l;
			      self.byname[j[1]]["enum"][n[2]] = n[1];
			     end
			end
		     end
		  end
	       end
	    end
	 end
      end      
   end
end

bm.register = function(self, reg)
   -- First see if we can resolve the register by name. 
   local lp = self.byname[reg];
   if (nil ~= lp) then
      return lp["off"], lp["map"], lp["bits"], lp["enum"];
   end

   -- If we failed, but the type is still 'string'
   -- the name is most likely erroneous
   if (type(reg) == "string") then
      error("No register with name: ", reg);
   end
   -- Finally, if it's a number - check if it's valid
   lp = self.byaddr[reg];
   if (nil ~= lp) then
      return lp["off"], lp["map"], lp["bits"], lp["enum"];
   end
   return error("No register with offset: ", reg);
end


bm.format_register = function(self, map, reg, regvalue)
   local str = string.format("%s[%16s] == 0x%8x :  ", self.name, self.bitmap[reg][1], regvalue);
   for i,j in ipairs(map) do
      if (type(j) == "string") then
	 -- Do nothing, it's reg name
      else 
	 if (type(j) == "function") then
	    str=str..j(self, regvalue)
	 else
	    if is_range(j) then -- range
	       local v = bit32.extract(regvalue, j[1], j[2]-j[1]+1);
	       str=str..string.format("%s(%d) ", j[3], v);
	    else 
	       if is_enum(j) then
		  local v = bit32.extract(regvalue, j[1], j[2]-j[1]+1);
		  local enum_val = j[3+v];
		  if type(enum_val) == "table" then 
		     enum_val = enum_val[2]
		  end
		  str=str..string.format("0x%x[%s] ", v, enum_val);
	       else
		  if (bit32.extract(regvalue, j[1]) ~= 0) then
		     str=str..j[2].." ";
		  else if (j[3] ~= nil) then
			str=str..j[3].." ";
		       end
		  end
	       end
	    end
	 end
      end
   end
   return str;
end

bm.print_register = function(self, reg, rvalue)
   local reg, map    = self:register(reg)
   if (rvalue == nil) then
      rvalue = self.regs[self.accessfunc](self.regs, reg);
   end
   print(self:format_register(map, reg, rvalue));
end


bm.dump = function(self, reg, regvalue)
   if (nil==regvalue and nil == self.regs) then
      error("Attempting bitmap dump with no handle to actual register data");
   end
   
   if (reg ~= nil) then
      self:print_register(reg, reg_value)
      return
   end
   -- Otherwise we'll need to loop through the bitmap
   local n = 0; 
   repeat
      self:print_register(n, regvalue);
      n = n + 4;
   until nil == self.bitmap[n]; 
   print("--------------------8<--------------------")
end


bm.extract = function(self, regname, bitname, value)
   local reg, map, bits, enum  = self:register(regname)
   if (nil == value) then
      value = self.regs[self.accessfunc](self.regs, reg, regvalue);
   end
   assert(reg ~= nil )
   local bitlen = 1

   local bitfield = bits[bitname];
   if is_range(bitfield) or is_enum(bitfield) then
      bitlen = bitfield[2] - bitfield[1] + 1;
   end
   
   return bit32.extract(value, bitfield[1], bitlen);

end

-- mb:r("ID")
-- mb:r("RESET", 1);
-- mb:r("ARLEN", "ARLEN", 15);
bm.io = function(self, regname, arg1, arg2)
   local do_bitop = false;
   local regvalue = nil;   
   local bitvalue = nil;
   local bitname  = nil;
   if type(arg1) == "string" then
      do_bitop = true;
      bitname = arg1;
      bitvalue = arg2
   else
      regvalue = arg1;
   end


   local reg, map, bits, enum  = self:register(regname)
   assert (reg ~= nil);

   if not do_bitop then
      print("normal")
      return self.regs[self.accessfunc](self.regs, reg, regvalue);
   end

   local bitfield = bits[bitname];
   -- If we're operating on individual bits things get more complicated

   local value = self.regs[self.accessfunc](self.regs, reg, regvalue);
   assert(type(bitfield) == "table")
   local bitlen = 1

   if is_range(bitfield) or is_enum(bitfield) then
      bitlen = bitfield[2] - bitfield[1] + 1;
   end

   if is_enum(bitfield) then
      assert(enum == nil)
      value = bit32.replace(value, enum[bitname], bitfield[1], bitlen);
   end
   
   if (bitvalue ~= nil) then
      value = bit32.replace(value, bitvalue, bitfield[1], bitlen);
      return self.regs[self.accessfunc](self.regs, reg, value);
   else
      return bit32.extract(value, bitfield[1], bitlen);
   end
end

return bm;