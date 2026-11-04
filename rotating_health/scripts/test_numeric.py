from pathlib import Path
import sys,struct,unittest
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'host'))
from protocol import Decoder,packet,crc16,unpack_features,SAMPLE
from analysis import metrics,diagnosis

class ProtocolTests(unittest.TestCase):
 def test_crc_vector(self):self.assertEqual(crc16(b'123456789'),0x29b1)
 def test_fragmentation_and_corruption(self):
    frame=packet(1,bytes(range(42)));bad=bytearray(frame);bad[-1]^=1
    d=Decoder();result=[]
    for b in b'garbage'+bad+frame:result+=d.feed(bytes([b]))
    self.assertEqual(result,[(1,bytes(range(42)))]);self.assertGreater(d.errors,0)
 def test_rtl_uart(self):
    data=bytes.fromhex((ROOT/'sim/control_uart.hex').read_text())
    self.assertEqual(Decoder().feed(data),[(17,bytes.fromhex('010003005a000000')),(1,bytes(range(44))),(3,bytes(range(44,116)))])
 def test_fft_against_numpy(self):
    v=np.load(ROOT/'sim/fft_reference.npy');g=np.loadtxt(ROOT/'sim/fft_output.csv',delimiter=',')
    for i,x in enumerate(v):
        a=g[g[:,0]==i];reference=np.fft.rfft(x*np.hanning(256))/256*64
        error=np.max(np.abs(a[:,2]+1j*a[:,3]-reference))
        self.assertLess(error,8) # < 0.125 ADC count in normalized FFT
 def test_feature_layout(self):
    value=(25600 << 0)|(10 << 208)|(((-100)&0xffffffff) << 400)
    payload=struct.pack('<I',3)+value.to_bytes(64,'little')+bytes([100,0,0,0])
    f=unpack_features(payload);self.assertEqual(f['energy'][0],25600);self.assertEqual(f['peak'][0],10);self.assertEqual(f['delta'],-100)
 def test_no_baseline_not_healthy(self):
    f=dict(fault=0,health=100,delta=5000)
    m=dict(rpm=60,rms=[.01]*3,a1=.01,a2=.001,kurtosis=3)
    text,h=diagnosis(f,m,19|256)
    self.assertIsNone(h);self.assertIn('未标定',text)

if __name__=='__main__':unittest.main(verbosity=2)
