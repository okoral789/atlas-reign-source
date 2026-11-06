local Codec = require("../src/shared/Core/MapCodec")
local Pixels = require("../src/shared/Assets/MapFxPixels")
local serde = require("@lune/serde")

local rgba = Codec.zstd_decompress(Codec.b64decode(Pixels.data))
assert(Pixels.width == 720 and Pixels.height == 218)
assert(buffer.len(rgba) == Pixels.width * Pixels.height * 4)
assert(serde.hash("sha256", buffer.tostring(rgba)) == "ba423a374c4d4e94bed1ff72e783078a5dba12c6d78a8702b592c3ccadcffa8a")
print("PASS: embedded atlas matches every RGBA pixel in the repository image")
