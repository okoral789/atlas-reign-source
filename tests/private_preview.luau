local Release = require("../src/shared/Data/ReleaseConfig")
Release.CHANNEL = "private"
local OwnerAccess = require("../src/server/OwnerAccess")
local LobbyHttp = require("../src/server/Lobbies/LobbyHttp")

assert(OwnerAccess.allowed(42, 42, false), "the owner can join the private test")
assert(not OwnerAccess.allowed(99, 42, false), "another account cannot join")
assert(not OwnerAccess.allowed(0, 0, false), "an unpublished place never grants live access")
assert(OwnerAccess.allowed(-1, 0, true), "local Studio testing remains available")
assert(not LobbyHttp.ENABLED, "the private test does not use the original developer's lobby service")
print("private_preview: all passed")
