"""Bind original Frontier art/audio to uploaded owner-owned IDs; never enables paid products."""
from pathlib import Path
import json
import re

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/frontier'
ASSETS=ROOT/'src/shared/Assets'


def write(path, text): path.write_text(text,encoding='utf-8',newline='\n')


def install():
    uploaded=json.loads((OUT/'uploaded.json').read_text())
    def asset(name):
        entry=uploaded[name]
        assert entry['creatorUserId']=='8318659852' and int(entry['assetId'])>0
        return 'rbxassetid://'+entry['assetId']
    header='-- Original Frontier generated assets, 2026-10-31. CC0. See tools/frontier and NOTICE.md.\n'
    keys=[p.stem for p in OUT.glob('*.png') if not p.stem.startswith('map_')]
    write(ASSETS/'UiIcons.luau',header+'return {\n'+''.join(f' {k}="{asset(k+".png")}",\n' for k in sorted(keys))+'}\n')
    write(ASSETS/'Branding.luau',header+f'return {{app_icon="{asset("app_icon.png")}",logo_mark="{asset("app_icon.png")}"}}\n')
    maps={p.stem[4:]:asset(p.name) for p in OUT.glob('map_*.png')}
    write(ASSETS/'MapThumbs.luau',header+'-- Earth thumbnails derive from public-domain Natural Earth / NOAA data.\nreturn {\n'+''.join(f' {k}="{v}",\n' for k,v in sorted(maps.items()))+'}\n')
    audio_keys=OUT/'audio-keys.json'
    if not audio_keys.exists():
        write(audio_keys,json.dumps({name:re.findall(r'^\s*(\w+) = \{ (?:id|sprite) =', (ASSETS/f'{name}.luau').read_text(encoding='utf-8'),re.M) for name in ['Audio','AudioUI','AudioExtra']},indent=2)+'\n')
    families=json.loads(audio_keys.read_text());regions=json.loads((OUT/'audio-regions.json').read_text())
    def cue_for(key):
        if 'hover' in key: return 'hover'
        if any(k in key for k in ['deny','error','betray']): return 'deny'
        if 'defeat' in key: return 'defeat'
        if any(k in key for k in ['victory','legendary','rare','gamestart']): return 'victory'
        if any(k in key for k in ['alarm','warning','under_attack']): return 'alarm'
        if any(k in key for k in ['explosion','shell_hit','splash','sink','rumble','burst','eliminate']): return 'impact'
        if any(k in key for k in ['launch','whoosh','fire']): return 'launch'
        if any(k in key for k in ['confirm','buy','star','alliance','build','open','conquer','reveal']): return 'confirm'
        return 'click'
    for family,keys in families.items():
        entries=[]
        for key in keys:
            if key in ['menu','war']: continue
            r=regions[cue_for(key)]
            entries.append(f' {key}={{sprite="{asset("cues.wav")}",start={r["start"]},stop={r["stop"]},length={r["length"]:.6f}}},\n')
        music=f'music={{menu={{id="{asset("horizon.wav")}",length=32}},war={{id="{asset("mobilize.wav")}",length=32}}}},\n' if family=='Audio' else ''
        write(ASSETS/f'{family}.luau',header+'return {\n'+music+'sfx={\n'+''.join(entries)+'}}\n')
    write(ASSETS/'Soundtrack.luau',header+f'''return {{
 credit="Original Frontier synthesized soundtrack",license="CC0 1.0",
 tracks={{
  horizon={{id="{asset('horizon.wav')}",length=32,title="Horizon",pack="Frontier Originals"}},
  mobilize={{id="{asset('mobilize.wav')}",length=32,title="Mobilize",pack="Frontier Originals"}}
 }},
 moods={{title={{"horizon"}},wait={{"horizon"}},calm={{"horizon"}},war={{"mobilize"}},victory={{"horizon"}},defeat={{"horizon"}}}}
}}
''')
    atlas=ROOT/'assets/atlas/uploaded.json'
    if atlas.exists():
        design=json.loads(atlas.read_text())
        icon='rbxassetid://'+str(design['emblem']['assetId'])
        coin='rbxassetid://'+str(design['credits']['assetId'])
        ui=(ASSETS/'UiIcons.luau').read_text(encoding='utf-8')
        ui=re.sub(r' credits="[^"]+"',f' credits="{coin}"',ui)
        ui=re.sub(r' app_icon="[^"]+"',f' app_icon="{icon}"',ui)
        write(ASSETS/'UiIcons.luau',ui)
        write(ASSETS/'Branding.luau',header+f'return {{app_icon="{icon}",logo_mark="{icon}",wordmark="rbxassetid://{design["wordmark"]["assetId"]}"}}\n')
    assert len(maps)==8 and all(families.values())
    print('Installed original icons, branding, 8 map previews, all SFX families, and soundtrack.')


if __name__ == '__main__': install()
