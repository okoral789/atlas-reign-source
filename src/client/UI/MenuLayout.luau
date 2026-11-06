-- Logical-pixel geometry for the approved centered wordmark and right-side game tiles.
local Layout={}
local function rect(x,y,w,h) return {x=x,y=y,w=w,h=h} end
function Layout.compact(vp,phone) return phone or vp.X<1280 or vp.Y<640 end
function Layout.make(vp,ins,reserved,phone,count)
 local compact=Layout.compact(vp,phone)
 local x=16+ins.x
 local top=math.max(64,reserved.Max.Y+8)+ins.y
 local width=vp.X-32-ins.x-ins.z
 local height=if compact then (if vp.Y<360 then 84 else 112) else vp.Y-top-ins.w-30
 local out={compact=compact,panel=rect(x,top,width,height),nav={},dock_x=vp.X/2,show_tag=not compact}
 if compact then
  out.logo=rect(8,4,math.min(230,width*.46),height-50)
  out.tag=rect(0,0,0,0)
  out.coin=rect(width-172,12,28,28);out.wallet=rect(width-136,12,128,28)
  for i=1,count do out.nav[i]=rect((i-1)*width/count+4,height-42,width/count-8,34) end
 else
  local logoW=math.min(width*.46,670)
  out.logo=rect((width-logoW)/2,76,logoW,100)
  out.tag=rect((width-logoW)/2,180,logoW,24)
  out.coin=rect(width-390,7,28,28);out.wallet=rect(width-352,7,126,28)
  out.owner=rect(width-214,0,214,44)
  local navX=width-252
  for i=1,5 do out.nav[i]=rect(navX,72+(i-1)*72,252,60) end
  out.nav[6]=rect(0,height-54,260,44)
  if count>6 then out.nav[7]=rect(navX,440,252,38) end
  if count>7 then out.nav[8]=rect(navX,486,252,38) end
 end
 return out
end
function Layout.party(plan,vp,height)
 local p=plan.panel
 local width=math.min(280,vp.X-32)
 local x=if plan.compact then vp.X-width-16 else p.x
 local y=if plan.compact then p.y+p.h+8 else p.y+plan.nav[6].y-height-10
 return rect(math.max(16,math.min(x,vp.X-width-16)),math.max(64,math.min(y,vp.Y-height-24)),width,height)
end
return Layout
