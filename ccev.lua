-- high-performance multi-threading and async I/O library

local gThreads = {}
local gSchedTimer = nil
local gSchedS = 0.1
local gTimers = {}
-- ev name -> []func
local gEventListeners = {}
local gSchedTimer = nil

local function ensureTicking()
  if not gSchedTimer then
    gSchedTimer = os.startTimer(gSchedS)
  end
end

local function onEvent(args)
  local listeners = gEventListeners[args[1]]
  if listeners then
    for _,li in ipairs(listeners) do
      li(args)
    end
  end

  if args[1] == "timer" then
    if gTimers[args[2]] then
      gTimers[args[2]]:_notify()
      gTimers[args[2]] = nil
    elseif args[2] == gSchedTimer then
      gSchedTimer = nil
      local newThreads = {}
      local allWaiting = true
      for _,th in ipairs(gThreads) do
        local added = false
        if (not th._shouldStop) and (not th:isDone()) then
          if #th._waitingForEither == 0 then
            th._val = coroutine.resume(th._coro, th._ctx, th._args)
            if th._err then
              th.errorCallback(th._err)
            else
              allWaiting = false
            end
          end
          if not th:isDone() then
            table.insert(newThreads, th)
            added = true
          end
        end
        if not added then
          for _,w in ipairs(th._waiters) do
            w:notifySync(th._val)
          end
        end
      end
      gThreads = newThreads

      if not allWaiting then
        gSchedTimer = os.startTimer(gSchedS)
      end
    end
  end
end

local ccev = nil

ccev = {
 threads = gThreads,

 onEvent = onEvent,

 setSchedInterval = function(seconds)
   gSchedS = seconds
 end,

 eventChannel = function(evn,...)
   local filters = {...}
   local ch = ccev.unboundedChannel()
   gEventListeners[evn] = gEventListeners[evn] or {}
   table.insert(gEventListeners[evn], function(args)
     local ok = true
     for i,f in ipairs(filters) do
       if args[i + 1] ~= f then
         ok = false
         break
       end
     end
     if ok then
       ch:push({table.unpack(args)})
     end
   end)
   return ch
 end,

 unboundedChannel = function()
   local c = {
     _q = {},
     _waiters = {},

     addWaiter = function(self, waiter)
       if not waiter then
         error("cannot add nil waiter")
       end
       if #self._q > 0 then
         local x = table.remove(self._q, 1)[1]
         waiter:notifySync(x)
       else
         table.insert(self._waiters, waiter)
       end
     end,

     push = function(self, val)
       if #self._waiters > 0 then
         local w = table.remove(self._waiters, 1)
         w:notifySync(val)
       else
         table.insert(self._q, {val})
       end
     end
   }
   return c
 end,

 onceTimer = function(s,val)
  local timer = {
    _done = false,
    _waiters = {},

    _notify = function(self)
      self._done = true
      for _,x in ipairs(self._waiters) do
        x:notifySync(val)
      end
    end,

    isDone = function(self)
      return self._done
    end,

    addWaiter = function(self, waiter)
      if self._done then
        waiter:notifySync(val)
      else
       table.insert(self._waiters, waiter)
      end
    end,
  }
  gTimers[os.startTimer(s)] = timer
  return timer
 end,

 onceSignal = function()
  local sig = {
    _isSignal = true,
    _signaled = false,
    _val = nil,
    _waiters = {},

    trySignal = function(self, val)
      if not self._isSignal then
        error("bruh")
      end
      if self._signaled then
        return
      end
      self._signaled = true
      self._val = val
      for _,x in ipairs(self._waiters) do
        x:notifySync(val)
      end
    end,

    isDone = function(self)
      if not self._isSignal then
        error("Bruh")
      end
      return self._signaled
    end,

    addWaiter = function(self,waiter)
      if not self._isSignal then
        error("bruh")
      end
      if self:isDone() then
        waiter:notifySync(self._val)
      else
        local a = self._waiters
        a[#a+1] = waiter
      end
    end
  }
  return sig
 end,

 launch = function(fn,...)
  local args = {...}

  local th = {
    _err = nill,
    _shouldStop = false,
    _coro = coro,
    _args = args,
    _prio = 1,
    _ctx = nil,
    _val = nil, -- retval
    _waiters = {},
    _waitValuesBoxed = {},
    -- contains a list of waiting for all
    _waitingForEither = {},

    errorCallback = function(e)
      error(e)
    end,

    stop = function(self)
      self._shouldStop = true
    end,

    setPriority = function(self, prio)
      self._prio = prio
    end,

    isDone = function(self)
      return coroutine.status(self._coro) == "dead"
    end,

    addWaiter = function(self,waiter)
      if self:isDone() then
        waiter:notifySync(nil)
      else
        table.insert(self._waiters,waiter)
      end
    end,
  }
  th._coro = coroutine.create(function(ctx,args)
    local status, err = pcall(fn, ctx, table.unpack(args))
    if not status then
      th._err = err
    end
    -- TODO: put waiters notify into this
  end)
  local function mkWaiter(wo)
    return {
      _wano = false,
      _th = th,
      notifySync = function(self,val)
        if self._wano then
          error("waiter was already notified")
        end
        if not self._th then
          error("wtf")
        end

        self._wano = true
        local any = #self._th._waitingForEither == 0
        for i,li in ipairs(self._th._waitingForEither) do
          local new = {}
          for _,x in ipairs(li) do
            if x ~= wo then
              table.insert(new, x)
            end
          end
          if #new == 0 then
            any = true
            break
          end
          self._th._waitingForEither[i] = new
        end

        if any then
          self._th._waitingForEither = {}
          ensureTicking()
        end

        table.insert(self._th._waitValuesBoxed, {val})
      end
    }
  end
  th._ctx = {
    _th = th,

    schedYield = function(self)
      coroutine.yield()
    end,

    waitForOne = function(self, ...)
      for _,x in ipairs({...}) do
        table.insert(self._th._waitingForEither,{x})
        x:addWaiter(mkWaiter(x))
      end
      self:schedYield()
      local out = nil
      for i,box in ipairs(self._th._waitValuesBoxed) do
        if box[1] then
          out = box[1]
          break
        end
        self._th._waitValuesBoxed[i] = nil
      end
      return out
    end,

    waitForAll = function(self, ...)
      local args = {...}
      table.insert(self._th._waitingForEither,args)
      for _,x in ipairs(args) do
        x:addWaiter(mkWaiter(x))
      end
      self:schedYield()
      local out = {}
      for i,box in ipairs(self._th._waitValuesBoxed) do
        out[i] = box[1]
        self._th._waitValuesBoxed[i] = nil
      end
      return table.unpack(out)
    end,
  }
  table.insert(gThreads, th)
  ensureTicking()
  return th
 end
}
return ccev
