`timescale 1ns/1ps
module i2c_tb;
reg clk=0,start=0,rd=1;reg [7:0] addr=0,wd=0;reg [2:0] len=1;always #10 clk=~clk;
tri1 scl,sda;reg dl=0;assign sda=dl?1'b0:1'bz;
wire busy,done,error;wire [47:0] data;
i2c_register dut(clk,start,rd,addr,wd,len,scl,sda,busy,done,error,data);
reg [7:0] got;integer i;
task wait_start;begin @(negedge sda);while(!scl)@(negedge sda);end endtask
task receive_byte(output [7:0] value);integer j;begin
 for(j=7;j>=0;j=j-1)begin @(posedge scl);value[j]=sda;end
 @(negedge scl);dl=1;@(posedge scl);@(negedge scl);dl=0;
end endtask
task send_byte(input [7:0] value);integer j;begin
 for(j=7;j>=0;j=j-1)begin dl=~value[j];@(posedge scl);@(negedge scl);end
 dl=0;@(posedge scl);@(negedge scl);
end endtask
task request(input reg r,input [7:0] a,input [7:0] w);begin
 @(negedge clk);rd=r;addr=a;wd=w;start=1;@(negedge clk);start=0;wait(done);#50;
end endtask
initial begin
 #100;
 fork
  begin request(1,0,0);if(error || data[7:0]!=8'hE5)$fatal(1,"device ID read");end
  begin wait_start();receive_byte(got);if(got!=8'hA6)$fatal(1,"write addr");receive_byte(got);if(got!=0)$fatal(1,"reg addr");wait_start();receive_byte(got);if(got!=8'hA7)$fatal(1,"read addr");send_byte(8'hE5);end
 join
 fork
  begin request(0,8'h2C,8'h0B);if(error)$fatal(1,"write error");end
  begin wait_start();receive_byte(got);receive_byte(got);if(got!=8'h2C)$fatal(1,"config reg");receive_byte(got);if(got!=8'h0B)$fatal(1,"config value");end
 join
 request(1,0,0);if(!error)$fatal(1,"missing ACK not detected");
 $display("I2C_RTL_PASS");$finish;
end
initial begin #10000000;$fatal(1,"I2C timeout");end
endmodule
