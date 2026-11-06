"""Original 2D neon and flame particles, CC0 PNG outputs; no external art."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter
import hashlib,json
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'assets/territory-v10'
def particle(kind):
    im=Image.new('RGBA',(256,256));d=ImageDraw.Draw(im)
    if kind=='neon':
        d.ellipse((55,55,201,201),fill=(43,235,255,135));im=im.filter(ImageFilter.GaussianBlur(22));d=ImageDraw.Draw(im)
        d.line([(128,38),(218,128),(128,218),(38,128),(128,38)],fill='#6bfaff',width=10)
        d.line([(128,72),(184,128),(128,184)],fill='#e2ffff',width=6)
        d.ellipse((115,115,141,141),fill='#edffff')
    else:
        d.ellipse((67,121,190,237),fill=(255,111,22,190));im=im.filter(ImageFilter.GaussianBlur(17));d=ImageDraw.Draw(im)
        d.polygon([(126,17),(134,90),(174,64),(174,113),(204,145),(197,197),(166,225),(106,227),(66,202),(53,163),(71,115),(76,165),(107,124),(113,67)],fill='#ff793b',outline='#8c3440',width=5)
        d.polygon([(128,84),(142,139),(163,121),(178,164),(165,203),(126,220),(94,201),(86,170),(116,135)],fill='#ffcf62')
        d.polygon([(126,150),(147,179),(141,207),(118,210),(106,191)],fill='#fff6bb')
    return im.resize((128,128),Image.Resampling.LANCZOS)
if __name__=='__main__':
    OUT.mkdir(exist_ok=True);rows=[]
    for key in ('neon','flame'):
        p=OUT/(key+'.png');particle(key).save(p);rows.append({'key':key,'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
    (OUT/'generated.json').write_text(json.dumps({'generator':'tools/frontier/generate_territory_fx.py','license':'CC0-1.0','assets':rows},indent=2)+'\n',encoding='utf-8')
    print('Generated two original 2D territory particles.')
