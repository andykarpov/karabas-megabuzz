`timescale 1ns / 1ps

module spram #(parameter DATAWIDTH=8, ADDRWIDTH=8, NUMWORDS=1<<ADDRWIDTH, MEM_INIT_FILE="")
(
	input	                 clock,

	input	 [ADDRWIDTH-1:0] address,
	input	 [DATAWIDTH-1:0] data,
	input	                 wren,
	output reg [DATAWIDTH-1:0] q
);

   reg [DATAWIDTH-1:0] mem[0:NUMWORDS];
   initial begin  // usa $readmemb/$readmemh dependiendo del formato del fichero que contenga la ROM
    if (MEM_INIT_FILE != "") begin
      $readmemb(MEM_INIT_FILE, mem);
    end
   end

  always @(posedge clock) 
  begin
    if (wren)
    begin
      mem[address] <= data;
      q <= data;
    end
    else
      q <= mem[address];
  end

endmodule
