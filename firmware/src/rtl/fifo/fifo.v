module fifo #(
  parameter DATA_WIDTH = 8,
  parameter ADDR_WIDTH = 8,
  parameter DEPTH = (2**ADDR_WIDTH)
)
(
  input wire clk,
  input wire reset,
  input wire rd,
  input wire wr,
  input wire [DATA_WIDTH-1:0] din,
  output reg [DATA_WIDTH-1:0] dout,
  output wire full,
  output wire empty,
  output wire [ADDR_WIDTH-1:0] data_count
);
  
reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
reg [ADDR_WIDTH-1:0] readPtr, writePtr;
reg [ADDR_WIDTH:0] counter;
wire  [ADDR_WIDTH-1:0] writeAddr = writePtr[ADDR_WIDTH-1:0];
wire  [ADDR_WIDTH-1:0] readAddr = readPtr[ADDR_WIDTH-1:0]; 

always @(posedge clk or posedge reset) begin
 if(reset)begin
	readPtr     <= 0;
	writePtr    <= 0;
	counter     <= 0;
 end
 else begin

    case ({wr && !full, rd && !empty})
		2'b10: begin // w
			memory[writeAddr] <= din;
			writePtr         <= (writePtr + 1) % DEPTH;
			counter          <= counter + 1;
		end
		2'b01: begin // r
			dout             <= memory[readAddr];
			readPtr          <= (readPtr + 1) % DEPTH;
			counter          <= counter - 1;
		end
		2'b11: begin // rw
			memory[writeAddr] <= din;
			writePtr         <= (writePtr + 1) % DEPTH;
			dout             <= memory[readAddr];
			readPtr          <= (readPtr + 1) % DEPTH;
		end
		default: ;
	endcase
 end
end
  
assign empty = (writePtr == readPtr) ? 1'b1: 1'b0;
assign full  = ((writePtr + 1) % DEPTH == readPtr) ? 1'b1 : 1'b0;
assign data_count = counter >= DEPTH ? DEPTH-1 : counter[ADDR_WIDTH-1:0];

endmodule
