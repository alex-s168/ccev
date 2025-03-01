local ccev = require "ccev"

local sig = ccev.onceSignal()
local ch = ccev.unboundedChannel()

ccev.launch(function(ctx)
  local i = 1
  while i <= 10 do
    if i == 3 then
      print(ctx:waitForAll(sig))
    end
    if i == 8 then
      ctx:waitForAll(ccev.onceTimer(3))
    end
    print(i)
    ctx:schedYield()
    i = i + 1
  end
  while i > 0 do
    ch:push(i)
    i = i - 1
  end
  ch:push(nil)
end)

th2 = ccev.launch(function(ctx)
  local i = 10
  while i > 0 do
    print(i)
    ctx:schedYield()
    i = i - 1
  end
  sig:trySignal(100)
  while true do
    local v = ctx:waitForAll(ch)
    if v == nil then
      break
    end
    print(v)
  end
end)

local keyups = ccev.eventChannel("key_up")
ccev.launch(function(ctx)
  while true do
    local v = ctx:waitForAll(keyups)
    print(v[2])
  end
end)

while true do
  local ev = {os.pullEvent()}
  ccev.onEvent(ev)
end
