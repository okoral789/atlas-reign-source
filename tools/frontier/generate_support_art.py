"""Original 2D tactical equipment art. PNG outputs are CC0; no third-party images."""
from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/support-v9'
S=4
EDGE='#082338'

def icon(kind):
    im=Image.new('RGBA',(256*S,256*S));d=ImageDraw.Draw(im)
    def box(rect,color,r=8):d.rounded_rectangle(tuple(v*S for v in rect),r*S,fill=color,outline=EDGE,width=5*S)
    def poly(points,color):
        p=[(x*S,y*S) for x,y in points];d.polygon(p,fill=color);d.line(p+[p[0]],fill=EDGE,width=5*S,joint='curve')
    def circle(rect,color):d.ellipse(tuple(v*S for v in rect),fill=color,outline=EDGE,width=5*S)
    if kind=='emp':
        box((42,150,215,212),'#404f8b');box((55,157,202,174),'#9a8fff',4)
        for x in (57,177):box((x,207,x+24,224),'#d3e6f5',3)
        box((77,101,180,158),'#1c6589');box((97,119,159,143),'#b1ffff',5)
        circle((81,26,176,121),'#43dbef');circle((99,42,158,101),'#b8ffff')
        poly([(133,49),(110,80),(127,80),(117,105),(151,70),(134,70)],'#ffdc66')
        for xy in ((38,52,49,106),(207,52,218,106)):box(xy,'#8e9bff',4)
        d.arc((17*S,12*S,238*S,139*S),205,335,fill='#72f6ff',width=8*S)
        d.arc((45*S,29*S,210*S,124*S),200,340,fill='#d5ffff',width=5*S)
        for x in (66,91,116,141,166):box((x,185,x+14,197),'#52f0ff',2)
    else:
        poly([(29,146),(213,146),(234,167),(193,204),(58,204),(21,176)],'#357b9b')
        poly([(38,151),(207,151),(220,165),(190,180),(51,180)],'#a1dded')
        box((71,105,182,150),'#5977ac');box((101,82,154,111),'#c4edf7')
        box((116,49,132,85),'#6c9cb9',3)
        poly([(52,130),(76,118),(76,144),(52,144)],'#e4f9ff')
        box((150,94,173,106),'#0d324e',2)
        circle((157,18,239,100),'#55e5ac')
        box((188,33,208,85),'#f4ffec',3);box((172,49,225,69),'#f4ffec',3)
        for x in (61,96,131,166):box((x,183,x+23,193),'#4dffbd',2)
        for y,x in ((219,41),(231,96)):
            d.line((x*S,y*S,(x+92)*S,y*S),fill='#69f6e5',width=5*S)
    return im.resize((256,256),Image.Resampling.LANCZOS)

if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True);rows=[]
    preview=Image.new('RGB',(620,330),'#082033');d=ImageDraw.Draw(preview)
    font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',20)
    for i,key in enumerate(('emp','fleet_repair')):
        im=icon(key);path=OUT/(key+'.png');im.save(path)
        assert im.getbbox() and im.getextrema()[3][1]==255
        rows.append({'key':key,'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        preview.paste(im,(i*310+27,20),im)
        d.text((i*310+58,285),key.replace('_',' ').upper(),font=font,fill='#effaff')
    assert rows[0]['sha256']!=rows[1]['sha256']
    preview.save(OUT/'preview.png')
    (OUT/'generated.json').write_text(json.dumps({'generator':'tools/frontier/generate_support_art.py','license':'CC0-1.0','assets':rows},indent=2)+'\n',encoding='utf-8')
    print('Generated two original 2D support equipment icons.')
