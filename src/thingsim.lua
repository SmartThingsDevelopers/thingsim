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
local socket = cosock.socket
local rpc = require "thingsim.rpc"
local log = require "log"
local json = require "dkjson"

-- top level library interface
local thingsim = {}

-- parse SSDP's psuedo HTTP header format into table
function ssdp_parse(msg)
  local lines = msg:gmatch("(.-)\r?\n")

  local header = lines()

  local kind

  if header == "M-SEARCH * HTTP/1.1" then
    kind = "search"
  else
    -- unknown kind, drop silently
    return nil
  end

  local headers = {}

  for line in lines do
    if line == "" then
      break
    end

    local key, value = line:match("(.-):%s*(.*)")

    headers[key] = value
  end

  return {
    kind = kind,
    headers = headers,
    body = nil,
  }
end

-- this function gets the OS to tell us which local interface IP is the best option for contacting
-- a given remote IP
function find_interface_ip_for_remote(ip)
  local sock = socket:udp()
  sock:setpeername(ip, 9) -- port 9 is "discard protocol" (not that this socket is ever even used)
  local localip, _, _ = sock:getsockname()

  return localip
end

function ssdp_listen(things)
  local sock = assert(socket.udp())

  local ssdp_multicast_ip = '239.255.255.250'
  local ssdp_multicast_port = 1900

  assert(sock:setsockname(ssdp_multicast_ip, ssdp_multicast_port))
  assert(sock:setoption("ip-add-membership", {multiaddr = ssdp_multicast_ip, interface = '0.0.0.0'}))

  while true do
    local pkt, ip, port, err = sock:receivefrom()

    if pkt ~= nil then
      local msg = ssdp_parse(pkt)
      if msg then
        -- TODO: dynamic search target
        if msg.headers.ST == "urn:smartthings-com:device:thingsim:1" then
          local localip = assert(find_interface_ip_for_remote(ip), "unable to get local ip")

          for _,thing in pairs(things) do
            local resp = {
              "HTTP/1.1 200 OK",
              "CACHE-CONTROL: 60",
              "DATE: " .. os.date("!%a, %d %b %Y %H:%M:%S GMT"),
              "EXT:", -- intentionally left blank, req for back compat, in spec
              "LOCATION: http://"..localip..":7474/", -- TODO: dynamic port
              "SERVER: UPnP/2.0 thingsim/0",
              "ST: urn:smartthings-com:device:thingsim:1",
              "USN: uuid:" .. tostring(thing.id) .. ":urn:smartthings-com:device:thingsim:1",
              "BOOTID.UPNP.ORG: "..tostring(messagecounter),
            }

            if thing.name then
              table.insert(
                resp,
                "NAME.SMARTTHINGS.COM: "..thing.name
              )
            end

            if thing.servers.rpc then
              table.insert(
                resp,
                "RPC.SMARTTHINGS.COM: rpc://" .. localip .. ":" .. thing.servers.rpc.port
              )
            end

            -- headers end with blank line
            table.insert(resp, "\r\n")

	    print("ssdp resp:\n", table.concat(resp, "\r\n"))

            sock:sendto(table.concat(resp, "\r\n"), ip, port)
          end
        end

      end
    elseif err == "timeout" then
      break
    else
      print("Error:", err)
      break
    end
  end

end



local thing = {}

function thingsim.thing(profile)
  local nt = {}

  nt.profile = profile

  return setmetatable(nt, {__index = thing})
end

-- simulator instance
local sim = {}

function sim.new(_, thingbase)


  return setmetatable({
    things = {}
  }, {__index = sim})
end

function sim:add(basething, thingprofile)
  local thing = {
    id = basething.id,
    name = basething.name,
    attrs = {},
    protocols = {},
    servers = {},
  }

  if #(basething.protocols or {}) > 0 then
    for _,protocol in pairs(basething.protocols) do
      thing.protocols[protocol] = true
    end
  else
    thing.protocols = { rpcserver = true }
  end

  for name, params in pairs(thingprofile.profile.attrs) do
    local checker = params.valid
    if type(checker) ~= "function" then
      if type(checker) == "table" then
        local invvalues = {}
        for k,v in pairs(checker) do invvalues[v] = true end
        checker = function(val) return invvalues[val] or false end
      else
        error("invalid value for `valid` for '"..name.."'")
      end
    end

    thing.attrs[name] = {
      value = params.default,
      check = checker
    }
  end

  table.insert(self.things, thing)
end

function sim:run()
  -- spawn SSDP listener to respond for each thing
  cosock.spawn(function() ssdp_listen(self.things) end)

  -- spawn an RPC server per thing
  for _, thing in pairs(self.things) do
    cosock.spawn(
      function()
        local server = rpc()

        local ip, port = server:getsockname()
        thing.servers.rpc = { ip = ip, port = port }

        server:register("getattr", function(attrs)
          local attrvals = {}
          for _, attr in pairs(attrs) do
            attrvals[attr] = assert(thing.attrs[attr].value, "no value")
          end
          return attrvals
        end)
        server:register("setattr", function(attrs)

          -- check all attrs first
          for attr, val in pairs(attrs) do
            if not thing.attrs[attr].check(val) then
              return "bad attr"
            end
          end

          -- apply all attrs
          local changedattrs = {}
          for attr, val in pairs(attrs) do
            thing.attrs[attr].value = val
            changedattrs[attr] = val
          end

          server:notify("attr", changedattrs)
          return "ok"
        end)

	print(string.format("rpcserver started for '%s' on %s:%s", thing.name or thing.id, ip, port))

        server:run()
      end,
      tostring(thing.name or thing.id) .. " rpc server"
    )
  end

  -- run both threads forever
  cosock.run()
end

thingsim.sim = sim

-- shortcut thingsim() - thingsim.sim.new()
local mt = { __call = sim.new }
setmetatable(thingsim, mt)

return thingsim
