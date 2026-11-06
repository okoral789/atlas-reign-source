"""Original geometric Frontier art and synthesized audio. No external artwork or samples.

Run from any directory with Python + Pillow + numpy. Outputs are CC0; this generator is AGPL-3.0.
"""
from pathlib import Path
import json
import math
import wave
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/frontier'
OUT.mkdir(parents=True, exist_ok=True)
S = 3


def icon(key):
    im = Image.new('RGBA', (128*S, 128*S))
    d = ImageDraw.Draw(im)
    def line(points, width=7):
        d.line([(x*S, y*S) for x,y in points], fill='white', width=width*S, joint='curve')
    def poly(points):
        d.polygon([(x*S,y*S) for x,y in points], fill='white')
    def circle(box, width=6):
        d.ellipse(tuple(int(v*S) for v in box), outline='white', width=width*S)
    def rect(box):
        d.rectangle(tuple(int(v*S) for v in box), fill='white')
    k = key.removeprefix('hud_')
    if k in ('app_icon','frontier'):
        poly([(64,8),(112,36),(112,92),(64,120),(16,92),(16,36)])
        d.polygon([(x*S,y*S) for x,y in [(64,17),(104,40),(104,88),(64,111),(24,88),(24,40)]], fill='#122d3e')
        d.polygon([(x*S,y*S) for x,y in [(43,37),(89,37),(83,49),(57,49),(57,60),(79,60),(73,72),(57,72),(57,94),(43,86)]], fill='#58dec6')
    elif k == 'gold':
        poly([(22,76),(50,76),(59,99),(13,99)])
        poly([(77,76),(105,76),(115,99),(68,99)])
        poly([(49,43),(79,43),(89,68),(39,68)])
    elif k == 'github':
        line([(44,32),(16,64),(44,96)],9); line([(84,32),(112,64),(84,96)],9)
        line([(74,25),(54,103)],7)
    elif k == 'credits':
        poly([(64,10),(108,36),(108,92),(64,118),(20,92),(20,36)])
        d.regular_polygon((64*S,64*S,38*S),6,rotation=30,fill='#00000000')
        line([(80,46),(72,40),(53,40),(42,52),(42,76),(53,88),(72,88),(80,82)],8)
    elif k in ('check',): line([(26,65),(52,91),(104,34)],10)
    elif k in ('close','exit','hud_exit'):
        line([(30,30),(98,98)],9); line([(30,98),(98,30)],9)
    elif k in ('play','chevron'):
        poly([(42,24),(100,64),(42,104)])
    elif k in ('globe',):
        circle((14,14,114,114)); d.ellipse((40*S,14*S,88*S,114*S),outline='white',width=5*S)
        line([(16,64),(112,64)],5); line([(24,38),(104,38)],4); line([(24,90),(104,90)],4)
    elif k in ('info','help'):
        circle((14,14,114,114)); rect((59,53,69,89)); circle((59,32,69,42),5)
    elif k in ('leaderboard','layers'):
        rect((21,69,42,108)); rect((53,26,74,108)); rect((85,49,106,108))
    elif k in ('users','troops','pops'):
        circle((45,20,81,56),16); poly([(25,106),(33,73),(48,64),(80,64),(95,73),(103,106)])
        if k == 'users': circle((10,34,36,60),10); circle((92,34,118,60),10)
    elif k in ('music_on','music_off'):
        line([(49,90),(49,28),(97,19),(97,81)],8); circle((26,78,51,103),10); circle((74,69,99,94),10)
        if k.endswith('off'): line([(18,19),(112,111)],10)
    elif k in ('target','attack','retreat','donate','betray'):
        if k == 'target': circle((20,20,108,108)); circle((45,45,83,83)); line([(64,4),(64,27)]); line([(100,64),(124,64)])
        else:
            line([(22,99),(99,22)],11); poly([(66,18),(110,18),(110,62)])
            if k == 'betray': line([(27,28),(101,102)],9)
    elif k in ('settings','atom','hydrogen','mirv'):
        circle((43,43,85,85),12)
        for a in range(0,360,60):
            x,y=math.cos(math.radians(a)),math.sin(math.radians(a))
            line([(64+x*29,64+y*29),(64+x*50,64+y*50)],10)
    elif k in ('clock','reload'):
        circle((17,17,111,111)); line([(64,34),(64,64),(87,77)],8)
    elif k in ('eye',):
        line([(12,64),(35,37),(64,26),(93,37),(116,64),(93,91),(64,102),(35,91),(12,64)],7); circle((47,47,81,81),10)
    elif k in ('crown',):
        poly([(23,91),(13,35),(45,58),(64,19),(83,58),(115,35),(105,91)]); rect((25,99,103,110))
    elif k in ('boat','port','warship'):
        poly([(14,78),(114,78),(94,103),(34,103)]); rect((44,42,86,73)); rect((59,22,68,43)); line([(16,114),(112,114)],5)
    elif k in ('silo','sam'):
        poly([(64,13),(83,39),(83,83),(96,102),(74,97),(64,111),(54,97),(32,102),(45,83),(45,39)])
    elif k in ('alliance',):
        circle((12,37,72,97),9); circle((56,37,116,97),9)
    elif k in ('skull',):
        circle((26,17,102,91),14); rect((43,83,85,109));
        for x in (48,80): d.ellipse(((x-9)*S,42*S,(x+9)*S,62*S),fill='#00000000')
    else:
        # Buildings and remaining controls use a consistent original silhouette vocabulary.
        rect((25,50,103,110)); poly([(17,49),(64,16),(111,49)])
        for x in (39,65,91): d.rectangle(((x-5)*S,65*S,(x+4)*S,85*S),fill='#00000000')
        if k == 'factory': rect((89,16,102,56))
    im.resize((128,128), Image.Resampling.LANCZOS).save(OUT / f'{key}.png')


