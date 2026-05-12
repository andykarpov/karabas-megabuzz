module clk_div_8mhz (
    input  wire clk,    // 28 MHz
    input  wire rst_n,  // active low reset
    output reg  cen     // 8 MHz enable
);

    reg [2:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 3'd0;
            cen <= 1'b0;
        end else begin
            if (counter == 3'd2) begin
                counter <= 3'd0;
                cen <= 1'b1;
            end else if (counter == 3'd0 && cen) begin 
					// correction
            end
            else begin
                counter <= counter + 1'b1;
                cen <= 1'b0;
            end
        end
    end
endmodule
