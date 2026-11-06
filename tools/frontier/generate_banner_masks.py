"""Encode the existing licensed flag art as compact territory masks; artwork licence is retained."""
from pathlib import Path
from PIL import Image
import json,hashlib
ROOT=Path(__file__).resolve().parents[2]
ABC='123456789abcdefghijklmnopqrstuvwxyz'
def generate():
    out=['-- Territory banner samples from existing assets/shop_flags/art; original artwork licence retained.','return {']
    rows=[]
    for path in sorted((ROOT/'assets/shop_flags/art').glob('*.png')):
        image=Image.open(path).convert('RGB').resize((24,16),Image.Resampling.LANCZOS).quantize(colors=12)
        palette=image.getpalette();indices=list(image.getdata())
        colors=[palette[i*3]*65536+palette[i*3+1]*256+palette[i*3+2] for i in range(12)]
        masks=[''.join(ABC[k] for k in indices[y*24:(y+1)*24]) for y in range(16)]
        assert len(set(map(len,masks)))==1 and len(masks)==16
        out.append(' ["'+path.stem+'"]={colors={'+','.join('0x%06X'%c for c in colors)+'},mask={'+','.join('"'+r+'"' for r in masks)+'}},')
        rows.append({'flag':path.stem,'source':str(path.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    assert len(rows)==38
    out.append('}')
    (ROOT/'src/shared/Data/BannerMasks.luau').write_text('\n'.join(out)+'\n',encoding='utf-8')
    (ROOT/'assets/banner-masks').mkdir(exist_ok=True)
    (ROOT/'assets/banner-masks/sources.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
    print('Encoded 38 flag designs as 24x16 territory masks; no new purchases or artwork.')
if __name__=='__main__':generate()
