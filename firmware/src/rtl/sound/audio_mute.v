module audio_mute(
	input wire clk,
	input wire on,
	output reg mute
);

    reg [24:0] timeout_cnt;

    always @(posedge clk or posedge on) begin
        if (on) begin
            timeout_cnt <= 25'd0;
            mute <= 1'b1;
        end else begin
            if (timeout_cnt == 25'h1FFFFFF) begin
                mute <= 1'b0;
            end else begin
                timeout_cnt <= timeout_cnt + 1'b1;
            end
        end
    end

endmodule
