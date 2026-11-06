"""Inventory source assets and every runtime manifest ID, preserving evidence and limits."""
from pathlib import Path
import csv
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[2]
DOC=ROOT/'docs/assets'
UPSTREAM='https://github.com/lukechatton/roworld/tree/2bc850dbc253f644fe2640d73b544d963e82fe51/'
REPLACED={'Audio','AudioExtra','AudioUI','Soundtrack','UiIcons','Branding','MapThumbs','CrateModel'}
GENERATORS={'ArsenalArt':'tools/assets/make_arsenal_art.py','ArsenalFx':'tools/assets/make_arsenal_fx.py',
 'ArsenalMaps':'tools/assets/make_arsenal_maps.py','CrateArt':'tools/assets/make_crate_art.py',
 'Flags':'assets/flags/SOURCE.txt','MapFx':'tools/assets/make_map_fx.py','MapSprites':'tools/assets/make_map_sprites.py',
 'RailArt':'tools/assets/make_rail_art.py','ShopFlags':'tools/assets/gen_shop_flags.py',
 'SkinPreviews':'tools/assets/make_skin_previews.py','UIKit':'tools/uikit/make_textures.py','UiShapes':'tools/ui/make_shapes.py'}


def table(path, rows):
    with path.open('w',encoding='utf-8',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator="\n");writer.writeheader();writer.writerows(rows)


def audit():
    atlas_ids={str(v['assetId']):k+'.png' for k,v in json.loads((ROOT/'assets/atlas/uploaded.json').read_text()).items()}
    DOC.mkdir(exist_ok=True,parents=True)
    uploaded=json.loads((ROOT/'assets/frontier/uploaded.json').read_text())
    own={v['assetId']:(k,v) for k,v in uploaded.items()}
    baseline=json.loads((DOC/'baseline-inventory.json').read_text(encoding='utf-8'))
    rows=[]; current=set()
    for p in sorted((ROOT/'src/shared/Assets').glob('*.luau')):
        ids=sorted(set(re.findall(r'rbxassetid://(\d+)',p.read_text(encoding='utf-8'))))
        for id in ids:
            current.add(id)
            ours=id in own or id in atlas_ids
            evidence=('assets/atlas/PROMPTS.json; assets/atlas/'+atlas_ids[id]) if id in atlas_ids else ('tools/frontier/generate_assets.py; assets/frontier/'+own[id][0]) if ours else GENERATORS.get(p.stem,'Review header in '+p.as_posix())
            if id in own and own[id][0].startswith('map_'):
                evidence='tools/frontier/generate_maps.py; '+evidence
            rows.append({'module':p.relative_to(ROOT).as_posix(),'asset_id':id,'decision':'replacement' if ours else 'retain with upstream notices',
                'licence':'CC0 / public-domain map data' if ours else ('Public domain / CC0' if p.stem in ['Flags','ArsenalMaps'] else 'AGPL-3.0 + upstream additional terms'),
                'evidence':evidence,'origin':'Frontier' if ours else UPSTREAM+evidence,
                'limit':'Moderation/access is separate from copyright' if ours else 'Upstream authorship evidence; no independent chain-of-title certification; legacy asset access not guaranteed'})
    removed=[]
    for row in baseline:
        name=Path(row['module']).stem
        if name in REPLACED:
            for id in row['assetIds']:
                assert id not in current, f'Superseded ID still in runtime: {id}'
                removed.append({'module':row['module'],'removed_asset_id':id,'decision':'replace; do not reintroduce without evidence',
                    'reason':'External source missing / unclear permission' if name not in ['MapThumbs'] else 'Regenerated in Frontier palette'})
    table(DOC/'register.csv',rows);table(DOC/'removed.csv',removed)
    flags={code:(licence,title) for code,licence,title in re.findall(r'^([a-z]+)\s+(Public domain|CC0)\s+(.+)$',(ROOT/'assets/flags/SOURCE.txt').read_text(encoding='utf-8'),re.M)}
    files=[]
    for p in sorted((ROOT/'assets').rglob('*')):
        if not p.is_file(): continue
        rel=p.relative_to(ROOT).as_posix();family=p.relative_to(ROOT/'assets').parts[0]
        licence='AGPL-3.0 + upstream additional terms';basis='RoWorld authored project source; see module/generator and root LICENSE'
        if family=='flags' and p.stem in flags:
            licence,title=flags[p.stem];basis='assets/flags/SOURCE.txt: https://commons.wikimedia.org/wiki/File:'+title.replace(' ','_')
        elif family=='atlas':
            licence='CC0 to the extent rights exist' if p.suffix=='.png' else 'AGPL-3.0 project metadata'
            basis='Built-in imagegen original output; assets/atlas/PROMPTS.json; NOTICE.md'
        elif family=='frontier':
            licence='CC0 / public-domain map data' if p.suffix in ['.png','.wav'] else 'AGPL-3.0 project metadata'
            basis='Original generated output; tools/frontier; NOTICE.md'
        files.append({'file':rel,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'licence':licence,'evidence':basis,
                      'limit':'Documented evidence, not a third-party ownership warranty'})
    table(DOC/'file-register.csv',files)
    print(f'Audit: {len(rows)} runtime references, {len(current)} unique IDs, {len(removed)} superseded references, {len(files)} source assets')


if __name__=='__main__': audit()
