require "class";

local p = class();

p.pool = { } 

p.init = function(self, b, size)
   local count = math.floor(b.size / size);
   for i = 1, count, 1 do
      local buf = b:alloc(size);
      if (buf == nil) then
	 error("Buffer alloc failed while creating pool")
      end
      table.insert(self.pool, buf);
   end
end

p.get = function(self)
   if #self.pool == 0 then
      return nil; 
   end
   return table.remove(self.pool);
end

p.free = function(self, buf)
   table.insert(self.pool, buf);
end

p.count = function(self)
   return #self.pool;
end

return p;