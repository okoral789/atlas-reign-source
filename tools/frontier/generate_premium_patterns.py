"""Original multicolor territory patterns; stable historical livery IDs are preserved."""
from pathlib import Path
import math

ROOT=Path(__file__).resolve().parents[2]
BASE=''' {id="fleet_copper",name="Copper Vanguard",robux=99,fleet_tint=0xF1BF86,accent=0xB77536,mask={"##......","..##....","....##..","......##"}},
 {id="fleet_crimson",name="Crimson Standard",robux=99,fleet_tint=0xEF9991,accent=0xB84941,mask={"#...#...","#...#...","########","#...#..."}},
 {id="fleet_obsidian",name="Obsidian Admiralty",robux=149,fleet_tint=0xB3AAC8,accent=0x494254,mask={"#...#",".#.#.","..#..",".#.#.","#...#"}},
'''


def pixel(kind,x,y):
    if kind=='circuit':
        if (x,y) in ((3,3),(11,11),(3,11),(11,3)):return '2'
        if (y==3 and 3<=x<=11) or (x==11 and 3<=y<=11) or (y==11 and 3<=x<=6) or (x==3 and 6<=y<=11):return '1'
    elif kind=='lava':
        vein=(x+round(2*math.sin(y*.7))+y//4)%12
        if vein==0:return '2'
        if vein in (1,11):return '1'
    elif kind=='royal':
        d=abs(x%8-4)+abs(y%8-4)
        if d==3:return '1'
        if d==0:return '2'
    elif kind=='frost':
        if (x-y*2)%13==0 or (x+y*2)%17==0:return '1'
        if (x*5+y*3)%37==0:return '2'
    elif kind=='nebula':
        if (x,y) in ((3,3),(12,10),(8,14)):return '2'
        if (x,y) in ((2,3),(4,3),(3,2),(3,4),(11,10),(13,10),(12,9),(12,11)):return '1'
        if (x+y*3)%23==0:return '3'
    elif kind=='topo':
        r=math.sqrt((x-8)**2+(y-8)**2)
        if round(r)%5==0:return '1'
        if x==8 and y==8:return '2'
    return '.'


if __name__=='__main__':
    designs=[('circuit','pattern_circuit','Neon Circuit',149,0x72FFF0,[0x145C73,0x7DFFDA]),
      ('lava','pattern_lava','Molten Rift',149,0xFFAC46,[0x7B2837,0xFFB547]),
      ('royal','pattern_royal','Royal Filigree',149,0xFFE5A1,[0xA57B39,0xFFF1B0]),
      ('frost','pattern_frost','Frost Prism',99,0xDDFFFF,[0x84D9F2,0xF0FFFF]),
      ('nebula','pattern_nebula','Nebula Grid',149,0xE5A1FF,[0x9F6AF1,0xE3F8FF,0xF87DCC]),
      ('topo','pattern_topo','Tactical Contours',99,0xBAFDD0,[0x247D79,0xAEF9CE])]
    text='-- Original Atlas Reign cosmetic liveries and procedural patterns. Never random rewards.\nreturn {\n'+BASE
    masks=[]
    for kind,key,name,price,trim,colors in designs:
        mask=[''.join(pixel(kind,x,y) for x in range(16)) for y in range(16)]
        marked=sum(c!='.' for row in mask for c in row)
        assert 8<=marked<=140, (key,marked)
        assert all(len(row)==16 for row in mask)
        masks.append(tuple(mask))
        effect={'circuit':'neon','lava':'flame','royal':'royal','frost':'frost','nebula':'nebula','topo':'scan'}[kind]
        text+=f' {{id="{key}",name="{name}",robux={price},fleet_tint=0x{trim:06X},premium=true,'+(f'effect="{effect}",' if effect else '')+'scale=1,alpha=230,colors={'+','.join(f'0x{c:06X}' for c in colors)+'},mask={\n'
        text+=''.join('  "'+row+'",\n' for row in mask)+' }},\n'
    assert len(set(masks))==6
    for key,name,effect,tint in [('border_aurora','Aurora Flow','aurora',0x77FFD8),('border_storm','Storm Voltage','electric',0x87CAFF),('border_tidal','Tidal Surge','tide',0x6AE9FF),('border_eclipse','Eclipse Halo','eclipse',0xD19CFF)]:
        text+=f' {{id="{key}",name="{name}",robux=149,fleet_tint=0x{tint:06X},premium=true,effect="{effect}",scale=1,alpha=230,colors={{0x{tint:06X},0xFFFFFF}},mask={{"12","21"}}}},\n'
    text=text.replace('fleet_tint=', 'border=true,fleet_tint=')
    (ROOT/'src/shared/Data/FleetStyles.luau').write_text(text+'}\n',encoding='utf-8')
    from PIL import Image,ImageDraw,ImageFont
    out=ROOT/'assets/premium-v8';out.mkdir(exist_ok=True)
    def rgb(c):return (c>>16&255,c>>8&255,c&255)
    image=Image.new('RGB',(1000,620),'#082033');draw=ImageDraw.Draw(image)
    font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',16)
    colors=[('ARCTIC PEARL',0xE5FCFF),('OBSIDIAN',0x252A40),('NEON MAGENTA',0xFF249F),('IMPERIAL GOLD',0xFFCC33),('VOID VIOLET',0x7C3CFF)]
    draw.text((20,14),'EXCLUSIVE COLORS / PATTERNS PREVIEWED ON BLUE',font=font,fill='#e6f7ff')
    for i,(name,color) in enumerate(colors):
        x=20+i*196;draw.rounded_rectangle((x,48,x+178,124),radius=12,fill=rgb(color),outline='#a4c5e2',width=2)
        draw.text((x,134),name,font=font,fill='#e6f7ff')
    for i,(kind,_,name,_,_,palette) in enumerate(designs):
        x,y=20+i%3*327,194+i//3*207;draw.text((x,y),name.upper(),font=font,fill='#ffcf56')
        for py in range(16):
            for px in range(32):
                code=pixel(kind,px%16,py);base=rgb(0x53A9FF)
                color=base if code=='.' else tuple(round(a*(1-230/255)+b*230/255) for a,b in zip(base,rgb(palette[int(code)-1])))
                draw.rectangle((x+px*9,y+30+py*9,x+(px+1)*9,y+30+(py+1)*9),fill=color)
    image.save(out/'preview.png')
    print('Generated six original multicolor patterns; three existing liveries preserved.')
