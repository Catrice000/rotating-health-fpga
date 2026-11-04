from pathlib import Path
import numpy as np
p=Path(__file__).resolve().parents[1]
t=np.arange(256)
vectors=[np.rint(100*np.sin(2*np.pi*17*t/256)).astype(int),np.where(t==23,300,0),np.random.default_rng(42).integers(-200,200,256)]
np.save(p/'sim/fft_reference.npy',vectors)
(p/'sim/fft_input.hex').write_text('\n'.join(f'{int(x)&65535:04x}' for v in vectors for x in v)+'\n')
for name in ['sin','cos','hann']:(p/'sim'/f'{name}.hex').write_bytes((p/'rtl'/f'{name}.hex').read_bytes())
