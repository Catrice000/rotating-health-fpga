from pathlib import Path
import sys
p=Path(__file__).resolve().parents[1];sys.path.insert(0,str(p/'host'))
from protocol import motor_command
commands=[(3,90,1),(2,0,2),(3,45,8),(4,1,3),(1,0,4),(4,1,5),(3,9,6),(2,0,7)]
data=b''.join(motor_command(*c) for c in commands)
(p/'sim/commands.hex').write_text('\n'.join(f'{b:02x}' for b in data)+'\n')
(p/'sim/speed_period.hex').write_bytes((p/'rtl/speed_period.hex').read_bytes())
