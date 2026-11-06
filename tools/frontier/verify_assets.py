"""Check current moderation status of Frontier-owned uploads (API key never persisted)."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import urllib.request

ROOT=Path(__file__).resolve().parents[2]

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--key-file',type=Path,required=True);args=parser.parse_args()
    key=args.key_file.read_text(encoding='utf-8-sig').strip()
    uploaded=json.loads((ROOT/'assets/frontier/uploaded.json').read_text())
    uploaded.update({'atlas/'+n:r for n,r in json.loads((ROOT/'assets/atlas/uploaded.json').read_text()).items()})
    def check(pair):
        name,record=pair
        req=urllib.request.Request('https://apis.roblox.com/assets/v1/assets/'+record['assetId'],headers={'x-api-key':key})
        with urllib.request.urlopen(req,timeout=30) as r: result=json.load(r)
        return {'file':name,'assetId':record['assetId'],'state':result.get('state'),
                'moderation':result.get('moderationResult',{}).get('moderationState'),
                'creationContext':result.get('creationContext')}
    with ThreadPoolExecutor(max_workers=4) as pool: results=list(pool.map(check,uploaded.items()))
    target=ROOT/'build/asset-status.json';target.write_text(json.dumps(results,indent=2)+'\n', encoding="utf-8", newline="\n")
    from collections import Counter
    print('Moderation:',dict(Counter(r['moderation'] for r in results)))
    print('Asset states:',dict(Counter(r['state'] for r in results)))
    assert all(r['state']=='Active' and r['moderation']=='Approved' for r in results), 'Some assets are not approved/active; inspect build/asset-status.json'
