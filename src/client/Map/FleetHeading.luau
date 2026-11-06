-- Full UNIT_PATH routes are used by current warships, trade and landings.
-- A single tile plus prev_tile is the legacy UNIT_MOVE representation.
return function(path,W,done,prev_tile)
 local a,b
 if #path>=2 then
  local i=math.min(math.floor(math.max(0,done))+1,#path-1)
  a,b=path[i],path[i+1]
 elseif (prev_tile or -1)>=0 then a,b=prev_tile,path[1] end
 if a==nil or b==nil then return nil end
 local dx,dy=b%W-a%W,math.floor(b/W)-math.floor(a/W)
 return if dx==0 and dy==0 then nil else math.deg(math.atan2(dy,dx))
end
