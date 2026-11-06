local fs=require("@lune/fs")
local luau=require("@lune/luau")
local serde=require("@lune/serde")
for _,file in {"release.project.json","default.project.json"} do
 local project=serde.decode("json",fs.readFile(file))
 assert(project.tree.Players["$properties"].CharacterAutoLoads==false)
 assert(project.tree.ReplicatedFirst.AtlasBoot["$path"]=="src/first")
end
local calls={}
local boot=luau.load(fs.readFile("src/first/init.client.luau"))
setfenv(boot,{game={GetService=function(_,name)
 assert(name=="ReplicatedFirst","boot must not wait on characters, map data or artwork")
 return {RemoveDefaultLoadingScreen=function() calls[#calls+1]="dismissed" end}
end}})
boot()
assert(#calls==1 and calls[1]=="dismissed")
print("PASS early client boot dismisses the Roblox screen without a character, menu or image dependency")
