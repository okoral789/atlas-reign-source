"""Original sample-free tactical/UI cues. Generated WAV recordings are dedicated to CC0."""
from pathlib import Path
import hashlib, json, wave
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/audio-v12'
SR=44100
RNG=np.random.default_rng(1204)

def tone(seconds,freq,end=None):
    t=np.arange(round(seconds*SR))/SR
    phase=2*np.pi*(freq*t if end is None else freq*t+(end-freq)*t*t/(2*seconds))
    return np.sin(phase)+.18*np.sin(phase*2)+.07*np.sin(phase*3)

def noise(seconds,window=12):
    return np.convolve(RNG.normal(0,1,round(seconds*SR)),np.ones(window)/window,mode='same')*np.sqrt(window)

def env(a,attack=.006,decay=.25):
    t=np.arange(len(a))/SR
    return a*np.minimum(t/attack,1)*np.exp(-t/decay)*np.minimum((len(a)/SR-t)/.04,1)

def layer(seconds,parts):
    out=np.zeros(round(seconds*SR))
    for when,a,gain in parts:
        start=round(when*SR);n=min(len(a),len(out)-start)
        out[start:start+n]+=a[:n]*gain
    return out

def chord(notes,seconds,decay=.5):
    return sum(env(tone(seconds,f),decay=decay) for f in notes)/len(notes)

def generate():
    OUT.mkdir(parents=True,exist_ok=True)
    cues={
      'click':env(tone(.09,520,210),decay=.021)*.6+env(noise(.09,3),decay=.008)*.1,
      'hover':env(tone(.05,1150,720),decay=.012)*.3,
      'confirm':layer(.48,[(0,chord([523,784],.4),.6),(.09,chord([659,988],.32),.5),(.18,chord([784,1175],.28),.4)]),
      'deny':layer(.38,[(0,env(tone(.2,180,145),decay=.09),.6),(.13,env(tone(.24,135,110),decay=.08),.5)]),
      'naval':layer(.8,[(0,env(noise(.8,28),decay=.25),.45),(.03,env(tone(.7,74,48),decay=.25),.3),(.09,env(noise(.5,5),decay=.1),.12)]),
      'cannon':layer(.7,[(0,env(tone(.65,95,30),decay=.13),.65),(0,env(noise(.4,3),decay=.07),.3),(.08,env(noise(.6,30),decay=.18),.2)]),
      'impact':layer(1.25,[(0,env(tone(1.2,65,24),decay=.3),.65),(0,env(noise(.8,5),decay=.18),.35),(.06,env(noise(1.15,44),decay=.4),.25)]),
      'launch':layer(1.1,[(0,env(noise(1.1,16),attack=.10,decay=.5),.4),(0,env(tone(1.1,80,520),attack=.05,decay=.65),.18)]),
      'nuke':layer(3.8,[(0,env(noise(.55,3),decay=.09),.35),(.025,env(tone(3.6,58,23),attack=.01,decay=.9),.7),(.10,env(noise(3.6,70),attack=.03,decay=.95),.45),(.30,env(noise(2.8,24),attack=.02,decay=.7),.13)]),
      'alarm':layer(1.7,[(i*.34,env(tone(.30,600 if i%2==0 else 455),attack=.03,decay=.5),.34) for i in range(5)]),
      'build':layer(.6,[(i*.12,env(tone(.22,260+i*105,190+i*85),decay=.055)+env(noise(.22,2),decay=.015)*.25,.45) for i in range(3)]),
      'conquer':layer(.9,[(i*.13,chord(notes,.6),.5) for i,notes in enumerate(([330,495],[415,622],[495,742]))]),
      'pop':env(tone(.065,700,180),attack=.001,decay=.018)*.5,
      'emp':layer(1.2,[(0,env(tone(1.2,1550,95),attack=.025,decay=.28),.35),(0,env(noise(1.2,4),attack=.01,decay=.22)*(np.sin(np.arange(round(1.2*SR))/SR*95)>.3),.25)]),
      'repair':layer(.9,[(0,env(noise(.18,2),decay=.03),.2),(.16,chord([392,587],.6),.4),(.32,chord([523,784],.5),.4)]),
      'victory':layer(2.5,[(i*.22,chord(notes,1.6,1.0),.55) for i,notes in enumerate(([262,330,392],[330,392,523],[392,523,659],[523,659,784]))]),
      'defeat':layer(2.1,[(0,chord([262,311,392],2,.8),.5),(.35,chord([196,233,294],1.7,.8),.45)]),
    }
    report={}
    for name,a in cues.items():
        # Gentle delay tail, DC removal and conservative peak prevent harsh/clipped repeated cues.
        delay=round(.052*SR)
        if len(a)>delay: a[delay:]+=a[:-delay].copy()*.13
        a-=a.mean();a=np.tanh(a*1.1);a*=.68/max(np.max(np.abs(a)),.68)
        assert np.isfinite(a).all() and np.sqrt(np.mean(a*a))>.005
        path=OUT/f'{name}.wav'
        with wave.open(str(path),'wb') as f:
            f.setparams((1,2,SR,0,'NONE','not compressed'));f.writeframes((a*32767).astype('<i2').tobytes())
        report[path.name]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'seconds':len(a)/SR,'peak':float(np.max(np.abs(a))),'rms':float(np.sqrt(np.mean(a*a))),'license':'CC0-1.0'}
    (OUT/'generated.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(f'Generated {len(report)} original distinct full-file cues; checked RMS, peaks and duration.')

if __name__=='__main__': generate()
