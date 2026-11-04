"""Presentation of FPGA features; heuristic labels require controlled validation."""
import math
FS = 200.0
N = 256
G_PER_COUNT = 0.0039

def metrics(f, ppr=4096):
    rms = [math.sqrt(max(0,e)/N)*G_PER_COUNT for e in f['energy']]
    peak = [v*G_PER_COUNT for v in f['peak']]
    crest = peak[0]/rms[0] if rms[0] > 1e-9 else 0
    kurtosis = f['fourth']*N/(f['energy'][0]**2) if f['energy'][0] else 0
    # 255 intervals between the first and last of 256 samples.
    rpm = f['delta']/ppr*60*FS/(N-1)
    a1 = math.hypot(f['s1'],f['c1'])*2/N*G_PER_COUNT
    a2 = math.hypot(f['s2'],f['c2'])*2/N*G_PER_COUNT
    return dict(rms=rms, peak=peak, crest=crest, kurtosis=kurtosis,rpm=rpm,a1=a1,a2=a2)

def diagnosis(f, m, flags, reference=None,target_rpm=None):
    if f['fault'] & 8 or not flags & 2:
        return '数据无效：检查采集和编码器', None
    if not flags & 16:
        return '停机 / 手动观察', None
    expected = target_rpm or [30,60,120][min(2,(flags>>8)&3)]
    if abs(m['rpm']) < 1:
        return '转动反馈缺失：检查电机与编码器', None
    if abs(abs(m['rpm'])-expected) > expected*.2:
        return '转速异常 / 加速中', min(40,f['health']) if flags & 64 else None
    if not flags & 64:
        return ('正在采集正常基线' if flags & 128 else '未标定：正常稳定运行后按 S1'), None
    if not reference:
        return 'FPGA 基线有效；上位机尚无同工况参考', f['health']
    if abs(abs(m['rpm'])-reference['rpm']) > max(5,reference['rpm']*.2):
        return '工况改变：请重新标定', None
    excess = sum(x*x for x in m['rms']) > max(1e-5, reference['energy']*1.5)
    enough_turns = abs(f['delta'])/reference['ppr'] >= 2
    if excess and enough_turns:
        if m['a2'] > max(.008,reference['a2']*2) and (m['kurtosis']>4 or m['a2']>m['a1']*.5):
            return '疑似松动 / 碰摩（谐波或冲击增强）', f['health']
        if m['a1'] > max(.008,reference['a1']*2) and m['a1']>m['a2']*1.5:
            return '疑似不平衡（1× 转频成分增强）', f['health']
    if excess:
        return ('振动异常；转速过低，阶次判断不足' if not enough_turns else '振动增强，原因待核实'), f['health']
    return '与正常基线接近（规则评估）', f['health']