def audio():
    sr = 22050
    def write(name, samples):
        data=(np.clip(samples,-.85,.85)*32767).astype('<i2')
        with wave.open(str(OUT/f'{name}.wav'),'wb') as f:
            f.setparams((1,2,sr,0,'NONE','not compressed')); f.writeframes(data.tobytes())
    # Original cues in one sprite: a short silence separates every playback region.
    regions={}; chunks=[]; offset=0
    for name, freq, duration in [('click',740,.10),('hover',990,.06),('confirm',620,.42),('deny',150,.25),('impact',60,.7),('alarm',440,1.2),('launch',180,.6),('victory',523,1.4),('defeat',196,1.1)]:
        t=np.arange(int(sr*duration))/sr
        if name == 'impact':
            rng=np.random.default_rng(47); signal=rng.uniform(-1,1,len(t))*.25+np.sin(2*np.pi*freq*t)*.3
        else:
            phase=2*np.pi*freq*t
            if name == 'launch': phase=2*np.pi*(freq*t+400*t*t)
            if name == 'alarm': phase=2*np.pi*(freq*t+80*np.sin(t*12))
            signal=np.sin(phase)*.25+np.sin(phase*1.5)*.08
        envelope=np.minimum(t/.012,1)*np.exp(-t/(duration*.4))*np.minimum((duration-t)/.025,1)
        cue=signal*envelope; regions[name]={'start':round(offset/sr,6),'stop':round((offset+len(t))/sr,6),'length':len(t)/sr}
        chunks += [cue,np.zeros(sr//4)]; offset += len(t)+sr//4
    write('cues',np.concatenate(chunks))
    # Two original 32-second ambient beds; chords are synthesized, with no sampled recordings.
    for name, notes in [('horizon',[146.832,174.614,220.,261.626]),('mobilize',[130.813,155.563,195.998,233.082])]:
        t=np.arange(32*sr)/sr; mix=np.zeros_like(t)
        for j,freq in enumerate(notes):
            mix += .035*np.sin(2*np.pi*freq*t)*(0.65+.35*np.sin(2*np.pi*(j+1)*t/32)**2)
            mix += .012*np.sin(2*np.pi*freq*2*t)
        fade=np.minimum(t/2,1)*np.minimum((32-t)/2,1)
        write(name,mix*fade)
    (OUT/'audio-regions.json').write_text(json.dumps(regions,indent=2)+'\n', encoding="utf-8", newline="\n")


if __name__ == '__main__':
    import re
    keys=re.findall(r'^\s*(\w+)\s*=\s*"rbxassetid://', (ROOT/'src/shared/Assets/UiIcons.luau').read_text(),re.M)
    keys=sorted(set(keys+['credits','frontier']))
    assert len(keys) >= 47 and {'gold','credits','app_icon'}.issubset(keys), 'Incomplete icon manifest'
    for key in keys: icon(key)
    audio()
    assert all(Image.open(OUT/f'{key}.png').getbbox() for key in keys)
    print(f'Generated {len(keys)} original icon masks and 3 audio files in {OUT}')
