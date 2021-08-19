package = "thingsim"
version = "dev-1"
source = {
  url = "git://github.com/SmartThingsDevelopers/thingsim.git",
  branch = "main"
}
description = {
  summary = "A smarthome network device simulator",
  homepage = "https://github.com/SmartThingsCommunity/thingsim",
  license = "Apache-2.0"
}
dependencies = {
  "lua >= 5.1 < 6",
  "luasocket >= 3.0-rc1",
  "cosock",
  "logface",
  "dkjson",
  "luafilesystem",
  "argparse",
}
build = {
  type = "builtin",
  modules = {
     ["thingsim"] = "src/thingsim.lua",
     ["thingsim.rpc"] = "src/rpc/init.lua",
  },
  install = {
    bin = {
      thingsim = "bin/thingsim.lua",
    }
  }
}
