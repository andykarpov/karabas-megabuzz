# Generate 44.1 kHz stereo test MP3s (128/320 kbps) with lameenc.
# usage: python3 -m venv venv && venv/bin/pip install lameenc numpy && venv/bin/python -I gen_mp3.py <outdir>
import sys, numpy as np, lameenc
sr=44100; n=sr*2; t=np.arange(n)/sr
rng=np.random.default_rng(1)
def ch(seed,f):
    r=np.random.default_rng(seed)
    x=sum(np.sin(2*np.pi*f*k*t+r.random()*6)/k for k in range(1,12))
    x+=0.6*np.convolve(r.standard_normal(n),np.ones(3)/3,'same')
    return x
L=ch(2,220); R=ch(3,330)
pcm=np.stack([L,R],1); pcm=(pcm/np.abs(pcm).max()*28000).astype('<i2')
for br in (128,320):
    e=lameenc.Encoder(); e.set_bit_rate(br); e.set_in_sample_rate(sr); e.set_channels(2); e.set_quality(2)
    open(f"{sys.argv[1]}/st{br}.mp3","wb").write(e.encode(pcm.tobytes())+e.flush())
