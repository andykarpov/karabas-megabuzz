// Minimal Xilinx UNISIM stub for Sigasi linting.
// These declarations are intentionally simple and are not meant to replace
// the real Xilinx primitives during FPGA synthesis.

module ODDR2 #(
    parameter DDR_ALIGNMENT = "C0",
    parameter INIT = 1'b0,
    parameter SRTYPE = "SYNC"
) (
    output Q,
    input  C0,
    input  C1,
    input  CE,
    input  D0,
    input  D1,
    input  R,
    input  S
);
    assign Q = 1'b0;
endmodule

module PLL_BASE #(
    parameter BANDWIDTH = "OPTIMIZED",
    parameter CLK_FEEDBACK = "CLKFBOUT",
    parameter COMPENSATION = "SYSTEM_SYNCHRONOUS",
    parameter DIVCLK_DIVIDE = 1,
    parameter CLKFBOUT_MULT = 1,
    parameter CLKFBOUT_PHASE = 0.0,
    parameter CLKOUT0_DIVIDE = 1,
    parameter CLKOUT0_PHASE = 0.0,
    parameter CLKOUT0_DUTY_CYCLE = 0.5,
    parameter CLKOUT1_DIVIDE = 1,
    parameter CLKOUT1_PHASE = 0.0,
    parameter CLKOUT1_DUTY_CYCLE = 0.5,
    parameter CLKOUT2_DIVIDE = 1,
    parameter CLKOUT2_PHASE = 0.0,
    parameter CLKOUT2_DUTY_CYCLE = 0.5,
    parameter CLKOUT3_DIVIDE = 1,
    parameter CLKOUT3_PHASE = 0.0,
    parameter CLKOUT3_DUTY_CYCLE = 0.5,
    parameter CLKOUT4_DIVIDE = 1,
    parameter CLKOUT4_PHASE = 0.0,
    parameter CLKOUT4_DUTY_CYCLE = 0.5,
    parameter CLKOUT5_DIVIDE = 1,
    parameter CLKOUT5_PHASE = 0.0,
    parameter CLKOUT5_DUTY_CYCLE = 0.5,
    parameter CLKIN_PERIOD = 10.0,
    parameter REF_JITTER = 0.01
) (
    output CLKFBOUT,
    output CLKOUT0,
    output CLKOUT1,
    output CLKOUT2,
    output CLKOUT3,
    output CLKOUT4,
    output CLKOUT5,
    output LOCKED,
    input  CLKIN,
    input  CLKFBIN,
    input  RST
);
    assign CLKFBOUT = 1'b0;
    assign CLKOUT0 = 1'b0;
    assign CLKOUT1 = 1'b0;
    assign CLKOUT2 = 1'b0;
    assign CLKOUT3 = 1'b0;
    assign CLKOUT4 = 1'b0;
    assign CLKOUT5 = 1'b0;
    assign LOCKED = 1'b1;
endmodule

module OBUF (
    output O,
    input  I
);
    assign O = I;
endmodule

module IBUF (
    output O,
    input  I
);
    assign O = I;
endmodule

module BUFG (
    output O,
    input  I
);
    assign O = I;
endmodule

module IBUFG (
    output O,
    input  I
);
    assign O = I;
endmodule

module IOBUF (
    inout  IO,
    input  I,
    input  T,
    output O
);
    assign IO = T ? 1'bz : I;
    assign O = IO;
endmodule
