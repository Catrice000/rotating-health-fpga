from pathlib import Path
import math
p=Path(__file__).resolve().parents[1]
for name,func,n in [('sin',lambda i: math.sin(2*math.pi*i/256),256),('cos',lambda i: math.cos(2*math.pi*i/256),256),('hann',lambda i: .5-.5*math.cos(2*math.pi*i/255),256)]:
 vals=[min(32767,max(-32767,round(func(i)*32767))) for i in range(n)]
 (p/'rtl'/f'{name}.hex').write_text('\n'.join(f'{v&65535:04x}' for v in vals)+'\n')

(p/"rtl/speed_period.hex").write_text("\n".join(f"{round(468750/max(10,min(120,i))):05x}" for i in range(128))+"\n")
