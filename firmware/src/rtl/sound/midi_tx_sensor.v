module midi_tx_sensor (
    input  wire clk,
    input  wire reset,
    input  wire midi_in, 
    output reg  midi_active
);

    reg [2:0] midi_sync_reg;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            midi_sync_reg <= 3'b111;
        end else begin
            midi_sync_reg <= {midi_sync_reg[1:0], midi_in};
        end
    end

    wire edge_detected = (midi_sync_reg[2] != midi_sync_reg[1]);
    reg [24:0] timeout_cnt;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            timeout_cnt <= 25'd0;
            midi_active <= 1'b0;
        end else begin
            if (edge_detected) begin
                timeout_cnt <= 25'd0;
                midi_active <= 1'b1;
            end else if (timeout_cnt == 25'h1FFFFFF) begin
                midi_active <= 1'b0;
            end else begin
                timeout_cnt <= timeout_cnt + 1'b1;
            end
        end
    end

endmodule
