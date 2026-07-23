//------------------------------------------------------------------------------
//
//   FileName:         spi_master.v
//   Dependencies:     none
//   Design Software:  Quartus II Version 9.0 Build 132 SJ Full Version
//
//   HDL CODE IS PROVIDED "AS IS."  DIGI-KEY EXPRESSLY DISCLAIMS ANY
//   WARRANTY OF ANY KIND, WHETHER EXPRESS OR IMPLIED, INCLUDING BUT NOT
//   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
//   PARTICULAR PURPOSE, OR NON-INFRINGEMENT. IN NO EVENT SHALL DIGI-KEY
//   BE LIABLE FOR ANY INCIDENTAL, SPECIAL, INDIRECT OR CONSEQUENTIAL
//   DAMAGES, LOST PROFITS OR LOST DATA, HARM TO YOUR EQUIPMENT, COST OF
//   PROCUREMENT OF SUBSTITUTE GOODS, TECHNOLOGY OR SERVICES, ANY CLAIMS
//   BY THIRD PARTIES (INCLUDING BUT NOT LIMITED TO ANY DEFENSE THEREOF),
//   ANY CLAIMS FOR INDEMNITY OR CONTRIBUTION, OR OTHER SIMILAR COSTS.
//
//   Version History
//   Version 1.0 7/23/2010 Scott Larson
//     Initial Public Release
//   Version 1.1 4/11/2013 Scott Larson
//     Corrected ModelSim simulation error (explicitly reset clk_toggles signal)
//    
//------------------------------------------------------------------------------

module spi_master(
    input wire                  clock,      //system clock
    input wire                  reset_n,    //asynchronous reset
    input wire                  enable,     //initiate transaction
    input wire                  cpol,       //spi clock polarity
    input wire                  cpha,       //spi clock phase
    input wire                  cont,       //continuous mode command
    input wire [31:0]           clk_div,    //system clock cycles per 1/2 period of sclk
    input wire [31:0]           addr,       //address of slave
    input wire [d_width - 1:0]  tx_data,    //data to transmit
    input wire                  miso,       //master in, slave out
    output reg                  sclk,       //spi clock
    output reg [slaves - 1:0]   ss_n,       //slave select
    output reg                  mosi,       //master out, slave in
    output reg                  busy,       //busy / data ready signal
    output reg [d_width - 1:0]  rx_data     //data received
);

parameter [31:0] slaves=4;
parameter [31:0] d_width=2; //data bus width
localparam [0:0] //state machine
  ready = 0,
  execute = 1;

reg state;  //current state
reg [31:0] slave;  //slave selected for current transaction
reg [31:0] clk_ratio;  //current clk_div
reg [31:0] count;  //counter to trigger sclk from system clock
reg [31:0] clk_toggles;  //count spi clock toggles
reg assert_data;  //'1' is tx sclk toggle, '0' is rx sclk toggle
reg continue;  //flag to continue transaction
reg [d_width - 1:0] rx_buffer;  //receive data buffer
reg [d_width - 1:0] tx_buffer;  //transmit data buffer
reg [31:0] last_bit_rx;  //last rx data bit location

  always @(posedge clock, posedge reset_n) begin
    if(~reset_n) begin //reset system
      busy <= 1; //set busy signal
      ss_n <= {((slaves - 1)-(0)+1){1'b1}}; //deassert all slave select lines
      mosi <= 1'bZ; //set master out to high impedance
      rx_data <= {((d_width - 1)-(0)+1){1'b0}}; //clear receive data port
      state <= ready; //go to ready state when reset is exited
    end else begin
      case(state) //state machine
      ready : begin
        busy <= 0; //clock out not busy signal
        ss_n <= {((slaves - 1)-(0)+1){1'b1}}; //set all slave select outputs high
        mosi <= 1'bZ; //set mosi output high impedance
        continue <= 0; //clear continue flag
        //user input to initiate transaction
        if(enable) begin
          busy <= 1; //set busy signal
          if((addr < slaves)) begin //check for valid slave address
            slave <= addr; //clock in current slave selection if valid
          end
          else begin
            slave <= 0; //set to first slave if not valid
          end
          if((clk_div == 0)) begin //check for valid spi speed
            clk_ratio <= 1; //set to maximum speed if zero
            count <= 1; //initiate system-to-spi clock counter
          end
          else begin
            clk_ratio <= clk_div; //set to input selection if valid
            count <= clk_div; //initiate system-to-spi clock counter
          end
          sclk <= cpol; //set spi clock polarity
          assert_data <=  ~cpha; //set spi clock phase
          tx_buffer <= tx_data; //clock in data for transmit into buffer
          clk_toggles <= 0; //initiate clock toggle counter
          last_bit_rx <= d_width * 2 + (cpha) - 1; //set last rx data bit
          state <= execute; //proceed to execute state
        end
        else begin
          state <= ready; //remain in ready state
        end
      end
      execute : begin
        busy <= 1; //set busy signal
        ss_n[slave] <= 0; //set proper slave select output
        //system clock to sclk ratio is met
        if((count == clk_ratio)) begin
          count <= 1; //reset system-to-spi clock counter
          assert_data <=  ~assert_data; //switch transmit/receive indicator
          if((clk_toggles == (d_width * 2 + 1))) begin
            clk_toggles <= 0; //reset spi clock toggles counter
          end
          else begin
            clk_toggles <= clk_toggles + 1; //increment spi clock toggles counter
          end
          //spi clock toggle needed
          if(clk_toggles <= (d_width * 2) & ~ss_n[slave]) begin
            sclk <=  ~sclk; //toggle spi clock
          end
          //receive spi clock toggle
          if(~assert_data & clk_toggles < (last_bit_rx + 1) & ~ss_n[slave]) begin
            rx_buffer <= {rx_buffer[d_width - 2:0],miso}; //shift in received bit
          end
          //transmit spi clock toggle
          if(assert_data & clk_toggles < last_bit_rx) begin
            mosi <= tx_buffer[d_width - 1]; //clock out data bit
            tx_buffer <= {tx_buffer[d_width - 2:0],1'b0}; //shift data transmit buffer
          end
          //last data receive, but continue
          if((clk_toggles == last_bit_rx & cont) begin
            tx_buffer <= tx_data; //reload transmit buffer
            clk_toggles <= last_bit_rx - d_width * 2 + 1; //reset spi clock toggle counter
            continue <= 1; //set continue flag
          end
          //normal end of transaction, but continue
          if(continue) begin
            continue <= 0; //clear continue flag
            busy <= 0; //clock out signal that first receive data is ready
            rx_data <= rx_buffer; //clock out received data to output port    
          end
          //end of transaction
          if((clk_toggles == (d_width * 2 + 1)) & ~cont) begin
            busy <= 0; //clock out not busy signal
            ss_n <= {((slaves - 1)-(0)+1){1'b1}}; //set all slave selects high
            mosi <= 1'bZ; //set mosi output high impedance
            rx_data <= rx_buffer; //clock out received data to output port
            state <= ready; //return to ready state
          end
          else begin
            //not end of transaction
            state <= execute; //remain in execute state
          end
        end
        else begin
          //system clock to sclk ratio not met
          count <= count + 1; //increment counter
          state <= execute; //remain in execute state
        end
      end
      endcase
    end
  end

endmodule
