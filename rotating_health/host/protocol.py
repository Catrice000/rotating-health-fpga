"""Version 1 health protocol. No packet arrival timestamps are used as sample time."""
import struct

MAGIC = b'\xc3\x3c'
SAMPLE = struct.Struct('<III6hiIHHBBHH')
CONTROL_SAMPLE = struct.Struct('<III6hiIHHBBHHH')

def motor_command(op, value, request_id):
    return packet(0x10, struct.pack('<BHH', op, value, request_id))

def crc16(data):
    crc = 0xffff
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ (0x1021 if crc & 0x8000 else 0)) & 0xffff
    return crc

def packet(kind, payload):
    body = bytes((kind, len(payload))) + payload
    return MAGIC + body + struct.pack('<H', crc16(body))

class Decoder:
    def __init__(self):
        self.buffer = bytearray()
        self.errors = 0

    def feed(self, data):
        self.buffer.extend(data)
        result = []
        while True:
            pos = self.buffer.find(MAGIC)
            if pos < 0:
                self.buffer[:] = self.buffer[-1:] if self.buffer[-1:] == MAGIC[:1] else b''
                break
            if pos:
                del self.buffer[:pos]
            if len(self.buffer) < 4:
                break
            length = self.buffer[3]
            if length > 96:
                del self.buffer[0]; self.errors += 1; continue
            if len(self.buffer) < length + 6:
                break
            body = bytes(self.buffer[2:4+length])
            expected = struct.unpack('<H', self.buffer[4+length:6+length])[0]
            if crc16(body) != expected:
                del self.buffer[0]; self.errors += 1; continue
            kind = self.buffer[2]
            result.append((kind, bytes(self.buffer[4:4+length])))
            del self.buffer[:length+6]
        return result

def unpack_sample(data):
    if len(data) not in (SAMPLE.size, CONTROL_SAMPLE.size):
        raise ValueError('sample packet size')
    v = (CONTROL_SAMPLE if len(data)==44 else SAMPLE).unpack(data)
    result = dict(seq=v[0], ms=v[1], errors=v[2], raw=v[3:6], filtered=v[6:9],
                count=v[9], edges=v[10], invalid=v[11], flags=v[12], device=v[13],
                pins=v[14], sample_drops=v[15], spectrum_drops=v[16])
    result['target_rpm']=v[17] if len(v)>17 else None
    return result

def unpack_features(data):
    if len(data) != 72:
        raise ValueError('feature packet size')
    frame = int.from_bytes(data[:4], 'little')
    f = int.from_bytes(data[4:68], 'little')
    def get(offset, width, signed=False):
        value = (f >> offset) & ((1 << width)-1)
        return value-(1 << width) if signed and value & (1 << (width-1)) else value
    return dict(frame=frame, energy=[get(i*48,48) for i in range(3)], fourth=get(144,64),
                peak=[get(208+i*16,16) for i in range(3)], zc=get(256,16),
                s1=get(272,32,True), c1=get(304,32,True), s2=get(336,32,True),
                c2=get(368,32,True), delta=get(400,32,True), health=data[68], fault=data[69])
