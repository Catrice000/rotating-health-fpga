`timescale 1ns/1ps
// Single-master 100 kHz I2C register transactions; open-drain bus.
module i2c_register(input clk,input start,input rd,input [7:0] regaddr,input [7:0] wdata,input [2:0] length,
 inout scl,inout sda,output reg busy=0,output reg done=0,output reg error=0,output reg [47:0] data=0);
reg sl=0,dl=0; assign scl=sl?1'b0:1'bz; assign sda=dl?1'b0:1'bz;
(* ASYNC_REG="TRUE" *) reg [1:0] ss=3,ds=3;
reg [7:0] tx=0,rx=0,addr=0,wd=0; reg readop=0;
reg [2:0] n=1,index=0,bitno=7; reg [1:0] stage=0;
reg [5:0] st=0; reg [8:0] div=0; reg [12:0] timeout=0;
always @(posedge clk) begin
 ss<={ss[0],scl}; ds<={ds[0],sda}; done<=0;
 if(!busy) begin
  sl<=0; dl<=0; div<=0; timeout<=0;
  if(start) begin busy<=1;error<=0;data<=0;addr<=regaddr;wd<=wdata;readop<=rd;n<=length;stage<=0;tx<=8'hA6;st<=0; end
 end else if(div!=124) div<=div+1'b1;
 else begin
  div<=0;
  if((!sl && !ss[1]) || (st==0 && !ds[1])) begin
   if(timeout==4095) begin busy<=0;done<=1;error<=1;sl<=0;dl<=0;st<=0; end else timeout<=timeout+1'b1;
  end else begin
   timeout<=0;
   case(st)
    0:st<=1;
    1:begin dl<=1;st<=2;end
    2:begin sl<=1;bitno<=7;st<=3;end
    3:begin dl<=~tx[bitno];st<=4;end
    4:begin sl<=0;st<=5;end
    5:st<=6;
    6:begin sl<=1;if(bitno==0)st<=7;else begin bitno<=bitno-1'b1;st<=3;end end
    7:begin dl<=0;st<=8;end
    8:begin sl<=0;st<=9;end
    9:begin if(ds[1])error<=1;st<=10;end
    10:begin
     sl<=1;
     if(error)st<=23;
     else if(stage==0)begin stage<=1;tx<=addr;bitno<=7;st<=3;end
     else if(stage==1 && !readop)begin stage<=2;tx<=wd;bitno<=7;st<=3;end
     else if(stage==1)st<=11;
     else if(!readop)st<=23;
     else begin index<=0;bitno<=7;rx<=0;st<=15;end
    end
    11:begin dl<=0;st<=12;end
    12:begin sl<=0;st<=13;end
    13:begin dl<=1;st<=14;end
    14:begin sl<=1;tx<=8'hA7;stage<=2;bitno<=7;st<=3;end
    15:begin dl<=0;st<=16;end
    16:begin sl<=0;st<=17;end
    17:begin rx[bitno]<=ds[1];st<=18;end
    18:begin sl<=1;if(bitno==0)st<=19;else begin bitno<=bitno-1'b1;st<=15;end end
    19:begin data[index*8+:8]<=rx;dl<=(index+1<n);st<=20;end
    20:begin sl<=0;st<=21;end
    21:st<=22;
    22:begin sl<=1;if(index+1==n)begin dl<=1;st<=23;end else begin index<=index+1'b1;bitno<=7;rx<=0;st<=15;end end
    23:begin sl<=1;dl<=1;st<=24;end
    24:begin sl<=0;st<=25;end
    25:begin dl<=0;st<=26;end
    26:begin busy<=0;done<=1;end
    default:begin busy<=0;done<=1;error<=1;end
   endcase
  end
 end
end
endmodule

module adxl_acquire(input clk,inout scl,inout sda,output reg valid=0,output reg [47:0] xyz=0,
 output reg ready=0,output reg [7:0] device_id=0,output reg [31:0] errors=0);
reg start=0,rd=1; reg [7:0] addr=0,wd=0;reg [2:0] len=1,phase=0;
wire busy,done,error;wire [47:0] data;
i2c_register io(clk,start,rd,addr,wd,len,scl,sda,busy,done,error,data);
reg waiting=0;reg [23:0] pause=500000;
always @(posedge clk)begin
 start<=0;valid<=0;
 if(pause!=0)pause<=pause-1'b1;
 else if(!waiting && !busy)begin
  start<=1;waiting<=1;
  case(phase)
   0:begin rd<=1;addr<=0;len<=1;end
   1:begin rd<=0;addr<=8'h2D;wd<=0;end
   2:begin rd<=0;addr<=8'h31;wd<=8'h08;end
   3:begin rd<=0;addr<=8'h2C;wd<=8'h0B;end // 200 Hz sensor ODR
   4:begin rd<=0;addr<=8'h2D;wd<=8'h08;end
   5:begin rd<=1;addr<=8'h30;len<=1;end // DATA_READY
   6:begin rd<=1;addr<=8'h32;len<=6;end
  endcase
 end
 if(done)begin
  waiting<=0;
  if(error || (phase==0 && data[7:0]!=8'hE5))begin ready<=0;phase<=0;errors<=errors+1'b1;pause<=500000;if(phase==0)device_id<=data[7:0];end
  else case(phase)
   0:begin device_id<=data[7:0];phase<=1;end
   1,2,3:phase<=phase+1'b1;
   4:begin phase<=5;ready<=1;pause<=1000000;end
   5:if(data[7])phase<=6;else pause<=50000;
   6:begin xyz<=data;valid<=1;phase<=5;pause<=5000;end
  endcase
 end
end
endmodule

module encoder_input #(parameter PPR=4096)(input clk,input enc_a,input enc_b,output reg signed [31:0] count=0,
 output reg [31:0] edges=0,output reg [15:0] invalid=0,output [7:0] phase,output [1:0] pins);
(* ASYNC_REG="TRUE" *)reg [1:0] a=0,b=0;reg [1:0] prev=0;reg [2:0] settle=0;
reg [12:0] position=0;
assign phase=(position*256)/PPR;assign pins={b[1],a[1]};
always @(posedge clk)begin
 a<={a[0],enc_a};b<={b[0],enc_b};prev<={a[1],b[1]};
 if(settle!=7)settle<=settle+1'b1;
 else case({prev,a[1],b[1]})
  1,7,14,8:begin count<=count+1'b1;edges<=edges+1'b1;position<=(position==PPR-1)?0:position+1'b1;end
  2,11,13,4:begin count<=count-1'b1;edges<=edges+1'b1;position<=(position==0)?PPR-1:position-1'b1;end
  default:if((prev^{a[1],b[1]})==3 && invalid!=65535)invalid<=invalid+1'b1;
 endcase
end
endmodule
