module clk_div_8mhz (
    input  wire clk,    // 28 MHz
    input  wire rst_n,  // active low reset
    output reg  cen     // 8 MHz enable
);

    reg [1:0] counter;
	 reg cyc34 = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            cen <= 0;
				cyc34 <= 0;
        end else begin
				cen <= 0;
				case ({cyc34, counter})
					3'b011: begin cen <= 1; counter <= 0; cyc34 <= ~cyc34; end // 4
					3'b110: begin cen <= 1; counter <= 0; cyc34 <= ~cyc34; end // 3
					default: counter <= counter + 1;
				endcase
        end
    end
endmodule
