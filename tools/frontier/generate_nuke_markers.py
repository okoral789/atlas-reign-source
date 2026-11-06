"""Original 2D missiles, pointing right. Full color identifies equipment, stern band identifies owner."""
from pathlib import Path
import hashlib,json,math
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/nukes-v8'
S=4
EDGE='#092236'


def missile(kind):
    im=Image.new('RGBA',(256*S,256*S));d=ImageDraw.Draw(im)
    def poly(points,color,edge=EDGE,width=5):
        p=[(int(x*S),int(y*S)) for x,y in points];d.polygon(p,fill=color)
        if edge:d.line(p+[p[0]],fill=edge,width=width*S,joint='curve')
    def box(rect,color,r=3):d.rounded_rectangle(tuple(v*S for v in rect),radius=r*S,fill=color,outline=EDGE,width=4*S)
    def disc(rect,color):d.ellipse(tuple(v*S for v in rect),fill=color,outline=EDGE,width=4*S)
    if kind=='atom':
        poly([(29,101),(12,66),(65,84),(87,100)],'#ffb52e');poly([(29,155),(12,190),(65,172),(87,156)],'#ffb52e')
        poly([(28,98),(171,86),(222,103),(246,128),(222,153),(171,170),(28,158)],'#ffd94c')
        poly([(42,104),(164,95),(202,107),(164,116),(42,119)],'#fff4b7',None)
        poly([(201,95),(222,103),(246,128),(222,153),(201,161)],'#e6842a')
        box((45,96,62,160),'#e69029');disc((107,105,153,151),EDGE)
        disc((122,120,138,136),'#ffd94c')
        for a in (0,120,240):
            rad=math.radians(a);x=130+math.cos(rad)*15;y=128+math.sin(rad)*15
            d.ellipse(((x-5)*S,(y-5)*S,(x+5)*S,(y+5)*S),fill='#ffd94c')
    elif kind=='hydrogen':
        poly([(38,101),(24,59),(83,94),(89,128),(83,162),(24,197),(38,155)],'#2979b5')
        poly([(30,104),(189,93),(245,128),(189,163),(30,152)],'#e8fbff')
        poly([(44,109),(180,102),(203,115),(46,122)],'#ffffff',None)
        for x in (83,139):box((x,98,x+17,158),'#49d7e2')
        poly([(200,100),(245,128),(200,156)],'#29658d')
    elif kind=='mirv':
        box((25,83,151,173),'#bb3b9d',12)
        box((47,90,65,166),'#ff75dc')
        for y in (72,111,150):
            poly([(133,y),(196,y),(240,y+17),(196,y+34),(133,y+34)],'#fa68d2')
            poly([(196,y),(240,y+17),(196,y+34)],'#173c66')
        box((91,94,110,162),'#24344f')
    elif kind=='mega':
        poly([(30,99),(40,50),(105,84),(137,128),(105,172),(40,206),(30,157)],'#e64b53')
        poly([(21,103),(172,80),(220,103),(248,128),(220,153),(172,176),(21,153)],'#334660')
        poly([(40,110),(168,93),(203,109),(165,116),(40,121)],'#6d8499',None)
        box((80,94,101,162),'#ff6b5a');box((140,87,165,169),'#ffb64c')
        poly([(208,97),(248,128),(208,159)],'#ed5a53')
        disc((115,114,141,140),'#ffda65')
    elif kind=='scatter':
        poly([(36,96),(24,63),(85,85),(117,128),(85,171),(24,193),(36,160)],'#fa9b4a')
        poly([(24,100),(171,86),(235,128),(171,170),(24,156)],'#b888f6')
        box((43,99,60,157),'#f2d5ff')
        for y in (98,122,146):
            poly([(103,y),(179,y-6),(206,y+6),(179,y+18),(103,y+12)],'#e8d9ff',width=3)
        poly([(198,103),(242,128),(198,153)],'#f49b4d')
    elif kind=='warhead':
        poly([(41,105),(22,80),(77,94),(90,128),(77,162),(22,176),(41,151)],'#8bacc3')
        poly([(32,102),(164,91),(244,128),(164,165),(32,154)],'#e8f7ff')
        poly([(165,91),(244,128),(165,165)],'#5b95b7')
        box((62,102,80,154),'#b9e6f0')
    else:raise ValueError(kind)
    return im.resize((256,256),Image.Resampling.LANCZOS)


if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True);records=[]
    preview=Image.new('RGB',(900,520),'#082033');d=ImageDraw.Draw(preview)
    font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',17)
    names=['atom','hydrogen','mirv','mega','scatter','warhead']
    for i,key in enumerate(names):
        im=missile(key);path=OUT/(key+'.png');im.save(path)
        assert im.getbbox() and im.getextrema()[3][1]==255
        records.append({'key':key,'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
        x,y=(i%3)*300,(i//3)*260
        d.text((x+18,y+15),{'mega':'SIEGEBREAKER','scatter':'COMET CLUSTER'}.get(key,key.upper()),font=font,fill='#e6f7ff')
        preview.paste(im.resize((230,190)),(x+30,y+45),im.resize((230,190)))
        for j,angle in enumerate((0,45,90)):
            small=im.rotate(-angle,resample=Image.Resampling.BICUBIC).resize((32,32),Image.Resampling.LANCZOS)
            preview.paste(small,(x+85+j*50,y+220),small)
    assert len({r['sha256'] for r in records})==6
    preview.save(OUT/'preview.png')
    (OUT/'generated.json').write_text(json.dumps({'generator':'tools/frontier/generate_nuke_markers.py','license':'CC0-1.0','assets':records},indent=2)+'\n',encoding='utf-8')
    print('Generated six original colored missile silhouettes and size/rotation review.')
