`timescale 1ns / 1ps

module dprom #(parameter DATAWIDTH=8, ADDRWIDTH=8, NUMWORDS=1<<ADDRWIDTH, MEM_INIT_FILE="")
(
	input	                 clock,
	input	 [ADDRWIDTH-1:0] address_a,
	input	 [DATAWIDTH-1:0] data_a,
	output reg [DATAWIDTH-1:0] q_a
);

   reg [DATAWIDTH-1:0] mem[0:NUMWORDS];
   initial begin  // usa $readmemb/$readmemh dependiendo del formato del fichero que contenga la ROM
    if (MEM_INIT_FILE != "") begin
      $readmemh(MEM_INIT_FILE, mem);
    end
   end

  always @(posedge clock) 
  begin
      q_a <= mem[address_a];
  end

endmodule
