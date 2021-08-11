-------------------------------------------------------------------------------
--   Copyright 2021 SmartThings
--
--   Licensed under the Apache License, Version 2.0 (the "License");
--   you may not use this file except in compliance with the License.
--   You may obtain a copy of the License at
--
--       http://www.apache.org/licenses/LICENSE-2.0
--
--   Unless required by applicable law or agreed to in writing, software
--   distributed under the License is distributed on an "AS IS" BASIS,
--   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--   See the License for the specific language governing permissions and
--   limitations under the License.
-------------------------------------------------------------------------------

local cosock = require "cosock"
local socket  = cosock.socket
local json = require "dkjson"

local rpc = {}

local function new()
  local sock = assert(socket.tcp())
  assert(sock:bind("0.0.0.0", 0))

  return setmetatable({
    sock = sock,
    handlers = {},
    subscriptions = {}
  }, {__index = rpc})
end

function rpc:getsockname()
  return self.sock:getsockname()
end

function rpc:register(command, handler)
  assert(type(command) == "string", "command must be string")
  assert(type(handler) == "function", "handler must be function")
  self.handlers[command] = handler
end

function rpc:notify(method, ...)
  for _, sub in pairs(self.subscriptions) do
    sub:send({method=method, params = {...}})
  end
end

function rpc:run()
  local t = self.sock
  assert(t:listen())

  while true do
    local conn = t:accept()

    local notifysend, notifyrecv = cosock.channel.new()
    self.subscriptions[notifysend] = notifysend

    cosock.spawn(
      function()
        repeat
          local readr, sendr, err = socket.select({conn, notifyrecv}, {}, nil)
          assert(not err, "select error: "..tostring(err))
          if readr[1] == conn then
            local line, err = conn:receive()
            if line then
              local msg, endpos, err = json.decode(line)
              if not msg then
                conn:send("error: parse error ".. err.. "\n")
              elseif type(msg) ~= "table" then
                conn:send("error: message should be map\n")
              elseif not msg.method then
                conn:send("error: method not specified\n")
              elseif not msg.id then
                conn:send("error: id not speicified\n")
              elseif not self.handlers[msg.method] then
                conn:send("error: invalid method '"..msg.method.."'\n")
              else
                local handler = self.handlers[msg.method]
                local params = msg.params or {}
                -- run handler
                local ret = table.pack(pcall(handler, table.unpack(params)))
                local status = ret[1]
		print("request", line)
		local response
                if status then
                  response = json.encode({id = msg.id, result = {table.unpack(ret, 2)}})
                else
                  response = json.encode({id = msg.id, result = {"error", table.unpack(ret, 2)}})
                end
		print("response", response)
		conn:send(response.."\n")
              end
            elseif err == "closed" then
              break
            else
              error("unexpected connection error: "..tostring(err))
            end
          elseif readr[1] == notifyrecv then
            local notifymsg, err = notifyrecv:receive()
            if err == "closed" then
              error("notify channel closed before device disconnected")
            elseif err then
              error("unexpected channel error: "..tostring(err))
            else
              conn:send(json.encode(notifymsg).."\n")
            end
          end
        until err ~= nil

        self.subscriptions[notifysend] = nil
      end
    )
  end
end

return setmetatable(rpc, {__call = new})
