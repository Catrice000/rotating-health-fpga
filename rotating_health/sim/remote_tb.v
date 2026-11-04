`timescale 1ns/1ps
module remote_tb;
reg clk=0,rx=1,stop=0;always #10 clk=~clk;
wire cv;wire [7:0] op;wire [15:0] val,id;
command_receive parser(clk,rx,cv,op,val,id);
wire run,dir,step,en,owner,trip,ack;wire [1:0] mode;wire [15:0] rpm;wire [63:0] record;
motor_control motor(clk,1'b0,stop,1'b0,1'b0,run,dir,step,en,mode,cv,op,val,id,1'b0,rpm,owner,trip,ack,record);
reg [7:0] data[0:87];integer ack_count=0;
task send_byte(input [7:0] b);begin
 rx=0;#4340;for(integer k=0;k<8;k=k+1)begin rx=b[k];#4340;end rx=1;#4340;
end endtask
task send_cmd(input integer n);begin for(integer j=0;j<11;j=j+1)send_byte(data[n*11+j]);#1000;end endtask
always @(posedge clk)if(ack)begin
 ack_count=ack_count+1;
 case(record[15:0])
  1:if(record[31:24]!=0 || rpm!=90)$fatal(1,"speed command");
  2:if(record[31:24]!=0 || !run || !owner)$fatal(1,"start command");
  8:if(record[31:24]!=0 || rpm!=45 || !run)$fatal(1,"running speed change");
  3:if(record[31:24]!=2 || dir!=0)$fatal(1,"running reversal not rejected");
  4:if(run || en || step)$fatal(1,"stop command");
  5:if(record[31:24]!=0 || dir!=1)$fatal(1,"direction command");
  6:if(record[31:24]!=1 || rpm!=45)$fatal(1,"out-of-range speed");
  7:if(record[31:24]!=3 || run)$fatal(1,"held S4 interlock");
 endcase
end
initial begin
 $readmemh("commands.hex",data);#200;
 send_cmd(0);send_cmd(1);send_cmd(2);
 motor.wake=0;motor.period=5000;motor.timer=5000;
 repeat(3)@(negedge clk);
 if(motor.period!=5032)$fatal(1,"speed ramp did not advance gradually");
 for(integer i=3;i<7;i=i+1)send_cmd(i);
 stop=1;send_cmd(7);stop=0;
 // Re-send start, then simulate expiry of its remote ownership watchdog.
 send_cmd(1);if(!run)$fatal(1,"restart");
 motor.watchdog=100000000;repeat(3)@(negedge clk);
 if(run || !trip)$fatal(1,"watchdog stop");
 // A corrupted CRC must not start the motor.
 data[21]=data[21]^1;send_cmd(1);if(run)$fatal(1,"bad CRC executed");
 if(ack_count!=9)$fatal(1,"unexpected command acknowledgement count");
 $display("REMOTE_CONTROL_RTL_PASS");$finish;
end
initial begin #20000000;$fatal(1,"remote timeout");end
endmodule
