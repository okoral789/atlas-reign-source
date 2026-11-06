"""Upload only generated Frontier assets to the owner account using Open Cloud (no UI).

Usage: python tools/frontier/upload_assets.py --key-file <path>
Stores resumable, content-addressed results, never the API key. Audio has monthly Roblox quotas.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time
import urllib.request
import urllib.error
import uuid

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/frontier'
OWNER='8318659852'


def upload(path, key, brand="Frontier", description=None):
    boundary=uuid.uuid4().hex
    kind='Audio' if path.suffix == '.wav' else 'Image'
    metadata={'assetType':kind,'displayName':brand+' '+path.stem.replace('_',' '),
              'description':description or 'Original Frontier procedural art/audio. CC0. Generator included in corresponding source.',
              'creationContext':{'creator':{'userId':OWNER}}}
    mime='audio/wav' if kind == 'Audio' else 'image/png'
    body=(f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\nContent-Type: application/json\r\n\r\n'+json.dumps(metadata)+
          f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; filename="{path.name}"\r\nContent-Type: {mime}\r\n\r\n').encode()+path.read_bytes()+f'\r\n--{boundary}--\r\n'.encode()
    def call(url, data=None, content_type=None):
        headers={'x-api-key':key}
        if content_type: headers['Content-Type']=content_type
        try:
            with urllib.request.urlopen(urllib.request.Request(url,data=data,headers=headers),timeout=60) as r: return json.load(r)
        except urllib.error.HTTPError as e:
            raise RuntimeError(f'Roblox HTTP {e.code}: '+e.read().decode()[:350]) from None
    result=call('https://apis.roblox.com/assets/v1/assets',body,f'multipart/form-data; boundary={boundary}')
    operation=result['path']
    for _ in range(40):
        result=call('https://apis.roblox.com/assets/v1/'+operation)
        if result.get('done'):
            if result.get('error'): raise RuntimeError(str(result['error']))
            assert result.get('response',{}).get('assetId'), result
            return result['response']
        time.sleep(1.5)
    raise TimeoutError(f'Asset operation pending: {operation}')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--key-file',type=Path,required=True); parser.add_argument('--only',default='')
    args=parser.parse_args(); key=args.key_file.read_text(encoding='utf-8-sig').strip()
    cache=OUT/'uploaded.json'; uploaded=json.loads(cache.read_text()) if cache.exists() else {}
    for path in sorted(OUT.iterdir()):
        if path.suffix not in ('.png','.wav') or (args.only and path.stem != args.only): continue
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        if uploaded.get(path.name,{}).get('sha256') == digest: continue
        result=upload(path,key)
        uploaded[path.name]={'sha256':digest,'assetId':str(result['assetId']),'creatorUserId':OWNER,'response':result}
        cache.write_text(json.dumps(uploaded,indent=2)+'\n', encoding="utf-8", newline="\n")
        print(path.name,result['assetId'],flush=True)
