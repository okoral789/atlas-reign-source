local heading=require("../src/client/Map/FleetHeading")
-- Current SimWarships._set_course emits a complete UNIT_PATH, with prev_tile=-1.
local path={650,651,652,716,780,779}
assert(heading(path,64,.2,-1)==0)
assert(heading(path,64,2.2,-1)==90)
assert(heading(path,64,4.2,-1)==180)
assert(heading(path,64,100,-1)==180)
assert(heading({716},64,0,652)==90)
assert(heading({652},64,0,-1)==nil and heading({},64,0,-1)==nil)
assert(heading({652},64,0,652)==nil)
print("PASS fleet heading: current full routes turn east/south/west; legacy movement and stationary states")
