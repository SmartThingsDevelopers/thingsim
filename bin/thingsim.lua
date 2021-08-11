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

local thingsim = require "thingsim"
local argparse = require "argparse"
local lfs = require "lfs"
local json = require "dkjson"
local log = require "log"

local PROGRAM_NAME = "thingsim"

-- define command structure
local argparser = argparse(PROGRAM_NAME, "A smarthome network device simulator")

-- TODO: add like a wizard or something as the base no-command call
--argparser:require_command(false)

-- TODO: needs log changes
--argparser:flag("-v --verbose")

local runcom = argparser:command("run", "simulate any previously added devices")

local addcom = argparser:command("add", "add new simulated devices")

addcom:argument("type"):choices({"bulb"})
--addcom:mutex(
--  addcom:option("-c --count", "adds <count> number of the described device"),
  addcom:option("-n --name", "gives the device(s) a name" --[[, suffixed with # when using --count"]])
--)
addcom:option("-p --protocols", "restrict which protocols devices should use"):args("*"):choices({"rpcserver"})

local rmcom = argparser:command("rm", "remove existing devices")

rmcom:mutex(
  rmcom:flag("--all -a", "remove all devices"),
  rmcom:argument("id", "the generated ID of the device to remove"):args("?")
)

local showcom = argparser:command("show", "show current devices")

-- TODO:
--runcom:flag("-d --daemon", "run in background, calling `thingsim run` again will reattach")

-- parse command
local args = argparser:parse()


local seeded
function seedonce()
  if not seeded then
    local randfile = io.open("/dev/random")
    if randfile then
      local bytesneeded = string.len(string.pack("T", 0))
      local randbytes = randfile:read(bytesneeded)
      local randnum = string.unpack("T", randbytes)
      math.randomseed(randnum)
    elseif pcall(require, "socket") then
      local socket = require "socket"
      math.randomseed(socket.gettime()*10000)
    else
      log.warn("No good sources of entropy, you might get duplicate UUIDs")
      math.randomseed(os.time() - os.clock() * 1000000)
    end
    seeded = true
  end
end


function randomuuid()
  seedonce()

  return string.format("%08x-%04x-%04x-%04x-%06x%06x",
    math.random(0, 0xffffffff),
    math.random(0, 0xffff),
    math.random(0, 0x0fff) + 0x4000, -- version 4, random
    math.random(0, 0x3fff) + 0x0800, -- variant 1
    math.random(0, 0xffffff),
    math.random(0, 0xffffff))
end

function get_config_dir(program)
  local XDG_CONFIG_HOME = os.getenv("XDG_CONFIG_HOME")

  if XDG_CONFIG_HOME then
    -- ensure trailing slash
    XDG_CONFIG_HOME = string.gsub(XDG_CONFIG_HOME, "/$", "") .. "/"
    return XDG_CONFIG_HOME.."/"..program.."/"
  else
    local home = os.getenv("HOME")
    assert(home, "neither XDG_CONFIG_HOME no HOME set, nowhere to store configs")
    home = string.gsub(home, "/$", "") .. "/"
    return home..".config/"..program.."/"
  end
end

function ensure_devices_config_dir()
  local config_path = get_config_dir(PROGRAM_NAME)
  local devices_config_path = config_path .. "devices/"

  recursive_ensure_dir_path(devices_config_path)
end

function recursive_ensure_dir_path(path)
  log.trace("ensuring dir exists", path)
  local dirs = string.gmatch(path, "([^/]+)")
  local built_path = "/"
  for segment in dirs do
    built_path = built_path .. segment .. "/"

    local attrs = lfs.attributes(built_path)

    if attrs == nil then
      assert(lfs.mkdir(built_path), "could not create path "..built_path)
    elseif attrs.mode ~= "directory" then
      error(built_path.." exists but isn't a directory")
    end
  end
end

function get_device_configs_path()
  local config_path = get_config_dir(PROGRAM_NAME)
  local device_configs_path = config_path .. "devices/"
  return device_configs_path
end

function ensure_device_configs_path()
  local device_configs_path = get_device_configs_path()
  recursive_ensure_dir_path(device_configs_path)
  return device_configs_path
end

function get_all_devices()
  local devices = {}

  local devices_dir = get_device_configs_path()
  local dirattr = lfs.attributes(devices_dir)

  if dirattr and dirattr.mode == "directory" then
    for filename in lfs.dir(devices_dir) do
      if filename ~= "." and filename ~= ".." then
        local file = assert(io.open(devices_dir.."/"..filename), "unable to open device file")
        local encoded_device = assert(file:read('a'), "unable to read device file")
        local device = assert(json.decode(encoded_device), "unable to parse device file as json")

        table.insert(devices, device)
      end
    end
  end

  return devices
end

if args.add then
  log.info(get_config_dir(PROGRAM_NAME), randomuuid())

  local device = {
    id = randomuuid(),
    type = args.type,
    name = args.name,
    protocols = args.protocols
  }

  print(json.encode(device))
  local dir_path = ensure_device_configs_path()
  local device_path = dir_path .. device.id .. ".json"

  local device_file = assert(io.open(device_path, "w"), "failed to open file to save device")
  assert(device_file:write(json.encode(device)), "failed to save device")

  log.info("device "..device.id.." added")
elseif args.rm then
  local device_configs_path = get_device_configs_path()
  if args.all then
    local devices = get_all_devices()
    for _, device in pairs(devices) do
      local devicepath = device_configs_path .. device.id .. ".json"
      os.remove(devicepath)
    end
    assert(lfs.rmdir(device_configs_path))
    print("all device configs removed")
  elseif args.id then
    local device_config_path = device_configs_path .. args.id .. ".json"

    local file_attrs = lfs.attributes(device_config_path)
    if not file_attrs then
      print(string.format("deivce %s not found", args.id))
      return -1
    end

    local file = io.open(device_config_path)
    local encoded_device = file:read('a')
    file:close()
    local device = json.decode(encoded_device)

    os.remove(device_config_path)

    if device and device.name then
      print(string.format("removed %s (%s)", device.name, device.id))
    else
      print(string.format("removed %s", args.id))
    end
  else
    rmcom:error("either --all or <id> must be specified")
  end
elseif args.show then
  local devices = get_all_devices()

  print(string.format("%i devices", #devices))

  local devices_by_type = {}
  for _, device in ipairs(devices) do
      devices_by_type[device.type] = devices_by_type[device.type] or {}
      table.insert(devices_by_type[device.type], device)
  end

  for type, devices in pairs(devices_by_type) do
    print(string.format("%i are of type '%s'", #devices, type))
    table.sort(devices, function(a,b) return a.name and not b.name or (a.name ~= nil and a.name < b.name) end)
    for _, device in ipairs(devices) do
      print(string.format(" * %s (%s)", device.name or "-unnamed-", device.id))
    end
  end
elseif args.run then
  local sim = thingsim()

  for _,device in pairs(get_all_devices()) do
    -- TODO: factor out device type profiles
    if device.type == "bulb" then
      local profile = thingsim.thing{
        attrs = {
          power = {
            valid = { "on", "off" },
            default = "on"
          },
          level = {
            valid = function(val) return val >= 0 and val <= 100 end,
            default = 100,
          }
        }
      }
      sim:add(device, profile)
    else
      log.error("device type not supported: "..tostring(device.type))
    end
  end

  print("ThingSim Starting... (Ctrl+C, Ctrl+C to stop)")

  sim:run()
else
  log.fatal "no command, TODO wizard"
end
