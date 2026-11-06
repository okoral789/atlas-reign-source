"""Publish a reviewed local build only to the owner-only private Frontier target, then validate.

Pass --key-file, --build and --sha256. Uses Open Cloud only; never opens Studio or the desktop.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import time
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
UNIVERSE='10774039150'; PLACE='129521354706128'


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--key-file',type=Path,required=True);p.add_argument('--build',type=Path,required=True);p.add_argument('--sha256',required=True);p.add_argument('--record',type=Path,default=ROOT/'build/private-publication-v0.4.1.json');args=p.parse_args()
    key=args.key_file.read_text(encoding='utf-8-sig').strip();build=args.build.read_bytes()
    assert hashlib.sha256(build).hexdigest()==args.sha256, 'Build differs from reviewed checksum'
    assert b'This is a private owner-only test.' in build and b'BUY_FLAG' in build
    config=[item.findtext("./Properties/string[@name='Source']") for item in ET.fromstring(build).iter('Item')
            if item.findtext("./Properties/string[@name='Name']")=='ReleaseConfig']
    assert len(config)==1 and re.search(r'\bCHANNEL\s*=\s*"private"', config[0] or ''), 'Build is not the private release channel'
    def call(path,body=None,content_type='application/json'):
        data=json.dumps(body).encode() if isinstance(body,dict) else body
        req=urllib.request.Request('https://apis.roblox.com/'+path,data=data,headers={'x-api-key':key,'Content-Type':content_type})
        try:
            with urllib.request.urlopen(req,timeout=90) as response:return json.load(response)
        except urllib.error.HTTPError as e:raise RuntimeError(f'Roblox HTTP {e.code}: '+e.read().decode()[:500]) from None
    u=call('cloud/v2/universes/'+UNIVERSE);place=call(f'cloud/v2/universes/{UNIVERSE}/places/{PLACE}')
    assert u['visibility']=='PRIVATE' and u['user']=='users/8318659852'
    assert u['rootPlace']==f'universes/{UNIVERSE}/places/{PLACE}' and place['serverSize']==50
    result=call(f'universes/v1/{UNIVERSE}/places/{PLACE}/versions?versionType=Published',build,'application/xml')
    version=result['versionNumber']
    script='\n'.join((ROOT/'tools/frontier'/name).read_text(encoding='utf-8')
                     for name in ('check_match_rewards.luau','check_cloud.luau'))
    script=f'assert(game.PlaceVersion == {version})\n'+script
    task=call(f'cloud/v2/universes/{UNIVERSE}/places/{PLACE}/versions/{version}/luau-execution-session-tasks',{'script':script,'timeout':'120s'})
    record={'universeId':UNIVERSE,'placeId':PLACE,'version':version,'sha256':args.sha256,'publication':result,'validation':task}
    dest=args.record;dest.write_text(json.dumps(record,indent=2)+'\n', encoding="utf-8", newline="\n")
    print('Published private version',version,flush=True)
    for _ in range(100):
        task=call('cloud/v2/'+task['path']);record['validation']=task
        dest.write_text(json.dumps(record,indent=2)+'\n', encoding="utf-8", newline="\n")
        if task['state'] not in ['QUEUED','PROCESSING']:
            print('Cloud validation:',json.dumps(task),flush=True)
            assert task['state']=='COMPLETE', 'Published build validation failed; inspect recorded task and restore baseline if necessary'
            break
        time.sleep(2)
    else:raise TimeoutError('Published; cloud validation still pending. Resume the recorded task.')
    assert call('cloud/v2/universes/'+UNIVERSE)['visibility']=='PRIVATE'
