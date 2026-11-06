-- Original Frontier supply case, 2026-10-31. AGPL-3.0 with terms in LICENSE.
-- Built entirely from Roblox Parts: no external meshes or textures.
local function part(name, size, pos, color, lid)
 return {name=name, size=size, cf=pos, color=color, lid=lid, material="SmoothPlastic"}
end
local navy, teal, brass = {27,49,62}, {58,188,173}, {232,184,90}
return {
 size={5,4.5,5}, hinge={0,2.8,2.5}, mouth={0,2.9,0}, seam={0,2.8,-2.5}, lid_open=115,
 parts={
  part("Case",{5,2.8,5},{0,1.4,0},navy,false),
  part("Lid",{5,1.1,5},{0,3.35,0},teal,true),
  part("Latch",{0.7,1.1,0.2},{0,2.6,-2.6},brass,true),
  part("BandLeft",{0.35,2.8,5.12},{-1.7,1.4,0},brass,false),
  part("BandRight",{0.35,2.8,5.12},{1.7,1.4,0},brass,false),
  part("LidBandLeft",{0.35,1.15,5.12},{-1.7,3.35,0},brass,true),
  part("LidBandRight",{0.35,1.15,5.12},{1.7,3.35,0},brass,true)
 }
}
