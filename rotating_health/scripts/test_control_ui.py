"""No real serial port or motor is touched by this UI test."""
import sys,struct,tkinter as tk
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'host'))
from app import Workstation
from protocol import SAMPLE,Decoder,unpack_sample

class Fake:
    def __init__(self):self.sent=[]
    def write(self,b):self.sent.append(b);return len(b)
    def close(self):pass
    @property
    def in_waiting(self):return 0
    def read(self,n):return b''

root=tk.Tk();app=Workstation(root);fake=Fake();app.ser=fake;app.mode='live'
body=SAMPLE.pack(1,100,0,0,0,256,0,0,0,0,0,0,3,229,0,0,0)+struct.pack('<H',60)
app.accept_sample(unpack_sample(body));app.rpm_set.set('90');app.apply_speed()
kind,payload=Decoder().feed(fake.sent[-1])[0]
op,value,rid=struct.unpack('<BHH',payload)
assert (kind,op,value)==(16,3,90)
assert '等待' in app.control_status.get()
app.on_packet(17,struct.pack('<HBBHBB',rid,3,0,90,0,0))
assert '已确认' in app.control_status.get()
app.poll();assert '目标 60 RPM' in app.motor_actual.get() # latest telemetry is authoritative
app.reset();assert Decoder().feed(fake.sent[-1])[0][1][0]==1
app.demo();app.calibrate()
for _ in range(10):app.demo_tick()
assert app.reference
root.after(200,app.close);root.mainloop()
print('CONTROL_UI_PASS')
