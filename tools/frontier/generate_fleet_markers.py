"""Original grayscale 2D fleet masks. Roblox tints the entire silhouette with its nation color."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont, ImageChops

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/fleet-v4'
S = 4


def marker(kind):
    image = Image.new('RGBA', (256*S, 256*S))
    draw = ImageDraw.Draw(image)
    def polygon(points, fill, outline=50, width=6):
        draw.polygon([(x*S,y*S) for x,y in points], fill=(fill,fill,fill,255))
        if outline is not None:
            draw.line([(x*S,y*S) for x,y in points+[points[0]]], fill=(outline,outline,outline,255), width=width*S, joint='curve')
    def box(rect, fill, radius=0):
        draw.rounded_rectangle(tuple(v*S for v in rect), radius=radius*S, fill=(fill,fill,fill,255))
    def disc(rect, fill):
        draw.ellipse(tuple(v*S for v in rect), fill=(fill,fill,fill,255))
    if kind == 'landing':
        polygon([(47,46),(196,46),(220,68),(220,188),(196,210),(47,210)],255)
        box((66,65,170,191),65,7)
        for x in (81,123):
            for y in (81,123,165): disc((x,y,x+19,y+19),240)
        box((183,64,208,192),110,2)
        polygon([(188,93),(207,128),(188,163)],255,None)
    elif kind == 'trade':
        polygon([(25,91),(194,91),(244,128),(194,165),(25,165),(15,153),(15,103)],255)
        box((28,103,54,153),65,4)
        for x in (67,111,155):
            box((x,104,x+32,152),55,3);box((x+5,109,x+11,147),190,1)
    elif kind == 'warship':
        polygon([(15,86),(151,78),(203,96),(248,128),(203,160),(151,178),(15,170)],255)
        polygon([(24,99),(153,91),(220,128),(153,165),(24,157)],175,None)
        box((80,102,121,154),45,5);box((91,109,109,147),245,2)
        for x in (43,158):
            disc((x-17,111,x+17,145),40);disc((x-10,118,x+10,138),210)
            for y in (119,132): box((x,y,x+48,y+6),255,1)
        box((74,70,126,82),230,2);box((74,174,126,186),230,2)
    else:
        raise ValueError(kind)
    return image.resize((256,256), Image.Resampling.LANCZOS)


if __name__ == '__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    records=[]
    preview=Image.new('RGB',(780,330),(8,29,47))
    draw=ImageDraw.Draw(preview)
    font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',18)
    color=(110,183,87)
    for row,kind in enumerate(('landing','trade','warship')):
        mask=marker(kind);path=OUT/(kind+'.png');mask.save(path)
        assert mask.size==(256,256) and mask.getextrema()[3][1]==255
        assert all(r==g==b for r,g,b,a in mask.get_flattened_data() if a), 'Tint mask must be grayscale'
        records.append({'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'size':[256,256]})
        draw.text((16,row*110+45),kind.upper(),font=font,fill=(235,250,255))
        tinted=ImageChops.multiply(mask,Image.new('RGBA',mask.size,(*color,255)))
        for col,angle in enumerate((0,45,90)):
            rotated=tinted.rotate(-angle,resample=Image.Resampling.BICUBIC)
            large=rotated.resize((88,88),Image.Resampling.LANCZOS)
            preview.paste(large,(180+col*200,row*110+6),large)
            small=rotated.resize((26 if kind=='warship' else 15,)*2,Image.Resampling.LANCZOS)
            preview.paste(small,(285+col*200,row*110+44),small)
    preview.save(OUT/'preview.png')
    assert len({r['sha256'] for r in records})==3, 'Fleet silhouettes must differ'
    (OUT/'generated.json').write_text(json.dumps({'generator':'tools/frontier/generate_fleet_markers.py','license':'CC0-1.0','assets':records},indent=2)+'\n',encoding='utf-8')
    print('Generated three original grayscale fleet masks and rotation review.')
