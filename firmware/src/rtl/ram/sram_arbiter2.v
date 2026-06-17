module sram_arbiter (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req1,       
    input  wire [20:0] addr1,      
    input  wire        we1,        
    input  wire [7:0]  din1,       
    output reg  [7:0]  dout1,      
    output reg         ack1,

	 input  wire        clk2, // для wait2
    input  wire        req2,       
    input  wire [20:0] addr2,      
    input  wire        we2,        
    input  wire [7:0]  din2,       
    output reg  [7:0]  dout2,      
    output reg         wait2,

    output reg  [20:0] sram_addr,
    inout  wire [7:0]  sram_data,
    output reg         sram_ce_n,  
    output reg         sram_oe_n,  
    output reg         sram_we_n   
);

    // CDC и детекторы фронтов
    reg [2:0] sync1_ff;
    reg [2:0] sync2_ff;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1_ff <= 3'b0;
            sync2_ff <= 3'b0;
        end else begin
            sync1_ff <= {sync1_ff[1:0], req1};
            sync2_ff <= {sync2_ff[1:0], req2};
        end
    end
    wire req1_edge = sync1_ff[1] && !sync1_ff[2];
    wire req2_edge = sync2_ff[1] && !sync2_ff[2];

    reg req1_pending;
    reg req2_pending;

    // FSM
    localparam STATE_IDLE  = 2'b00;
    localparam STATE_DEV1  = 2'b01;
    localparam STATE_DEV2  = 2'b10;
    
    reg [1:0] state;
    reg [4:0] cycle_cnt; 

    // Логика формирования сигнала WAIT для GS
    wire wait2_int = req2 && (req1_pending || req1_edge || (state == STATE_DEV1));
	 reg [9:0] wait2_reg; // удлиняем до 10 бит, чтобы поймать в медленном клок-домене
	 always @(posedge clk) begin
		if (wait2_int)
			wait2_reg <= 10'b1111111111;
		else
			wait2_reg <= {wait2_reg[8:0], 1'b0};
	 end
	 
	 // формирование wait2 в клок-домене clk2
	 always @(posedge clk2) begin
		if (wait2_reg != 10'b0000000000)
			wait2 <= 1'b1;
		else
			wait2 <= 1'b0;
	 end

    // SRAM
    reg        sram_bus_dir; // 1 - запись, 0 - чтение
    reg [7:0] sram_dout_reg;
    assign sram_data = sram_bus_dir ? sram_dout_reg : 8'hZZ;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= STATE_IDLE;
            cycle_cnt     <= 2'b0;
            ack1          <= 1'b1;
            req1_pending  <= 1'b0;
            req2_pending  <= 1'b0;
            sram_ce_n     <= 1'b1;
            sram_oe_n     <= 1'b1;
            sram_we_n     <= 1'b1;
            sram_bus_dir  <= 1'b0;
            sram_addr     <= 21'b0;
            sram_dout_reg <= 8'hFF;
            dout1         <= 8'hFF;
            dout2         <= 8'hFF;
        end else begin

            if (req1_edge) req1_pending <= 1'b1;
            if (req2_edge) req2_pending <= 1'b1;

            case (state)
                STATE_IDLE: begin
                    sram_ce_n    <= 1'b1;
                    sram_oe_n    <= 1'b1;
                    sram_we_n    <= 1'b1;
                    sram_bus_dir <= 1'b0;
                    cycle_cnt    <= 2'b0;

                    if (req1_pending || req1_edge) begin
                        state        <= STATE_DEV1;
								ack1 			 <= 1'b0;								
                        req1_pending <= 1'b0; 
                        sram_addr    <= addr1;
                        sram_ce_n    <= 1'b0;
                        sram_we_n    <= !we1;
                        sram_oe_n    <= we1;
                        if (we1) begin
                            sram_dout_reg <= din1;
                            sram_bus_dir  <= 1'b1;
                        end
                    end 
                    else if (req2_pending || req2_edge) begin
                        state        <= STATE_DEV2;
                        req2_pending <= 1'b0; 
                        sram_addr    <= addr2;
                        sram_ce_n    <= 1'b0;
                        sram_we_n    <= !we2;
                        sram_oe_n    <= we2;
                        if (we2) begin
                            sram_dout_reg <= din2;
                            sram_bus_dir  <= 1'b1;
                        end
                    end
                end

                STATE_DEV1: begin
                    if (cycle_cnt < 4'd8) begin // 9 тактов (~63 нс)
                        cycle_cnt <= cycle_cnt + 1'b1;
                    end else begin
                        if (!sram_oe_n) dout1 <= sram_data;
                        ack1      <= 1'b1;                  
                        sram_ce_n <= 1'b1;
                        sram_we_n <= 1'b1;
                        sram_oe_n <= 1'b1;
                        state     <= STATE_IDLE;
                    end
                end

                STATE_DEV2: begin
                    if (cycle_cnt < 4'd8) begin // 9 тактов (~63 нс)
                        cycle_cnt <= cycle_cnt + 1'b1;
                    end else begin
                        if (!sram_oe_n) dout2 <= sram_data;
                        sram_ce_n <= 1'b1;
                        sram_we_n <= 1'b1;
                        sram_oe_n <= 1'b1;
                        state     <= STATE_IDLE;
                    end
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

