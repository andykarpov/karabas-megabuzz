//   Version 1.0 03/29/2019 Scott Larson

module i2s_transceiver(
    input wire                  reset_n,    //asynchronous active low reset
    input wire                  mclk,       //master clock
    output wire                 sclk,       //serial clock (or bit clock)
    output wire                 ws,         //word select (or left-right clock)
    output reg                  sd_tx,      //serial data transmit
    input wire                  sd_rx,      //serial data receive
    input wire [d_width - 1:0]  l_data_tx,  //left channel data to transmit
    input wire [d_width - 1:0]  r_data_tx,  //right channel data to transmit
    output reg [d_width - 1:0]  l_data_rx,  //left channel data received
    output reg [d_width - 1:0]  r_data_rx   //right channel data received
);

    parameter [31:0] mclk_sclk_ratio=8;
    parameter [31:0] sclk_ws_ratio=64;
    parameter [31:0] d_width=24; //data width

    reg sclk_int = 1'b0;  //internal serial clock signal
    reg ws_int = 1'b0;  //internal word select signal
    reg [d_width - 1:0] l_data_rx_int;  //internal left channel rx data buffer
    reg [d_width - 1:0] r_data_rx_int;  //internal right channel rx data buffer
    reg [d_width - 1:0] l_data_tx_int;  //internal left channel tx data buffer
    reg [d_width - 1:0] r_data_tx_int;  //internal right channel tx data buffer

    reg [31:0] sclk_cnt = 0; //counter of master clocks during half period of serial clock
    reg [31:0] ws_cnt = 0;   //counter of serial clock toggles during half period of word select
    always @(posedge mclk, posedge reset_n) begin : P1
        if((reset_n == 1'b0)) begin //asynchronous reset
          sclk_cnt = 0; //clear mclk/sclk counter
          ws_cnt = 0; //clear sclk/ws counter
          sclk_int <= 1'b0; //clear serial clock signal
          ws_int <= 1'b0; //clear word select signal
          l_data_rx_int <= {((d_width - 1)-(0)+1){1'b0}}; //clear internal left channel rx data buffer
          r_data_rx_int <= {((d_width - 1)-(0)+1){1'b0}}; //clear internal right channel rx data buffer
          l_data_tx_int <= {((d_width - 1)-(0)+1){1'b0}}; //clear internal left channel tx data buffer
          r_data_tx_int <= {((d_width - 1)-(0)+1){1'b0}}; //clear internal right channel tx data buffer
          sd_tx <= 1'b0; //clear serial data transmit output
          l_data_rx <= {((d_width - 1)-(0)+1){1'b0}}; //clear left channel received data output
          r_data_rx <= {((d_width - 1)-(0)+1){1'b0}}; //clear right channel received data output
        end else begin //master clock rising edge
          if((sclk_cnt < (mclk_sclk_ratio / 2 - 1))) begin //less than half period of sclk
            sclk_cnt = sclk_cnt + 1; //increment mclk/sclk counter
          end
          else begin //half period of sclk
            sclk_cnt = 0; //reset mclk/sclk counter
            sclk_int <=  ~sclk_int; //toggle serial clock

            //less than half period of ws
            if((ws_cnt < (sclk_ws_ratio - 1))) begin
              ws_cnt = ws_cnt + 1; //increment sclk/ws counter
                 
              //rising edge of sclk during data word
              if((sclk_int == 1'b0 && ws_cnt > 1 && ws_cnt < (d_width * 2 + 2))) begin 
                if((ws_int == 1'b1)) begin //right channel
                  r_data_rx_int <= {r_data_rx_int[d_width - 2:0],sd_rx}; //shift data bit into right channel rx data buffer
                end
                else begin //left channel
                  l_data_rx_int <= {l_data_rx_int[d_width - 2:0],sd_rx}; //shift data bit into left channel rx data buffer
                end
              end

              //falling edge of sclk during data word
              if((sclk_int == 1'b1 && ws_cnt < (d_width * 2 + 3))) begin 
                if((ws_int == 1'b1)) begin //right channel
                  sd_tx <= r_data_tx_int[d_width - 1];                  //transmit serial data bit 
                  r_data_tx_int <= {r_data_tx_int[d_width - 2:0],1'b0}; //shift data of right channel tx data buffer
                end
                else begin //left channel
                  sd_tx <= l_data_tx_int[d_width - 1];                  //transmit serial data bit
                  l_data_tx_int <= {l_data_tx_int[d_width - 2:0],1'b0}; //shift data of left channel tx data buffer
                end
              end
            end
            else begin //half period of ws
              ws_cnt = 0;                 //reset sclk/ws counter        
              ws_int <=  ~ws_int;         //toggle word select
              r_data_rx <= r_data_rx_int; //output right channel received data
              l_data_rx <= l_data_rx_int; //output left channel received data
              r_data_tx_int <= r_data_tx; //latch in right channel data to transmit
              l_data_tx_int <= l_data_tx; //latch in left channel data to transmit
            end
          end
        end
    end

    assign sclk = sclk_int; //output serial clock
    assign ws = ws_int;     //output word select

endmodule
