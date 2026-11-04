`timescale 1ns/1ps
module buttons(input clk,input [4:0] raw,output reg [4:0] press=0,output [4:0] level);
(* ASYNC_REG="TRUE" *)reg [4:0] a=0,b=0;reg [4:0] stable=31,armed=0;
assign level=stable;
reg [20:0] timer[0:4];integer i;
initial for(i=0;i<5;i=i+1)timer[i]=0;
always @(posedge clk)begin
 a<=raw;b<=a;press<=0;
 for(i=0;i<5;i=i+1)begin
  if(b[i]==stable[i])timer[i]<=0;
  else if(timer[i]==999999)begin
   stable[i]<=b[i];timer[i]<=0;
   if(b[i] && armed[i])begin press[i]<=1;armed[i]<=0;end
   if(!b[i])armed[i]<=1;
  end else timer[i]<=timer[i]+1'b1;
 end
end
endmodule

module motor_control(input clk,input start_stop,input stop,input change_dir,input change_speed,
 output reg run=0,output reg direction=0,output reg step=0,output enable,output [1:0] speed_mode,
 input cmd_valid,input [7:0] cmd_op,input [15:0] cmd_value,input [15:0] request_id,input inhibit,
 output reg [15:0] target_rpm=60,output reg remote_owned=0,output reg watchdog_trip=0,
 output reg ack_event=0,output reg [63:0] ack_record=0);
reg [17:0] speed_period[0:127];initial $readmemh("speed_period.hex",speed_period);
wire [17:0] target=speed_period[target_rpm[6:0]];
assign speed_mode=(target_rpm==30)?0:((target_rpm==120)?2:1);
reg [31:0] timer=0;reg [17:0] period=50000;reg [22:0] wake=0;reg [26:0] watchdog=0;
reg response_pending=0;reg [7:0] response_op=0,response_status=0;reg [15:0] response_id=0;
assign enable=run;
always @(posedge clk)begin
 ack_event<=response_pending;response_pending<=0;
 if(response_pending)ack_record<={{7'd0,run},{7'd0,direction},target_rpm,response_status,response_op,response_id};
 if(remote_owned && run)begin if(cmd_valid && cmd_op==6)watchdog<=0;else if(watchdog<100000000)watchdog<=watchdog+1'b1;end else watchdog<=0;
 if(cmd_valid && cmd_op!=6)begin
  response_pending<=1;response_op<=cmd_op;response_id<=request_id;response_status<=0;
  case(cmd_op)
   1:begin run<=0;remote_owned<=0;step<=0;timer<=0;wake<=0;end
   2:if(inhibit || stop)response_status<=3;else begin if(!run)begin period<=50000;timer<=0;step<=0;wake<=2500000;end run<=1;remote_owned<=1;watchdog<=0;watchdog_trip<=0;end
   3:if(cmd_value<10 || cmd_value>120)response_status<=1;else target_rpm<=cmd_value;
   4:if(run)response_status<=2;else if(cmd_value>1)response_status<=1;else direction<=cmd_value[0];
   default:response_status<=4;
  endcase
 end
 if(change_dir && !run)direction<=~direction;
 if(change_speed && !run)target_rpm<=(target_rpm==30)?60:((target_rpm==60)?120:30);
 if(start_stop && !run && !inhibit && !stop)begin run<=1;remote_owned<=0;wake<=2500000;period<=50000;timer<=0;step<=0;watchdog_trip<=0;end
 if(run)begin
  if(wake!=0)wake<=wake-1'b1;
  else if(timer>=period-1)begin
   timer<=0;step<=~step;
   if(!step)begin
    if(period>target)period<=(period-target>32)?period-32:target;
    else if(period<target)period<=(target-period>32)?period+32:target;
   end
  end else timer<=timer+1'b1;
 end
 // Highest priority stop, including held physical S4 and remote link watchdog.
 if(stop || inhibit || (start_stop && run) || (cmd_valid && cmd_op==1) || (remote_owned && run && watchdog>=100000000))begin
  if(remote_owned && run && watchdog>=100000000)watchdog_trip<=1;
  run<=0;step<=0;timer<=0;wake<=0;period<=50000;remote_owned<=0;
 end
end
endmodule

module uart_byte #(parameter DIV=217)(input clk,input start,input [7:0] data,output tx,output reg busy=0);
reg [9:0] shift=1023;reg [9:0] timer=0;reg [3:0] bitno=0;
assign tx=shift[0];
always @(posedge clk)begin
 if(!busy)begin if(start)begin busy<=1;shift<={1'b1,data,1'b0};timer<=0;bitno<=0;end end
 else if(timer==DIV-1)begin timer<=0;shift<={1'b1,shift[9:1]};if(bitno==9)begin busy<=0;bitno<=0;end else bitno<=bitno+1'b1;end
 else timer<=timer+1'b1;
end
endmodule

// Packet: C3 3C TYPE LENGTH PAYLOAD CRC16-CCITT(type,length,payload), little endian CRC.
module health_link(input clk,input sample_event,input [351:0] sample_record,
 input feature_event,input [575:0] feature_record,
 input bin_valid,input [7:0] bin,input signed [23:0] re,im,input frame_done,
 output tx,output reg [15:0] sample_drops=0,output reg [15:0] spectrum_drops=0,input ack_event,input [63:0] ack_record);
reg ap=0;reg [63:0] ack_hold=0;
reg sp=0,fp=0,spec=0;reg [351:0] sample_hold=0;reg [575:0] feat_hold=0;
reg [47:0] spectrum[0:128];reg [47:0] sq=0;reg [7:0] spec_idx=0;reg [31:0] frame_id=0,send_frame=0;
reg [3:0] st=0;reg [7:0] typ=0,len=0,index=0,byte_data=0;reg [767:0] body=0;
reg kick=0;wire busy;reg [15:0] crc=65535;
uart_byte uart(clk,kick,byte_data,tx,busy);
function [15:0] crc_byte;input [15:0] c;input [7:0] b;integer j;reg [15:0] t;begin t=c^{b,8'd0};for(j=0;j<8;j=j+1)t=t[15]?((t<<1)^16'h1021):(t<<1);crc_byte=t;end endfunction
wire take_ack=(st==0 && ap),take_sample=(st==0 && !ap && sp),take_feature=(st==0 && !ap && !sp && fp);
always @(posedge clk)begin
 if(ack_event)begin ack_hold<=ack_record;ap<=1;end else if(take_ack)ap<=0;
 sq<=spectrum[spec_idx];
 if(bin_valid)spectrum[bin]<={re,im};
 if(frame_done)begin frame_id<=frame_id+1'b1;if(spec)spectrum_drops<=spectrum_drops+1'b1;else begin spec<=1;spec_idx<=0;send_frame<=frame_id;end end
 if(sample_event)begin sample_hold<=sample_record;if(sp && !take_sample)sample_drops<=sample_drops+1'b1;sp<=1;end else if(take_sample)sp<=0;
 if(feature_event)begin feat_hold<=feature_record;fp<=1;end else if(take_feature)fp<=0;
 kick<=0;
 case(st)
  0:begin
   index<=0;crc<=65535;
   if(ap)begin typ<=8'h11;len<=8;body<=ack_hold;st<=2;end
   else if(sp)begin typ<=1;len<=44;body<=sample_hold;st<=2;end
   else if(fp)begin typ<=3;len<=72;body<=feat_hold;st<=2;end
   else if(spec)st<=1;
  end
  1:begin typ<=2;len<=14;body<={32'd0};body[31:0]<=send_frame;body[47:32]<={8'd0,spec_idx};body[79:48]<={{8{sq[47]}},sq[47:24]};body[111:80]<={{8{sq[23]}},sq[23:0]};st<=2;end
  2:if(!busy)begin
   kick<=1;
   if(index==0)byte_data<=8'hC3;
   else if(index==1)byte_data<=8'h3C;
   else if(index==2)begin byte_data<=typ;crc<=crc_byte(crc,typ);end
   else if(index==3)begin byte_data<=len;crc<=crc_byte(crc,len);end
   else if(index<len+4)begin byte_data<=body[(index-4)*8+:8];crc<=crc_byte(crc,body[(index-4)*8+:8]);end
   else if(index==len+4)byte_data<=crc[7:0];else byte_data<=crc[15:8];
   st<=3;
  end
  3:if(busy)st<=4;
  4:if(!busy)begin
   if(index==len+5)begin
    st<=0;
    if(typ==2)begin if(spec_idx==128)begin spec<=0;spec_idx<=0;end else spec_idx<=spec_idx+1'b1;end
   end else begin index<=index+1'b1;st<=2;end
  end
 endcase
end
endmodule
