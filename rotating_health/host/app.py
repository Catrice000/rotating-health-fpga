"""Local workstation for EGO1. All live spectra/features come from the FPGA."""
import csv,json,math,struct,sys,time,tkinter as tk
from pathlib import Path
from collections import deque
from tkinter import ttk,messagebox,filedialog
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'deps'))
import numpy as np
import serial
from serial.tools import list_ports
from matplotlib import rcParams
from matplotlib.figure import Figure
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from protocol import Decoder,unpack_sample,unpack_features,motor_command
from analysis import metrics,diagnosis,FS,N,G_PER_COUNT
rcParams['font.sans-serif']=['Microsoft YaHei','SimHei','DejaVu Sans']
rcParams['axes.unicode_minus']=False
BG='#0c1525'; PANEL='#15243a'; FG='#e8f0fc'; MUTED='#9ab0ca'; GREEN='#59d6ab'; ORANGE='#ffbd76'

class Workstation:
 def __init__(self,root):
    self.root=root;root.title('旋转设备多维状态感知与故障识别');root.geometry('1340x940');root.minsize(1040,790);root.configure(bg=BG)
    self.ser=None;self.mode='idle';self.decoder=Decoder();self.last_packet=0;self.last_sample=None;self.sample=None;self.feature=None;self.reference=None
    self.times=deque(maxlen=2000);self.values=[deque(maxlen=2000) for _ in range(3)];self.hist=deque(maxlen=120);self.rpms=deque(maxlen=120);self.healths=deque(maxlen=120)
    self.spectra={};self.record=None;self.record_json=None;self.writer=None;self.record_path=None;self.loglines=deque(maxlen=60);self.last_reason='';self.missing=0;self.last_draw=0;self.baseline_seen=False
    self.command_id=0;self.pending={};self.last_heartbeat=0
    self.ppr=4096
    if (ROOT/'config.json').exists():self.ppr=int(json.loads((ROOT/'config.json').read_text())['ppr'])
    self.replay=[];self.replay_pos=0;self.demo_i=0;self.demo_start=time.monotonic();self.demo_next=self.demo_start;self.demo_learning=False;self.demo_learn_n=0;self.demo_flags=19|16|512;self.demo_ref_energy=None
    top=tk.Frame(root,bg=BG);top.pack(fill='x',padx=20,pady=(16,4))
    tk.Label(top,text='旋转设备健康监测',bg=BG,fg=FG,font=('Microsoft YaHei',22,'bold')).pack(side='left')
    self.connection=tk.StringVar(value='未连接');tk.Label(top,textvariable=self.connection,bg=BG,fg=GREEN,font=('Microsoft YaHei',12)).pack(side='right')
    bar=tk.Frame(root,bg=PANEL);bar.pack(fill='x',padx=20,pady=6)
    self.port=tk.StringVar();self.ports=ttk.Combobox(bar,textvariable=self.port,state='readonly',width=10);self.ports.pack(side='left',padx=10,pady=12)
    for label,fn in [('刷新',self.refresh),('连接 / 断开',self.connect),('离线演示',self.demo),('正常基线',self.calibrate),('记录 / 停止',self.toggle_record),('回放 CSV',self.replay_csv)]:
        tk.Button(bar,text=label,command=fn,bg='#2c4565',fg=FG,relief='flat',padx=9,pady=5).pack(side='left',padx=4)
    self.demo_fault=tk.StringVar(value='正常');self.demo_select=ttk.Combobox(bar,textvariable=self.demo_fault,values=['正常','不平衡演示','松动演示','转速异常演示'],state='readonly',width=14);self.demo_select.pack(side='right',padx=10)
    control=tk.Frame(root,bg=PANEL);control.pack(fill='x',padx=20,pady=5)
    tk.Label(control,text='电机控制',bg=PANEL,fg=FG,font=('Microsoft YaHei',11,'bold')).pack(side='left',padx=12)
    self.rpm_set=tk.StringVar(value='60')
    tk.Label(control,text='目标 RPM',bg=PANEL,fg=MUTED).pack(side='left')
    ttk.Spinbox(control,from_=10,to=120,textvariable=self.rpm_set,width=6).pack(side='left',padx=7,pady=12)
    self.control_buttons=[]
    for text,fn in [('应用转速',self.apply_speed),('启动',lambda:self.send_command(2,0)),('停止',lambda:self.send_command(1,0))]:
        b=tk.Button(control,text=text,command=fn,relief='flat',bg=('#a84444' if text=='停止' else '#276b65'),fg='white',padx=14,pady=5);b.pack(side='left',padx=4);self.control_buttons.append(b)
    self.direction_set=tk.StringVar(value='正向')
    ttk.Combobox(control,textvariable=self.direction_set,values=['正向','反向'],state='readonly',width=6).pack(side='left',padx=(15,4))
    b=tk.Button(control,text='应用方向',command=lambda:self.send_command(4,1 if self.direction_set.get()=='反向' else 0),bg='#2c4565',fg=FG,relief='flat',padx=10,pady=5);b.pack(side='left',padx=4);self.control_buttons.append(b)
    self.control_status=tk.StringVar(value='连接新版 FPGA 后可控制；方向只能停机修改')
    tk.Label(control,textvariable=self.control_status,bg=PANEL,fg=ORANGE,font=('Microsoft YaHei',9),wraplength=360,justify='left').pack(side='left',padx=12)
    self.motor_actual=tk.StringVar(value='电机反馈：等待新版 FPGA 状态，实测转速见 RPM 卡片')
    tk.Label(root,textvariable=self.motor_actual,bg=BG,fg=MUTED,font=('Microsoft YaHei',9),anchor='w').pack(fill='x',padx=23)
    self.reason=tk.StringVar(value='连接开发板，或点击离线演示。演示数据会明确标注。')
    tk.Label(root,textvariable=self.reason,bg=BG,fg=ORANGE,font=('Microsoft YaHei',12,'bold'),anchor='w',wraplength=1250).pack(fill='x',padx=23,pady=6)
    cards=tk.Frame(root,bg=BG);cards.pack(fill='x',padx=20,pady=5)
    self.cards={}
    for title in ['三轴 RMS (g)','转速 (RPM)','健康指数','1× / 2× (g)']:
        f=tk.Frame(cards,bg=PANEL);f.pack(side='left',expand=True,fill='both',padx=3)
        tk.Label(f,text=title,bg=PANEL,fg=MUTED,font=('Microsoft YaHei',10)).pack(anchor='w',padx=15,pady=(9,0))
        v=tk.StringVar(value='—');self.cards[title]=v;tk.Label(f,textvariable=v,bg=PANEL,fg=FG,font=('Segoe UI',19,'bold')).pack(anchor='w',padx=15,pady=(3,10))
    notebook=ttk.Notebook(root);notebook.pack(fill='both',expand=True,padx=20,pady=8)
    plots=tk.Frame(notebook,bg=PANEL);diag=tk.Frame(notebook,bg=PANEL);notebook.add(plots,text='实时波形 / FPGA 频谱 / 转速');notebook.add(diag,text='诊断 / 接线 / 操作记录')
    self.fig=Figure(figsize=(12,5.5),dpi=100,facecolor=PANEL);self.axes=self.fig.subplots(2,2)
    for ax in self.axes.flat:
        ax.set_facecolor(PANEL);ax.tick_params(colors=MUTED);ax.grid(color='#324760',alpha=.45)
        for spine in ax.spines.values():spine.set_color('#324760')
    self.axwave,self.axfft,self.axrpm,self.axhealth=self.axes.flat
    colors=['#69a8ff',GREEN,ORANGE]
    self.wave=[self.axwave.plot([],[],color=c,label=n,linewidth=1)[0] for c,n in zip(colors,'XYZ')]
    self.axwave.set_title('FPGA 去直流 + FIR 振动波形',color=FG);self.axwave.set_ylabel('g',color=MUTED);self.axwave.set_xlabel('FPGA 时间 (s)',color=MUTED);self.axwave.set_ylim(-.3,.3);self.axwave.legend(facecolor=PANEL,labelcolor=FG)
    self.fftline=self.axfft.plot([],[],color=GREEN)[0];self.axfft.set_title('FPGA 256 点 Hann FFT · X 轴',color=FG);self.axfft.set_xlim(0,100);self.axfft.set_ylim(0,.1);self.axfft.set_ylabel('单边幅值 (g)',color=MUTED);self.axfft.set_xlabel('Hz',color=MUTED)
    self.rpmline=self.axrpm.plot([],[],color=colors[0])[0];self.axrpm.set_title('编码器窗口转速',color=FG);self.axrpm.set_ylabel('RPM',color=MUTED)
    self.healthline=self.axhealth.plot([],[],color=ORANGE)[0];self.axhealth.set_title('FPGA 基线健康指数（规则评分）',color=FG);self.axhealth.set_ylim(-5,105)
    self.fig.tight_layout(pad=2);self.canvas=FigureCanvasTkAgg(self.fig,master=plots);self.canvas.get_tk_widget().pack(fill='both',expand=True)
    self.diagnostic=tk.StringVar();tk.Label(diag,textvariable=self.diagnostic,bg=PANEL,fg=FG,font=('Microsoft YaHei',11),justify='left',anchor='nw',wraplength=1200).pack(fill='x',padx=20,pady=15)
    tk.Label(diag,text='S0：启动 / 停止电机　S4：停止优先（按键去抖约 20 ms）　S1：采集正常基线\n停机时 S2 改方向，S3 切换 30 / 60 / 120 RPM。默认 60 RPM、16 细分，带启动加速。\n编码器：A→J5 25 / H14，B→27 / E17，3.3V 供电并共地。\nADXL345：SCL→17 / E15，SDA→19 / D15，CS→3.3V，SDO→GND。\nD36A：ST1→29 / K13，DIR1→31 / H17，EN1→30 / J13，独立 12V 供电并共地。\n标定必须使用已确认正常、固定安装的设备；改变安装位置、负载或转速后重新标定。',bg=PANEL,fg=MUTED,font=('Microsoft YaHei',10),justify='left').pack(anchor='w',padx=20)
    self.log=tk.Text(diag,height=9,bg=BG,fg=MUTED,font=('Consolas',10),relief='flat');self.log.pack(fill='both',expand=True,padx=20,pady=15)
    self.footer=tk.StringVar(value='230400 baud · 200 Hz ODR · 256 点 FFT · 0.78125 Hz / bin · 编码器默认 4096 count/rev')
    tk.Label(root,textvariable=self.footer,bg=BG,fg=MUTED,font=('Microsoft YaHei',9),anchor='w').pack(fill='x',padx=23,pady=(0,10))
    self.refresh();root.after(30,self.poll);root.protocol('WM_DELETE_WINDOW',self.close)
 def note(self,text):
    self.loglines.append(time.strftime('%H:%M:%S')+' '+text);self.log.delete('1.0','end');self.log.insert('end','\n'.join(self.loglines));self.log.see('end')
 def refresh(self):
    ports=list(list_ports.comports());self.ports['values']=[p.device for p in ports];usb=[p.device for p in ports if 'USB' in p.hwid.upper() and 'BTHENUM' not in p.hwid.upper()]
    if not self.ser and len(usb)==1:self.port.set(usb[0])
 def reset(self):
    if self.ser:
        try:self.ser.write(motor_command(1,0,0))
        except (serial.SerialException,OSError):pass
        self.ser.close();self.ser=None
    self.pending.clear()
    self.mode='idle';self.decoder=Decoder();self.sample=None;self.feature=None;self.last_sample=None;self.last_packet=0;self.reference=None;self.baseline_seen=False;self.spectra.clear();self.times.clear();[v.clear() for v in self.values];self.hist.clear();self.rpms.clear();self.healths.clear();self.missing=0
    for v in self.cards.values():v.set('—')
    for line in [*self.wave,self.fftline,self.rpmline,self.healthline]:line.set_data([],[])
 def connect(self):
    if self.ser:self.reset();self.connection.set('已断开');return
    if not self.port.get():messagebox.showinfo('选择串口','请刷新并选择开发板 USB 串口。');return
    self.reset()
    try:self.ser=serial.Serial(self.port.get(),230400,timeout=0,write_timeout=.2)
    except (serial.SerialException,OSError) as e:messagebox.showerror('连接失败',str(e));return
    self.mode='live';self.reason.set('等待完整健康监测比特流的数据…');self.note('连接 '+self.port.get()+'，请使用 rotating_health.bit')
 def demo(self):
    self.reset();self.mode='demo';self.demo_i=0;self.demo_next=time.monotonic();self.demo_learning=False;self.demo_learn_n=0;self.demo_ref_energy=None;self.demo_flags=19|16|512;self.note('进入离线演示：所有数据均为合成数据')
 def calibrate(self):
    if self.mode=='demo':self.demo_learning=True;self.demo_learn_n=0;self.demo_flags=(self.demo_flags&~64)|128;self.reference=None;self.baseline_seen=False;self.note('离线模拟基线采集');return
    if self.mode!='live':messagebox.showinfo('基线','请先连接实际设备，或进入离线演示。');return
    self.reference=None;self.baseline_seen=False
    messagebox.showinfo('正常基线','确认机械安装固定、设备处于正常稳定运行状态后，按开发板 S1。\nFPGA 会采集 8 个合格窗口，约 10.24 秒；低速、加速或异常数据会延长标定。\n界面按钮不会远程启动电机。')
 def toggle_record(self):
    if self.record:self.stop_record();return
    name=filedialog.asksaveasfilename(defaultextension='.csv',filetypes=[('CSV','*.csv')],initialfile='health_'+time.strftime('%Y%m%d_%H%M%S')+'.csv')
    if not name:return
    self.record_path=Path(name);self.record=open(name,'w',newline='',encoding='utf-8-sig');self.writer=csv.writer(self.record)
    self.writer.writerow(['mode','seq','ms','raw_x','raw_y','raw_z','filtered_x','filtered_y','filtered_z','encoder_count','flags','errors','invalid'])
    self.record_json=open(str(self.record_path)+'.jsonl','w',encoding='utf-8');self.note('开始记录 '+name)
 def stop_record(self):
    if self.record:self.record.close();self.record_json.close();self.record=None;self.record_json=None;self.writer=None;self.note('记录已保存')
 def replay_csv(self):
    name=filedialog.askopenfilename(filetypes=[('CSV','*.csv')]);
    if not name:return
    self.reset()
    try:
        with open(name,encoding='utf-8-sig') as f:self.replay=list(csv.DictReader(f))
        if not self.replay or 'filtered_x' not in self.replay[0]:raise ValueError('文件不是本软件记录格式')
    except (OSError,ValueError) as e:messagebox.showerror('回放失败',str(e));return
    self.mode='replay';self.replay_pos=0;self.demo_next=time.monotonic();self.reason.set('记录回放：波形与计数来自文件；当前硬件状态未知');self.note('回放 '+name)
 def accept_sample(self,s):
    if self.sample and s['ms']<self.sample['ms']:
        self.times.clear();[q.clear() for q in self.values];self.last_sample=None;self.reference=None;self.baseline_seen=False
        self.note('FPGA 时间已重置：清除旧参考和波形')
    self.sample=s;self.last_packet=time.monotonic()
    if s['seq']==self.last_sample:return
    if self.last_sample is not None:
        gap=(s['seq']-self.last_sample)&0xffffffff
        if gap>1:self.missing+=gap-1
    self.last_sample=s['seq']
    if s['flags']&2:
        self.times.append(s['ms']/1000)
        for q,v in zip(self.values,s['filtered']):q.append(v*G_PER_COUNT)
    if self.writer:self.writer.writerow([self.mode,s['seq'],s['ms'],*s['raw'],*s['filtered'],s['count'],s['flags'],s['errors'],s['invalid']])
 def accept_feature(self,f):
    self.feature=f
    if not self.sample:return
    m=metrics(f,self.ppr);flags=self.sample['flags']
    if flags&128:self.baseline_seen=False;self.reference=None
    if flags&64 and not self.baseline_seen:
        self.reference=dict(energy=sum(x*x for x in m['rms']),a1=m['a1'],a2=m['a2'],rpm=abs(m['rpm']),ppr=self.ppr);self.baseline_seen=True
        self.note('捕获同工况参考；FPGA 正常基线有效')
    text,health=diagnosis(f,m,flags,self.reference,self.sample.get('target_rpm'))
    if self.mode=='demo':text='【合成演示】'+text
    self.reason.set(text)
    if text!=self.last_reason:self.note(text);self.last_reason=text
    self.cards['三轴 RMS (g)'].set(' / '.join('%.3f'%v for v in m['rms']))
    self.cards['转速 (RPM)'].set('%+.1f'%m['rpm'])
    self.cards['健康指数'].set(str(health)+'/100' if health is not None else '未评估')
    self.cards['1× / 2× (g)'].set('%.3f / %.3f'%(m['a1'],m['a2']))
    self.hist.append(self.sample['ms']/1000);self.rpms.append(m['rpm']);self.healths.append(float('nan') if health is None else health)
    if self.record_json:self.record_json.write(json.dumps(dict(type='features',ms=self.sample['ms'],mode=self.mode,features=f,metrics=m,diagnosis=text),ensure_ascii=False)+'\n')
 def apply_speed(self):
    try:
        rpm=int(self.rpm_set.get())
        if not 10<=rpm<=120:raise ValueError()
    except (ValueError,tk.TclError):messagebox.showinfo('转速范围','请输入 10～120 的整数 RPM。');return
    self.send_command(3,rpm)
 def send_command(self,op,value):
    if self.mode!='live' or not self.ser or (op!=1 and (not self.sample or self.sample.get('target_rpm') is None or time.monotonic()-self.last_packet>1)):
        messagebox.showinfo('尚不能控制','请连接新版控制比特流，并等待实时状态数据。');return
    if op==4 and self.sample['flags']&16:
        messagebox.showinfo('请先停机','运行中不允许换向。请停止并确认停止状态后再应用方向。');return
    if len(self.pending)>=6 and op!=1:return
    self.command_id=(self.command_id+1)&65535
    try:self.ser.write(motor_command(op,value,self.command_id))
    except (serial.SerialException,OSError) as e:self.note('控制发送失败：'+str(e));return
    self.pending[self.command_id]=(time.monotonic(),op)
    self.control_status.set('命令已发送，等待 FPGA 确认…')
 def accept_ack(self,data):
    if len(data)!=8:return
    request,op,status,rpm,direction,run=struct.unpack('<HBBHBB',data)
    if request not in self.pending:return
    self.pending.pop(request)
    names={1:'停止',2:'启动',3:'调速',4:'方向'}
    if status==0:
        text='FPGA 已确认%s：%d RPM，%s，%s'%(names.get(op,'命令'),rpm,'反向' if direction else '正向','运行命令有效' if run else '已停止')
    else:text='FPGA 拒绝%s：%s'%(names.get(op,'命令'),{1:'参数超出范围',2:'必须先停止',3:'停止键或时钟保护有效',4:'不支持的命令'}.get(status,'未知错误'))
    self.control_status.set(text);self.note(text)
 def on_packet(self,kind,data):
    try:
        if kind==0x11:self.accept_ack(data)
        elif kind==1:self.accept_sample(unpack_sample(data))
        elif kind==3:self.accept_feature(unpack_features(data))
        elif kind==2 and len(data)==14:
            frame,k,re,im=struct.unpack('<IHii',data)
            if k>128:return
            if frame not in self.spectra:
                if len(self.spectra)>3:self.spectra.pop(next(iter(self.spectra)))
                self.spectra[frame]={}
            self.spectra[frame][k]=(re,im)
            if len(self.spectra[frame])==129:
                arr=np.array([self.spectra[frame][i] for i in range(129)])
                amp=np.hypot(arr[:,0],arr[:,1])/64*(2*N/127.5)*G_PER_COUNT;amp[0]/=2;amp[-1]/=2
                self.fftline.set_data(np.arange(129)*FS/N,amp);self.axfft.set_ylim(0,max(.01,float(amp.max())*1.2))
                if self.record_json:self.record_json.write(json.dumps(dict(type='spectrum',frame=frame,amplitude_g=amp.tolist()))+'\n')
    except (ValueError,struct.error) as e:self.note('丢弃不兼容数据：'+str(e))
 def demo_tick(self):
    t=np.arange(N)/FS+self.demo_i/FS;fault=self.demo_fault.get();amp=.025 if fault=='正常' else .13
    rpm=35 if fault=='转速异常演示' else 120;frequency=rpm/60;theta=2*np.pi*frequency*t
    x=amp*np.sin(theta)+.003*np.sin(2*np.pi*23*t)
    if fault=='松动演示':x+=.11*np.sin(2*theta)+.04*(np.sin(9*theta)**9)
    ys=.02*np.sin(theta+.8);zs=.015*np.sin(theta+1.2)
    raw=np.rint(np.column_stack([x,ys,zs])/G_PER_COUNT).astype(int)
    if self.demo_learning:
        self.demo_learn_n+=1
        if self.demo_learn_n>=8:self.demo_flags=(self.demo_flags|64)&~128;self.demo_learning=False;self.demo_ref_energy=sum(float((a*a).sum()) for a in raw.T)
    energy=[int((a*a).sum()) for a in raw.T];health=100
    if self.demo_ref_energy and sum(energy)>self.demo_ref_energy*1.5:health=40
    for i,row in enumerate(raw):
        j=self.demo_i+i
        self.accept_sample(dict(seq=j+1,ms=round((j+1)*1000/FS),errors=0,raw=tuple(row+[0,0,256]),filtered=tuple(row),count=round((j+1)/FS*frequency*self.ppr),edges=round((j+1)/FS*frequency*self.ppr),invalid=0,flags=self.demo_flags,device=229,pins=0,sample_drops=0,spectrum_drops=0))
    counts=raw[:,0];f=dict(frame=self.demo_i//N,energy=energy,peak=[int(np.abs(a).max()) for a in raw.T],fourth=sum(int(a)**4 for a in counts),zc=int(np.sum(np.diff(np.sign(counts))!=0)),
        s1=round(float(np.dot(counts,np.sin(theta)))),c1=round(float(np.dot(counts,np.cos(theta)))),s2=round(float(np.dot(counts,np.sin(2*theta)))),c2=round(float(np.dot(counts,np.cos(2*theta)))),delta=round(frequency*(N-1)/FS*self.ppr),health=health,fault=1 if health<100 else 0)
    self.accept_feature(f)
    spectrum=np.fft.rfft(counts*np.hanning(N))/N*64
    for k,v in enumerate(spectrum):self.on_packet(2,struct.pack('<IHii',f['frame'],k,round(v.real),round(v.imag)))
    self.demo_i+=N
 def draw(self):
    if self.times:
        t=self.times[-1]
        for line,values in zip(self.wave,self.values):line.set_data(self.times,values)
        self.axwave.set_xlim(max(0,t-10),max(10,t));limit=max(.03,max(abs(v) for q in self.values for v in q)*1.15);self.axwave.set_ylim(-limit,limit)
    if self.hist:
        for ax,line,values in [(self.axrpm,self.rpmline,self.rpms),(self.axhealth,self.healthline,self.healths)]:line.set_data(self.hist,values);ax.set_xlim(max(0,self.hist[-1]-60),max(60,self.hist[-1]))
        limit=max(30,max(abs(v) for v in self.rpms)*1.2);self.axrpm.set_ylim(-limit,limit)
    self.canvas.draw_idle()
 def poll(self):
    now=time.monotonic()
    if self.ser:
        try:
            for kind,data in self.decoder.feed(self.ser.read(min(self.ser.in_waiting,65536))):self.on_packet(kind,data)
        except (serial.SerialException,OSError) as e:self.reset();self.reason.set('串口异常：'+str(e))
    if self.mode=='demo' and now>=self.demo_next:self.demo_tick();self.demo_next=now+N/FS
    if self.mode=='replay' and now>=self.demo_next:
        for _ in range(10):
            if self.replay_pos>=len(self.replay):self.connection.set('回放结束');break
            r=self.replay[self.replay_pos];self.replay_pos+=1
            self.accept_sample(dict(seq=int(r['seq']),ms=int(r['ms']),raw=tuple(int(r['raw_'+a]) for a in 'xyz'),filtered=tuple(int(r['filtered_'+a]) for a in 'xyz'),count=int(r['encoder_count']),flags=int(r['flags']),errors=int(r['errors']),invalid=int(r['invalid']),edges=0,device=0,pins=0,sample_drops=0,spectrum_drops=0))
        self.demo_next=now+.05
    if self.mode=='live':
        if not self.last_packet or now-self.last_packet>1:
            self.connection.set('等待数据 / 数据中断');self.reason.set('检查 rotating_health.bit、USB 串口与 230400 波特率；请勿使用旧诊断比特流。')
            for v in self.cards.values():v.set('—')
        elif self.sample and not self.sample['flags']&2:
            self.connection.set('FPGA 在线 · 加速度数据无效');self.reason.set('传感器未就绪 / 数据过期：检查 ADXL345 电源、地址与 I²C；编码器计数仍可查看。')
            for v in self.cards.values():v.set('—')
        else:self.connection.set('实时采集中')
    elif self.mode=='demo':self.connection.set('合成演示 · 非实测数据')
    elif self.mode=='replay':self.connection.set('离线回放 · 非当前设备')
    else:self.connection.set('未连接')
    if self.sample:
        s=self.sample;self.diagnostic.set('模式：%s　设备 ID：0x%02X　FPGA 样本序号：%d　I²C 错误：%d\n编码器计数：%+d　有效跳变：%d　异常跳变：%d　A=%d B=%d\n串口缺样：%d　CRC 错误：%d　FPGA 样本丢包：%d　频谱丢帧：%d\n数字滤波：去直流 IIR α=1/64 + FIR [1,2,1]/4；RMS / 峰值为滤波后数值。'%(self.mode,s['device'],s['seq'],s['errors'],s['count'],s['edges'],s['invalid'],s['pins']&1,(s['pins']>>1)&1,self.missing,self.decoder.errors,s['sample_drops'],s['spectrum_drops']))
    capable=self.mode=='live' and self.ser is not None and self.sample is not None and self.sample.get('target_rpm') is not None and now-self.last_packet<1
    for i,b in enumerate(self.control_buttons):b.config(state='normal' if capable or (i==2 and self.mode=='live' and self.ser is not None) else 'disabled')
    if capable:
        self.motor_actual.set('FPGA 目标 %d RPM · %s · %s · %s；实测转速见 RPM 卡片'%(self.sample['target_rpm'],'反向' if self.sample['flags']&32 else '正向','运行命令有效' if self.sample['flags']&16 else '已停止','上位机控制' if self.sample['flags']&1024 else '本地 / 待机'))
        if now-self.last_heartbeat>.4:
            try:self.ser.write(motor_command(6,0,0));self.last_heartbeat=now
            except (serial.SerialException,OSError):pass
        for rid,(sent,op) in list(self.pending.items()):
            if now-sent>1:
                self.pending.pop(rid);self.control_status.set('命令未获确认，请检查连接；界面未自动重试启动');self.note('控制命令确认超时')
        if self.sample['flags']&2048:self.control_status.set('控制心跳曾中断，FPGA 已停机；确认连接后手动重新启动')
    else:
        self.motor_actual.set('电机反馈：没有最新控制状态，不能确认运行情况')
        if self.mode=='live':self.control_status.set('未取得控制能力：检查新版比特流、串口和连接状态')
    if now-self.last_draw>.2:self.draw();self.last_draw=now
    self.root.after(30,self.poll)
 def close(self):
    self.stop_record()
    if self.ser:
        try:self.ser.write(motor_command(1,0,0))
        except (serial.SerialException,OSError):pass
        self.ser.close()
    self.root.destroy()

if __name__=='__main__':
    root=tk.Tk();app=Workstation(root)
    if '--demo' in sys.argv:app.demo()
    root.mainloop()
