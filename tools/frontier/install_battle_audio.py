"""Bind original full-file battle cues, keeping earlier audio as loading fallbacks."""
from pathlib import Path
import hashlib
import json
ROOT=Path(__file__).resolve().parents[2]
FAMILIES={
 'click':['ui_click','ui_tab','ui_back','order_ack','countdown_tick','countdown_tick_1','countdown_tick_2','countdown_tick_3','countdown_tick_4','countdown_tick_5','card_flip','spectate_switch'],
 'hover':['ui_hover'], 'confirm':['ui_confirm','ui_open','star_get','star_tick','buy_spend','crate_shimmer','reveal_common','reveal_rare'],
 'deny':['ui_error','ui_locked','betrayal'], 'naval':['boat_launch','ship_sink','shell_splash'],
 'cannon':['warship','shell_fire','sam_launch'], 'impact':['shell_hit','eliminate','crate_land','crate_drop'],
 'launch':['nuke_launch','card_whoosh','attack_launch'], 'nuke':['nuke_explosion'],
 'alarm':['nuke_alarm','under_attack','ally_request'], 'build':['build','crate_rattle'],
 'conquer':['conquer','spawn_confirm','game_start','alliance','queue_start','unlock','crate_open'],
 'pop':['expand','expand_pop','sam_intercept','crate_preview_common','crate_preview_rare'],
 'emp':['emp_pulse'], 'repair':['fleet_repair','reinforce'],
 'victory':['victory','countdown_gamestart','crate_preview_epic','crate_preview_legendary','reveal_epic','reveal_legendary'], 'defeat':['defeat'],
}
def install():
    out=ROOT/'assets/audio-v12';uploaded=json.loads((out/'uploaded.json').read_text());meta=json.loads((out/'generated.json').read_text())
    extra=ROOT/'assets/audio-cartoony'
    overrides=json.loads((extra/'uploaded.json').read_text()) if (extra/'uploaded.json').exists() else {}
    entries=[]
    for cue,names in FAMILIES.items():
        row=uploaded[cue+'.wav'];assert row['creatorUserId']=='8318659852' and row['sha256']==meta[cue+'.wav']['sha256']
        for name in names:
            if name not in overrides:
                entries.append(f' {name}={{id="rbxassetid://{row["assetId"]}",length={meta[cue+".wav"]["seconds"]}}},\n')
    for name,row in overrides.items():
        assert row['creatorUserId']=='8318659852' and row['response']['moderationResult']['moderationState']=='Approved'
        assert hashlib.sha256((extra/(name+'.wav')).read_bytes()).hexdigest()==row['sha256']
        entries.append(f' {name}={{id="rbxassetid://{row["assetId"]}",length={row["seconds"]}}},\n')
    (ROOT/'src/shared/Assets/BattleAudio.luau').write_text('-- Audio: CC0 synthesis/water + CC BY 3.0 launch/explosion; see assets/audio-cartoony/sources.json.\nreturn {sfx={\n'+''.join(entries)+'}}\n',encoding='utf-8')
    print(f'Installed {len(entries)} sound bindings; {len(overrides)} recorded battle replacements.')
if __name__=='__main__': install()
