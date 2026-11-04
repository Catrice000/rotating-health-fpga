`timescale 1ns/1ps
module vibration_filter(input clk,input valid,input [47:0] xyz,output reg out_valid=0,
 output reg signed [15:0] x=0,y=0,z=0);
reg signed [31:0] mx=0,my=0,mz=0;
reg signed [15:0] x1=0,x2=0,y1=0,y2=0,z1=0,z2=0;
wire signed [15:0] ix=xyz[15:0],iy=xyz[31:16],iz=xyz[47:32];
wire signed [31:0] ex=(ix*256)-mx,ey=(iy*256)-my,ez=(iz*256)-mz;
wire signed [15:0] hx=ex>>>8,hy=ey>>>8,hz=ez>>>8;
wire signed [17:0] fx=$signed(hx)+$signed(x1)*2+$signed(x2);
wire signed [17:0] fy=$signed(hy)+$signed(y1)*2+$signed(y2);
wire signed [17:0] fz=$signed(hz)+$signed(z1)*2+$signed(z2);
always @(posedge clk)begin
 out_valid<=valid;
 if(valid)begin
  mx<=mx+(ex>>>6);my<=my+(ey>>>6);mz<=mz+(ez>>>6);
  x<=fx>>>2;y<=fy>>>2;z<=fz>>>2;
  x2<=x1;x1<=hx;y2<=y1;y1<=hy;z2<=z1;z1<=hz;
 end
end
endmodule

// 256-point radix-2 DIT FFT, bit-reversed input, Hann window, 1/256 scaling.
// Two synchronous ports infer true dual-port block RAM.
module fft256(input clk,input valid,input signed [15:0] sample,
 output reg bin_valid=0,output reg [7:0] bin=0,output reg signed [23:0] real_out=0,imag_out=0,
 output reg frame_done=0,output reg [31:0] dropped=0);
reg signed [15:0] sine[0:255],cosine[0:255],window[0:255];
initial begin $readmemh("sin.hex",sine);$readmemh("cos.hex",cosine);$readmemh("hann.hex",window);end
wire [47:0] aq,bq;
reg [3:0] st=0;reg [7:0] load=0,bf=0,outidx=0;reg [2:0] stage=0;
reg signed [23:0] ar=0,ai=0,br=0,bi=0;reg signed [15:0] wr=0,wi=0;
reg signed [40:0] tr=0,ti=0;
wire signed [40:0] mul0=br*wr,mul1=bi*wi,mul2=br*wi,mul3=bi*wr;
wire signed [40:0] rr=tr>>>15,ii=ti>>>15;
wire signed [41:0] sumr=$signed(ar)+rr,sumi=$signed(ai)+ii,difr=$signed(ar)-rr,difi=$signed(ai)-ii;
wire signed [31:0] windowed=sample*window[load];
wire signed [23:0] input_q=windowed>>>9; // retain six fractional bits before rounding
function [7:0] reverse;input [7:0] a;integer i;begin for(i=0;i<8;i=i+1)reverse[i]=a[7-i];end endfunction
wire [7:0] mask=(8'd1<<stage)-1;
wire [7:0] ia=((bf>>stage)<<(stage+1))|(bf&mask);
wire [7:0] ib=ia+(8'd1<<stage);
wire [7:0] tw=(bf&mask)<<(7-stage);
wire [7:0] aa=(st==0)?reverse(load):((st>=6)?outidx:ia);
wire [7:0] ba=ib;
wire awe=(st==0 && valid)||(st==4),bwe=(st==4);
wire [23:0] rplus=sumr>>>1,iplus=sumi>>>1,rminus=difr>>>1,iminus=difi>>>1;
wire [47:0] aw=(st==0)?{input_q,24'd0}:{rplus,iplus};
`ifdef SYNTHESIS
xpm_memory_tdpram #(.MEMORY_SIZE(12288),.MEMORY_PRIMITIVE("block"),.CLOCKING_MODE("common_clock"),
 .WRITE_DATA_WIDTH_A(48),.READ_DATA_WIDTH_A(48),.BYTE_WRITE_WIDTH_A(48),.ADDR_WIDTH_A(8),.READ_LATENCY_A(1),.WRITE_MODE_A("read_first"),
 .WRITE_DATA_WIDTH_B(48),.READ_DATA_WIDTH_B(48),.BYTE_WRITE_WIDTH_B(48),.ADDR_WIDTH_B(8),.READ_LATENCY_B(1),.WRITE_MODE_B("read_first"),.USE_MEM_INIT(0)) storage(
 .clka(clk),.clkb(clk),.rsta(1'b0),.rstb(1'b0),.ena(1'b1),.enb(1'b1),.regcea(1'b1),.regceb(1'b1),.sleep(1'b0),
 .wea(awe),.web(bwe),.addra(aa),.addrb(ba),.dina(aw),.dinb({rminus,iminus}),.douta(aq),.doutb(bq),
 .injectsbiterra(1'b0),.injectdbiterra(1'b0),.injectsbiterrb(1'b0),.injectdbiterrb(1'b0),.sbiterra(),.dbiterra(),.sbiterrb(),.dbiterrb());
`else
reg [47:0] mem[0:255];reg [47:0] qa=0,qb=0;assign aq=qa;assign bq=qb;
always @(posedge clk)begin if(awe)mem[aa]<=aw;qa<=mem[aa];end
always @(posedge clk)begin if(bwe)mem[ba]<={rminus,iminus};qb<=mem[ba];end
`endif
always @(posedge clk)begin
 bin_valid<=0;frame_done<=0;
 if(valid && st!=0)dropped<=dropped+1'b1;
 case(st)
  0:if(valid)begin if(load==255)begin load<=0;stage<=0;bf<=0;st<=1;end else load<=load+1'b1;end
  1:st<=2;
  2:begin ar<=aq[47:24];ai<=aq[23:0];br<=bq[47:24];bi<=bq[23:0];wr<=cosine[tw];wi<=-sine[tw];st<=3;end
  3:begin tr<=mul0-mul1;ti<=mul2+mul3;st<=4;end
  4:st<=5;
  5:if(bf==127)begin bf<=0;if(stage==7)begin outidx<=0;st<=6;end else begin stage<=stage+1'b1;st<=1;end end else begin bf<=bf+1'b1;st<=1;end
  6:st<=7;
  7:begin bin<=outidx;real_out<=aq[47:24];imag_out<=aq[23:0];bin_valid<=1;if(outidx==128)begin frame_done<=1;st<=0;end else begin outidx<=outidx+1'b1;st<=6;end end
 endcase
end
endmodule

// Windowed time-domain metrics and encoder-phase synchronous 1x/2x correlations.
// Baseline learned only on requested, valid, steady rotating windows.
module health_features #(parameter PPR=4096)(input clk,input valid,input signed [15:0] x,y,z,
 input [7:0] phase,input signed [31:0] encoder_count,input learn,input sensor_ok,input encoder_ok,
 output reg report=0,output reg [511:0] features=0,output reg baseline=0,output reg learning=0,
 output reg [7:0] health=0,output reg [7:0] fault=0);
