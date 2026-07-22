`timescale 1ns / 1ps

module sprom #(parameter DATAWIDTH=8, ADDRWIDTH=8, NUMWORDS=1<<ADDRWIDTH, MEM_INIT_FILE="")
(
	input wire	               clock,
	input wire [ADDRWIDTH-1:0] address,
	output reg [DATAWIDTH-1:0] q
);

   reg [DATAWIDTH-1:0] mem[0:NUMWORDS];
   initial begin  // usa $readmemb/$readmemh dependiendo del formato del fichero que contenga la ROM
    if (MEM_INIT_FILE != "") begin
      $readmemh(MEM_INIT_FILE, mem);
    end
   end

  always @(posedge clock) 
  begin
      q <= mem[address];
  end

endmodule
