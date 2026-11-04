`timescale 1ns/1ps
module features_tb;
reg clk=0,valid=0,learn=0;reg signed [15:0] x=0,y=0,z=0;reg [7:0] phase=0;reg signed [31:0] count=0;always #10 clk=~clk;
wire report,baseline,learning;wire [511:0] features;wire [7:0] health,fault;
health_features dut(clk,valid,x,y,z,phase,count,learn,1'b1,1'b1,report,features,baseline,learning,health,fault);
integer i;
task sample(input integer val);begin @(negedge clk);valid=1;x=val;count=count+5;phase=phase+1;@(negedge clk);valid=0;end endtask
initial begin
 #100;@(negedge clk);learn=1;@(negedge clk);learn=0;
 for(i=0;i<256*10;i=i+1)sample(10);
 repeat(5)@(negedge clk);
 if(!baseline || learning)$fatal(1,"baseline did not complete");
 if(health!=100 || fault!=0)$fatal(1,"normal status");
 if(features[47:0]!=25600 || features[223:208]!=10)$fatal(1,"energy/peak packing");
 for(i=0;i<256;i=i+1)sample(30);
 repeat(5)@(negedge clk);
 if(health!=10 || fault!=1)$fatal(1,"vibration anomaly not detected");
 $display("FEATURES_RTL_PASS");$finish;
end
endmodule
