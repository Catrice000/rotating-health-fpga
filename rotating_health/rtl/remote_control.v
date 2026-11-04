`timescale 1ns/1ps
module uart_receive(input clk,input rx,output reg valid=0,output reg [7:0] data=0);
(* ASYNC_REG="TRUE" *)reg [1:0] sync=3;
reg [1:0] st=0;reg [8:0] timer=0;reg [2:0] bitno=0;reg [7:0] bits=0;
always @(posedge clk)begin
 sync<={sync[0],rx};valid<=0;
 case(st)
  0:if(!sync[1])begin timer<=108;st<=1;end
  1:if(timer!=0)timer<=timer-1'b1;else if(!sync[1])begin timer<=216;bitno<=0;st<=2;end else st<=0;
  2:if(timer!=0)timer<=timer-1'b1;else begin bits[bitno]<=sync[1];timer<=216;if(bitno==7)st<=3;else bitno<=bitno+1'b1;end
  3:if(timer!=0)timer<=timer-1'b1;else begin if(sync[1])begin data<=bits;valid<=1;end st<=0;end
 endcase
end
endmodule

// C3 3C 10 05 OP VALUE_LO VALUE_HI ID_LO ID_HI CRC_LO CRC_HI.
module command_receive(input clk,input rx,output reg valid=0,output reg [7:0] op=0,
 output reg [15:0] value=0,request_id=0);
wire bv;wire [7:0] b;uart_receive receiver(clk,rx,bv,b);
reg [3:0] st=0;reg [15:0] crc=65535;reg [7:0] crc_low=0;
reg [7:0] opcode=0;reg [15:0] argument=0,id=0;reg [19:0] timeout=0;
function [15:0] crc_byte;input [15:0] c;input [7:0] x;integer j;reg [15:0] t;begin t=c^{x,8'd0};for(j=0;j<8;j=j+1)t=t[15]?((t<<1)^16'h1021):(t<<1);crc_byte=t;end endfunction
always @(posedge clk)begin
 valid<=0;
 if(bv)begin
  timeout<=0;
  case(st)
   0:if(b==8'hC3)st<=1;
   1:if(b==8'h3C)begin st<=2;crc<=65535;end else st<=(b==8'hC3)?1:0;
   2:if(b==8'h10)begin crc<=crc_byte(crc,b);st<=3;end else st<=0;
   3:if(b==5)begin crc<=crc_byte(crc,b);st<=4;end else st<=0;
   4:begin opcode<=b;crc<=crc_byte(crc,b);st<=5;end
   5:begin argument[7:0]<=b;crc<=crc_byte(crc,b);st<=6;end
   6:begin argument[15:8]<=b;crc<=crc_byte(crc,b);st<=7;end
   7:begin id[7:0]<=b;crc<=crc_byte(crc,b);st<=8;end
   8:begin id[15:8]<=b;crc<=crc_byte(crc,b);st<=9;end
   9:begin crc_low<=b;st<=10;end
   10:begin if({b,crc_low}==crc)begin valid<=1;op<=opcode;value<=argument;request_id<=id;end st<=0;end
  endcase
 end else if(st!=0)begin if(timeout==499999)begin timeout<=0;st<=0;end else timeout<=timeout+1'b1;end
end
endmodule
