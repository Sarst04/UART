////////////////////////////////////////////////////////////////////////////////
// File       : transmitter.sv
// Author(s)  : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Created    : 2026-09-01
// Description: UART Transmitter with Even Parity (11-bit frame: 1 Start, 8 Data, 1 Parity, 1 Stop)
//
// Revisions:
//   2026-09-01 - Initial release (Sayyid Amirreza Sayyid Torabi)
////////////////////////////////////////////////////////////////////////////////
module uartTransmitter (
    input  wire         clk,
    input  wire         rst,

    input  wire         slowTick,
    input  wire         emptyFifo,

    output logic        readEn,
    output wire         TX,

    input  wire [7:0]   readData
);

	// Data Path
    logic [10:0]	shiftReg;
    logic        	shiftEnable;
    logic        	loadEnable;

    assign TX 		= shiftReg[0];

	wire 			parity;
    assign 			parity = ^readData;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shiftReg <= 11'b0;
        end else if (loadEnable) begin
            shiftReg <= {1'b1, parity, readData, 1'b0}; 
        end else if (shiftEnable) begin
            shiftReg <= {1'b1, shiftReg[10:1]};
        end
    end

    logic [2:0] counter;
    logic       countEnable;
    logic       countClear;
    wire        carryOut;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= 3'b0;
        end else if (countClear) begin
            counter <= 3'b0;
        end else if (countEnable) begin
            counter <= counter + 1'b1;
        end
    end

    assign carryOut = &counter; 


	// Controller
    typedef enum logic [1:0] {
        IDLE,
        DATA,
        PARITY,
        STOP
    } state_t;
    state_t currentState, nextState;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            currentState <= IDLE;
        end else begin
            currentState <= nextState;
        end
    end

    always_comb begin
        nextState = currentState;

        if (slowTick) begin
            unique0 case (currentState)
                IDLE : begin
                    if (!emptyFifo) begin
                        nextState = DATA;
                    end
                end
                DATA : begin
                    if (carryOut) begin
                        nextState = PARITY;
                    end
                end
                PARITY : begin
                    nextState = STOP;
                end
                STOP : begin
                    nextState = IDLE;
                end
            endcase
        end
    end

    always_comb begin
        countEnable = 1'b0;
        countClear  = 1'b0;
        shiftEnable = 1'b0;
        loadEnable  = 1'b0;
        readEn      = 1'b0;

        if (slowTick) begin
            unique0 case (currentState)
                IDLE : begin
                    if (!emptyFifo) begin
                        loadEnable = 1'b1;
                        readEn     = 1'b1;
                    end
                end
                DATA : begin
                    shiftEnable = 1'b1;
                    countEnable = 1'b1;
                end
                PARITY : begin
                    shiftEnable = 1'b1;
                    countClear 	= 1'b1;
                end
                STOP : begin
                    shiftEnable = 1'b1;
                end
            endcase
        end
    end

endmodule