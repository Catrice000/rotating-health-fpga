`timescale 1ns/1ps
module motor_tb;
reg clk=0,start=0,stop=0,dir_change=0,speed_change=0;always #10 clk=~clk;
wire run,dir,step,en;wire [1:0] speed;
motor_control dut(clk,start,stop,dir_change,speed_change,run,dir,step,en,speed);
initial begin
 #100;if(run || en || step)$fatal(1,"uncommanded motor start");
 @(negedge clk);start=1;@(negedge clk);start=0;
 if(!run || !en)$fatal(1,"start enable");
 @(negedge clk);dir_change=1;speed_change=1;@(negedge clk);dir_change=0;speed_change=0;
 if(dir!=0 || speed!=1)$fatal(1,"configuration changed while running");
 @(negedge clk);stop=1;@(negedge clk);stop=0;
 if(run || en || step)$fatal(1,"stop priority");
 $display("MOTOR_RTL_PASS");$finish;
end
endmodule
