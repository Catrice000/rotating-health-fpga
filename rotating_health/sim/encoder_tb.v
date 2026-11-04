`timescale 1ns/1ps
module encoder_tb;
reg clk=0,a=0,b=0;always #10 clk=~clk;
wire signed [31:0] count;wire [31:0] edges;wire [15:0] invalid;wire [7:0] phase;wire [1:0] pins;
encoder_input dut(clk,a,b,count,edges,invalid,phase,pins);
task ab(input aa,input bb);begin a=aa;b=bb;#100;end endtask
initial begin
 #200;
 if(count!=0)$fatal(1,"startup count");
 for(integer i=0;i<1024;i=i+1)begin ab(0,1);ab(1,1);ab(1,0);ab(0,0);end
 if(count!=4096 || edges!=4096 || phase!=0)$fatal(1,"one revolution");
 ab(1,0);ab(1,1);ab(0,1);ab(0,0);
 if(count!=4092 || phase!=255)$fatal(1,"reverse");
 ab(1,1);if(invalid!=1)$fatal(1,"invalid transition");
 $display("ENCODER_RTL_PASS");$finish;
end
endmodule
