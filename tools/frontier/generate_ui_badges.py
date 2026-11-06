"""Original illustrated 2D menu badges and bonus missiles. No external artwork."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/ui-v7'
S = 3
INK = '#092436'
GOLD = '#ffcf56'
WHITE = '#f0f9ff'
CYAN = '#36ecdb'
BLUE = '#54adfa'


def icon(kind):
    im = Image.new('RGBA', (256*S, 256*S))
    d = ImageDraw.Draw(im)
    def poly(points, fill, edge=INK, width=5):
        p = [(round(x*S), round(y*S)) for x, y in points]
        d.polygon(p, fill=fill)
        if edge:
            d.line(p+[p[0]], fill=edge, width=width*S, joint='curve')
    def box(rect, fill, radius=6, edge=INK, width=5):
        d.rounded_rectangle(tuple(round(v*S) for v in rect), radius=radius*S, fill=fill, outline=edge, width=width*S)
    def disc(rect, fill, edge=INK, width=5):
        d.ellipse(tuple(round(v*S) for v in rect), fill=fill, outline=edge, width=width*S)
    def line(points, fill, width=5):
        d.line([(round(x*S), round(y*S)) for x, y in points], fill=fill, width=width*S, joint='curve')
    def star(x, y, r, color):
        import math
        poly([(x+math.cos(i*math.pi/5-math.pi/2)*(r if i%2==0 else r*.45),
               y+math.sin(i*math.pi/5-math.pi/2)*(r if i%2==0 else r*.45)) for i in range(10)],color,width=3)
    if kind == 'customize':
        for x,y,c in ((39,64,BLUE),(60,47,CYAN),(81,30,GOLD)):
            box((x,y,x+128,y+160),c,18)
            line([(x+18,y+19),(x+105,y+19)],WHITE,4)
        disc((105,63,167,125),'#dff8ff')
        disc((120,77,152,109),CYAN,width=3)
        poly([(155,185),(183,121),(210,132),(184,198)],'#e0f4ff')
        poly([(183,121),(200,94),(210,132)],'#e48a6c')
        poly([(155,185),(184,198),(166,219),(146,213)],BLUE)
    elif kind == 'ladder':
        poly([(46,61),(82,61),(86,116),(62,116),(49,101)],GOLD)
        poly([(174,61),(210,61),(207,101),(194,116),(170,116)],GOLD)
        box((105,132,151,184),GOLD)
        poly([(72,41),(184,41),(175,113),(154,143),(102,143),(81,113)],GOLD)
        poly([(81,50),(110,50),(110,127),(96,114)],'#ffe9a1',None)
        star(130,86,25,'#de8c2c')
        box((80,177,176,197),GOLD)
        box((65,199,191,221),BLUE)
        box((93,204,163,216),CYAN,3,width=2)
    elif kind == 'armory':
        poly([(41,189),(82,59),(103,29),(119,65),(126,201)],BLUE)
        poly([(138,200),(130,71),(148,38),(171,68),(215,188)],'#ff8069')
        poly([(56,177),(29,206),(52,212),(76,189)],CYAN)
        poly([(187,176),(226,201),(211,217),(169,191)],GOLD)
        line([(77,102),(111,109)],WHITE,9)
        line([(142,110),(181,101)],GOLD,9)
        poly([(69,206),(118,157),(166,206),(143,230),(116,211),(92,230)],GOLD)
    elif kind == 'shop':
        box((54,69,204,210),CYAN,13)
        box((43,104,212,134),GOLD,7)
        box((111,69,143,210),GOLD,4)
        poly([(54,69),(80,44),(220,44),(204,69)],'#b0fff0')
        box((94,43,127,70),GOLD,4,width=3)
        disc((148,133,225,213),GOLD)
        poly([(174,155),(197,155),(197,184),(174,184)],'#d3852e',width=3)
        line([(62,145),(62,190),(90,190)],WHITE,4)
    elif kind == 'help':
        poly([(33,53),(80,43),(127,58),(176,43),(223,53),(223,204),(176,195),(127,211),(80,195),(33,204)],BLUE)
        poly([(42,46),(86,39),(127,53),(127,199),(83,184),(42,190)],WHITE)
        poly([(127,53),(170,39),(214,46),(214,190),(170,184),(127,199)],'#b1fff0')
        line([(127,58),(127,198)],INK,4)
        for y in (76,96,116): line([(56,y),(104,y+5)],'#7495a5',5)
        disc((145,91,204,150),GOLD,width=3)
        line([(160,111),(169,120),(189,102)],INK,6)
    elif kind == 'party':
        disc((28,83,99,154),BLUE)
        disc((156,83,227,154),GOLD)
        box((18,147,110,209),BLUE,28)
        box((145,147,237,209),GOLD,28)
        disc((80,38,176,137),WHITE)
        box((68,133,188,221),CYAN,34)
        poly([(101,153),(128,174),(155,153),(147,204),(108,204)],BLUE,width=3)
    elif kind == 'reports':
        poly([(50,48),(128,26),(206,48),(200,146),(179,187),(128,225),(77,187),(56,146)],BLUE)
        poly([(70,62),(128,46),(186,62),(182,139),(164,174),(128,201),(92,174),(74,139)],'#123f61')
        line([(108,79),(108,169)],WHITE,9)
        poly([(112,76),(164,87),(151,118),(112,108)],GOLD)
        star(166,169,24,CYAN)
    elif kind == 'mega':
        poly([(58,169),(47,221),(91,205),(103,179)],'#d44356')
        poly([(153,75),(192,45),(203,84),(181,104)],'#d44356')
        poly([(67,167),(101,109),(158,68),(187,90),(167,142),(103,193)],'#ff7568')
        poly([(101,109),(158,68),(183,85),(126,124),(87,174),(71,165)],'#ffaf87',None)
        poly([(159,68),(166,37),(186,29),(204,40),(202,64),(187,90)],'#223b54')
        line([(96,121),(149,159)],GOLD,17)
        disc((106,115,148,157),GOLD,width=3)
        disc((122,131,132,141),INK,None)
        star(46,69,18,GOLD)
        star(215,165,12,CYAN)
        poly([(81,191),(73,214),(50,229),(46,213),(61,189)],GOLD,width=3)
    elif kind == 'scatter':
        for x,y,c in ((49,48,'#ffd574'),(108,24,'#ffac56'),(168,48,'#ff8069')):
            poly([(x,y+33),(x+13,y),(x+27,y+33),(x+27,y+82),(x,y+82)],c)
            line([(x+4,y+43),(x+23,y+43)],WHITE,5)
        box((59,124,203,211),'#f08a36',12)
        disc((59,109,203,151),GOLD)
        disc((74,119,188,139),'#6e3942',width=3)
        box((84,151,105,198),GOLD,3,width=3)
        box((155,151,176,198),'#ffbd66',3,width=3)
        poly([(109,211),(151,211),(156,232),(104,232)],BLUE)
    else:
        raise ValueError(kind)
    return im.resize((256,256), Image.Resampling.LANCZOS)


if __name__ == '__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    keys=['customize','ladder','armory','shop','help','party','reports','mega','scatter']
    sheet=Image.new('RGBA',(768,768))
    for i,key in enumerate(keys):
        im=icon(key)
        assert im.getbbox() and im.getextrema()[3][1]==255
        sheet.paste(im,((i%3)*256,(i//3)*256))
    path=OUT/'badges.png';sheet.save(path)
    bg=Image.new('RGBA',sheet.size,'#082033');bg.alpha_composite(sheet);bg.convert('RGB').save(OUT/'preview.png')
    (OUT/'generated.json').write_text(json.dumps({'generator':'tools/frontier/generate_ui_badges.py','license':'CC0-1.0',
        'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'keys':keys,'size':[768,768],'cell':256},indent=2)+'\n',encoding='utf-8')
    print('Generated nine original illustrated badges and bonus weapons.')
