-- memory poller base class
local m = {}

m.pollfd  = nil; 
m.backend = nil;
m.callback = nil; 

m.start = function()
   m.backend.mem_poll_start(m.pollfd)
   m.backend.mem_poll_set_callback(m.callback)
end

m.stop = function(flush=false)
   return m.backend.mem_poll_stop(m.pollfd, flush)
end

--We need to free the poller whenever we do gc 
m.__gc = function()
   print("gc mem poller")
   m.backend.mem_poll_destroy(m.pollfd);
end


return m