`timescale 1ns/1ps
module link_tb;
reg clk=0;always #10 clk=~clk;
reg sample_event=0,feature_event=0;reg [335:0] sr=0;reg [575:0] fr=0;
wire tx;wire [15:0] drops,sdrops;
health_link dut(clk,sample_event,sr,feature_event,fr,1'b0,8'd0,24'sd0,24'sd0,1'b0,tx,drops,sdrops);
integer i,fd;reg [7:0] b;
initial begin
 for(i=0;i<42;i=i+1)sr[i*8+:8]=i;
 for(i=0;i<72;i=i+1)fr[i*8+:8]=i+42;
 #100;@(negedge clk);sample_event=1;feature_event=1;@(negedge clk);sample_event=0;feature_event=0;
end
initial begin
 fd=$fopen("uart_bytes.hex","w");
 for(i=0;i<126;i=i+1)begin
  @(negedge tx);#6510;
  for(integer k=0;k<8;k=k+1)begin b[k]=tx;#4340;end
  if(!tx)$fatal(1,"UART stop bit");$fwrite(fd,"%02x\n",b);
 end
 $fclose(fd);$display("LINK_RTL_PASS");$finish;
end
initial begin #10000000;$fatal(1,"link timeout");end
endmodule
