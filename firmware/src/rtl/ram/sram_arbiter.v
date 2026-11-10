`default_nettype none
/*
  Shares the SRAM of General Sound with the RAM of DivMMC.

  GS keeps the direct path to the pads it always had: its CPU reads memory in one CE period (71 ns), which
  leaves no room for anything in between. An access of the host takes the pads over instead. GS is frozen
  through its CE first, and is given the time of a whole SRAM access again before it runs on, so a read or
  a write of GS that got interrupted simply happens once more.

  Host side: host_req is asynchronous and stays up until the host ends its cycle. Without contention the
  data is ready about 160 ns after host_req, host_wait covers the faster hosts.
*/

module sram_arbiter (
    input wire         clk_mem,         // 140 MHz
    input wire         clk_bus,         // 28 MHz, same PLL
    input wire         reset,
    input wire         enable,          // off during the load of the GS ROM

    input wire         host_req,
    input wire         host_we,
    input wire [20:0]  host_a,
    input wire [7:0]   host_di,
    output reg [7:0]   host_do = 8'hFF,
    output wire        host_wait,

    output wire        gs_hold,         // clk_bus: GS must not take a CE
    input wire [20:0]  gs_a,
    input wire [7:0]   gs_do,
    input wire         gs_oe,
    input wire         gs_wr_n,
    input wire         gs_rd_n,
    output wire [7:0]  gs_di,

    output wire [20:0] sram_a,
    inout wire  [7:0]  sram_d,
    output wire        sram_wr_n,
    output wire        sram_rd_n
);

    // clocks of clk_mem from the address on the pads to the data being taken: 71 ns for a 45 ns SRAM
    localparam ACCESS_LAST = 4'd9;
    // clocks after the pads are back with GS: a complete SRAM access before its next CE
    localparam RECOVER_LAST = 4'd10;

    localparam IDLE = 3'd0, ACQUIRE = 3'd1, SWITCH = 3'd2, ACCESS = 3'd3, RECOVER = 3'd4, DROP = 3'd5;

    reg [2:0] state = IDLE;
    reg [3:0] cnt = 0;
    reg [1:0] req_sr = 0;
    wire req = req_sr[1];

    reg hold_req = 0, hold_bus = 0, hold_seen = 0, done = 0;
    reg mux_on = 0, block = 0, h_we = 0, h_drive = 0, h_rd_n = 1, h_wr_n = 1;
    reg [20:0] h_a = 0;
    reg [7:0] h_data = 0;

    // A CE of GS on this very edge has still seen its own data: the pads change only after hold_seen
    always @(posedge clk_bus) hold_bus <= hold_req;
    assign gs_hold = hold_bus;

    always @(posedge clk_mem) begin
        req_sr <= {req_sr[0], host_req & enable};
        hold_seen <= hold_bus;

        if (reset) begin
            state <= IDLE;
            hold_req <= 0;
            done <= 0;
            mux_on <= 0;
            block <= 0;
            h_drive <= 0;
            h_rd_n <= 1;
            h_wr_n <= 1;
        end else begin
            case (state)
                IDLE: if (req & ~done) begin
                    hold_req <= 1;
                    state <= ACQUIRE;
                end

                // an interrupted write of GS must end at its own address: first the strobes go away,
                // only then the address changes (and back, in the opposite order)
                ACQUIRE: if (hold_seen) begin
                    block <= 1;
                    state <= SWITCH;
                end

                SWITCH: begin
                    mux_on <= 1;
                    h_a <= host_a;
                    h_we <= host_we;
                    h_data <= host_di;
                    cnt <= 0;
                    state <= ACCESS;
                end

                ACCESS: begin
                    cnt <= cnt + 1'b1;
                    if (cnt == 0) begin
                        if (h_we) begin
                            h_drive <= 1;
                            h_wr_n <= 0;
                        end else
                            h_rd_n <= 0;
                    end
                    if (h_we) begin
                        if (cnt == ACCESS_LAST - 1) h_wr_n <= 1; // the data stays one clock longer
                        if (cnt == ACCESS_LAST) h_drive <= 0;
                    end else if (cnt == ACCESS_LAST) begin
                        host_do <= sram_d;
                        h_rd_n <= 1;
                    end
                    if (cnt == ACCESS_LAST + 1) begin
                        mux_on <= 0;
                        done <= 1;
                        cnt <= 0;
                        state <= RECOVER;
                    end
                end

                RECOVER: begin
                    block <= 0;
                    cnt <= cnt + 1'b1;
                    if (cnt == RECOVER_LAST) begin
                        hold_req <= 0;
                        state <= DROP;
                    end
                end

                // GS has to see the end of the hold before the next one starts
                DROP: if (!hold_seen) state <= IDLE;

                default: state <= IDLE;
            endcase
            // the host has ended its cycle, whatever is going on: the next one is a new request
            if (!req) done <= 0;
        end
    end

    assign host_wait = host_req & enable & ~done;

    assign sram_a    = mux_on ? h_a    : gs_a;
    assign sram_wr_n = mux_on ? h_wr_n : (gs_wr_n | block);
    assign sram_rd_n = mux_on ? h_rd_n : (gs_rd_n | block);
    assign sram_d    = mux_on ? (h_drive ? h_data : 8'bz) : ((gs_oe & ~block) ? gs_do : 8'bz);
    assign gs_di     = sram_d;

endmodule