reg signed [15:0] sine[0:255],cosine[0:255];
initial begin $readmemh("sin.hex",sine);$readmemh("cos.hex",cosine);end
wire signed [31:0] xx=x*x,yy=y*y,zz=z*z;
wire [63:0] x4=$unsigned(xx)*$unsigned(xx);
wire [15:0] absx=x[15]?-x:x,absy=y[15]?-y:y,absz=z[15]?-z:z;
reg [7:0] n=0;reg [47:0] sx=0,sy=0,sz=0;reg [63:0] sx4=0;
reg [15:0] px=0,py=0,pz=0,zc=0;reg signprev=0;
reg signed [47:0] c1=0,s1=0,c2=0,s2=0;
wire signed [31:0] v1=x*cosine[phase],v2=x*sine[phase],v3=x*cosine[(phase<<1)&255],v4=x*sine[(phase<<1)&255];
reg signed [31:0] start_count=0,previous_delta=0;
wire signed [31:0] delta=encoder_count-start_count;
wire [31:0] speed=delta[31]?-delta:delta;
wire [31:0] oldspeed=previous_delta[31]?-previous_delta:previous_delta;
wire signed [32:0] speed_diff=$signed({1'b0,speed})-$signed({1'b0,oldspeed});
wire [32:0] abs_diff=speed_diff[32]?-speed_diff:speed_diff;
wire [47:0] ex=sx+$unsigned(xx),ey=sy+$unsigned(yy),ez=sz+$unsigned(zz);
wire [47:0] energy=ex+ey+ez;
reg [3:0] learn_n=0;reg [51:0] base_sum=0;reg [47:0] base_energy=0;
reg [35:0] base_speed_sum=0;reg [31:0] base_speed=0;
wire signed [32:0] base_speed_diff=$signed({1'b0,speed})-$signed({1'b0,base_speed});
wire [32:0] base_speed_error=base_speed_diff[32]?-base_speed_diff:base_speed_diff;
wire [47:0] safe_base=(base_energy<768)?48'd768:base_energy;
wire stable_speed=(oldspeed!=0 && abs_diff*5<oldspeed); // within 20%
reg window_ok=1;
always @(posedge clk)begin
 report<=0;
 if(learn)begin baseline<=0;learning<=1;learn_n<=0;base_sum<=0;base_speed_sum<=0;end
 if(valid)begin
  if(!sensor_ok || !encoder_ok)window_ok<=0;
  sx<=ex;sy<=ey;sz<=ez;sx4<=sx4+x4;
  if(absx>px)px<=absx;if(absy>py)py<=absy;if(absz>pz)pz<=absz;
  c1<=c1+v1;s1<=s1+v2;c2<=c2+v3;s2<=s2+v4;
  if(n!=0 && signprev!=x[15])zc<=zc+1'b1;
  signprev<=x[15];n<=n+1'b1;
  if(n==0)start_count<=encoder_count;
  if(n==255)begin
   // Packed in a documented little-endian record; frequency-independent raw metrics.
   features<={16'd0,16'd0,delta,32'(c2+v3>>>15),32'(s2+v4>>>15),32'(c1+v1>>>15),32'(s1+v2>>>15),
              16'(zc+(signprev!=x[15])),(absz>pz?absz:pz),(absy>py?absy:py),(absx>px?absx:px),
              (sx4+x4),ez,ey,ex};
   report<=1;previous_delta<=delta;
   if(learning && !learn && window_ok && sensor_ok && encoder_ok && speed>=PPR/4 && stable_speed)begin
    base_sum<=base_sum+energy;
    base_speed_sum<=base_speed_sum+speed;
    if(learn_n==7)begin base_energy<=(base_sum+energy)>>3;base_speed<=(base_speed_sum+speed)>>3;baseline<=1;learning<=0;end else learn_n<=learn_n+1'b1;
   end
   if(!window_ok || !sensor_ok || !encoder_ok)begin health<=0;fault<=8;end
   else if(!baseline)begin health<=0;fault<=0;end
   else if(speed<16)begin health<=0;fault<=4;end
   else if(base_speed_error*5>base_speed)begin health<=40;fault<=4;end
   else if(energy>safe_base*4)begin health<=10;fault<=1;end
   else if(energy>safe_base*2)begin health<=40;fault<=1;end
   else if(energy>safe_base+safe_base/2)begin health<=70;fault<=1;end
   else begin health<=100;fault<=0;end
   sx<=0;sy<=0;sz<=0;sx4<=0;px<=0;py<=0;pz<=0;zc<=0;c1<=0;s1<=0;c2<=0;s2<=0;window_ok<=1;
  end
 end
end
endmodule
