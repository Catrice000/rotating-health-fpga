`timescale 1ns/1ps
module fft_tb;
reg clk=0,valid=0;reg signed [15:0] sample=0;always #10 clk=~clk;
wire bv,done;wire [7:0] bin;wire signed [23:0] re,im;wire [31:0] dropped;
fft256 dut(clk,valid,sample,bv,bin,re,im,done,dropped);
reg [15:0] input_mem[0:767];integer f,i,fd,received=0;
initial begin
 $readmemh("fft_input.hex",input_mem);fd=$fopen("fft_output.csv","w");
 #100;
 for(f=0;f<3;f=f+1)begin
  for(i=0;i<256;i=i+1)begin @(negedge clk);sample=input_mem[f*256+i];valid=1;@(negedge clk);valid=0;repeat(4)@(negedge clk);end
  wait(done);repeat(10)@(negedge clk);
 end
 if(received!=387 || dropped!=0)$fatal(1,"FFT output count or input drop");
 $fclose(fd);$display("FFT_RTL_PASS");$finish;
end
always @(posedge clk)if(bv)begin $fwrite(fd,"%0d,%0d,%0d,%0d\n",f,bin,re,im);received=received+1;end
initial begin #10000000;$fatal(1,"FFT timeout");end
endmodule
