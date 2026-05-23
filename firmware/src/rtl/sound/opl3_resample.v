module opl3_resample (
    input wire clk,           // 28 MHz
    input wire reset,
    input wire [15:0] data_in,// Input audio-data (48.611 kHz)
    input wire valid_in,      // Valid input (1 clock)
    output reg [15:0] data_out,// Output audio-data (54.687 kHz)
    output reg valid_out      // Valid output (1 clock)
);

    // NCO step constant for samplerate 54.687 kHz @ 28 MHz
    localparam [31:0] NCO_INC = 32'd8389360;

    reg [15:0] sample_curr;
    reg [15:0] sample_next;
    
    reg [31:0] phase_acc;
    
    // Input latch
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sample_curr <= 16'd0;
            sample_next <= 16'd0;
        end else if (valid_in) begin
            sample_curr <= sample_next;
            sample_next <= data_in;
        end
    end

    // NCO and out strobe
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            phase_acc <= 32'd0;
            valid_out <= 1'b0;
        end else begin
            phase_acc <= phase_acc + NCO_INC;
            
            if (phase_acc >= (32'hFFFFFFFF - NCO_INC)) begin
                valid_out <= 1'b1;
            end else begin
                valid_out <= 1'b0;
            end
        end
    end

    // Linear interpolation
    // Out = Curr + (Next - Curr) * (Fraction / Max_Fraction)
    wire [15:0] frac = phase_acc[31:16];
    wire signed [16:0] diff = $signed({1'b0, sample_next}) - $signed({1'b0, sample_curr});
    wire signed [32:0] product = diff * $signed({1'b0, frac});

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            data_out <= 16'd0;
        end else if (valid_out) begin
            data_out <= sample_curr + product[31:16];
        end
    end

endmodule
