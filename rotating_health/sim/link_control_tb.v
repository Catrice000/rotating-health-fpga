`timescale 1ns/1ps
module link_control_tb;
reg clk=0;always #10 clk=~clk;
reg se=0,fe=0,ae=0;reg [351:0] sr=0;reg [575:0] fr=0;reg [63:0] ar=64'h0000005a00030001;
wire tx;wire [15:0] drops,sdrops;
health_link dut(clk,se,sr,fe,fr,1'b0,8'd0,24'sd0,24'sd0,1'b0,tx,drops,sdrops,ae,ar);
integer fd;reg [7:0] b;
initial begin
 for(integer i=0;i<44;i=i+1)sr[i*8+:8]=i;
 for(integer i=0;i<72;i=i+1)fr[i*8+:8]=i+44;
 #100;@(negedge clk);se=1;fe=1;ae=1;@(negedge clk);se=0;fe=0;ae=0;
end
initial begin
 fd=$fopen("control_uart.hex","w");
 for(integer i=0;i<142;i=i+1)begin
  @(negedge tx);#6510;for(integer k=0;k<8;k=k+1)begin b[k]=tx;#4340;end
  if(!tx)$fatal(1,"UART stop bit");$fwrite(fd,"%02x\n",b);
 end
 $fclose(fd);$display("CONTROL_LINK_RTL_PASS");$finish;
end
initial begin #10000000;$fatal(1,"link timeout");end
endmodule
