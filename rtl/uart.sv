////////////////////////////////////////////////////////////////////////////////
// File       : uart.sv
// Author(s)  : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Created    : 2026-09-01
// Description: Top-level UART: baud generator + TX/RX FIFOs + receiver/transmitter,
//
// Revisions:
//   2026-09-01 - Initial release (Sayyid Amirreza Sayyid Torabi)
////////////////////////////////////////////////////////////////////////////////
module uart #(
    parameter CLK_FREQUENCY = 50_000_000,
    parameter BAUD_RATE     = 9600,
    parameter FIFO_DEPTH    = 8,
	parameter OVERSAMPLE	= 16
)(
    input  wire         clk,
    input  wire         rst,

    input  wire         RX,
    output wire         TX,

    // Bus Side
    input  wire         readRequest,
    input  wire         writeRequest,
    input  wire  [31:0] address,
    input  wire  [31:0] dataIn,
    output logic [31:0] dataOut,

    // Interrupt
    output logic        irq
);

    localparam logic [31:0] ADDR_DATA  	 	= 32'h0;
    localparam logic [31:0] ADDR_STATUS  	= 32'h4;
    localparam logic [31:0] ADDR_CONTROL 	= 32'h8;

	logic [3:0] statusReg;
	logic [3:0] controlReg;

    wire  fastTick;
    wire  slowTick;

    uartBaudGenerator #(
        .CLK_FREQUENCY (CLK_FREQUENCY),
        .BAUD_RATE     (BAUD_RATE),
        .OVERSAMPLE    (OVERSAMPLE)
    ) baudGen (
        .clk      (clk),
        .rst      (rst),
        .fastTick (fastTick),
        .slowTick (slowTick)
    );

    wire  [7:0] rxFifoReadData;
    logic       rxFifoReadEn;
    wire        rxFifoEmpty;

    wire        rxWriteEn;
    wire  [7:0] rxWriteData;
    wire        rxFifoFull;

    wire        overRunError;
    wire        parityError;

    uartReceiver  #(
			.OVERSAMPLE(OVERSAMPLE)
		) receiver (
        .clk          (clk),
        .rst          (rst),

        .RX           (RX),

        .fastTick     (fastTick),
        .writeData    (rxWriteData),
        .writeEn      (rxWriteEn),
        .fullFifo     (rxFifoFull),
        .overRunError (overRunError),
        .parityError  (parityError)
    );

    uartFifo #(
        .DATA_WIDTH (8),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) rxFifo (
        .clk       (clk),
        .rst       (rst),

        .writeData (rxWriteData),
        .writeEn   (rxWriteEn),
        .full      (rxFifoFull),

        .readData  (rxFifoReadData),
        .readEn    (rxFifoReadEn),
        .empty     (rxFifoEmpty)
    );




    logic       txWriteEn;
    logic [7:0] txWriteData;
    wire        txFifoFull;

    wire  [7:0] txFifoReadData;
    wire        txFifoReadEn;
    wire        txFifoEmpty;


    uartTransmitter transmitter (
        .clk       (clk),
        .rst       (rst),

        .TX        (TX),

        .slowTick  (slowTick),
        .readData  (txFifoReadData),
        .readEn    (txFifoReadEn),
        .emptyFifo (txFifoEmpty)
    );

    uartFifo #(
        .DATA_WIDTH (8),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) txFifo (
        .clk       (clk),
        .rst       (rst),

        .writeData (txWriteData),
        .writeEn   (txWriteEn),
        .full      (txFifoFull),

        .readData  (txFifoReadData),
        .readEn    (txFifoReadEn),
        .empty     (txFifoEmpty)
    );




    always_comb begin
        dataOut 		= 32'b0;
		rxFifoReadEn	= 1'b0;
        if (readRequest) begin
            unique0 case (address)
                ADDR_DATA  		: begin 
					dataOut 		= {24'b0, rxFifoReadData};
					rxFifoReadEn	= !rxFifoEmpty;
				end
                ADDR_STATUS  	: dataOut = {24'b0, statusReg};
                ADDR_CONTROL 	: dataOut = {24'b0, controlReg};
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            statusReg  <= 4'b0;
            controlReg <= 4'b0;
        end else begin
			txWriteData 		<= 8'b0;
			txWriteEn			<= 1'b0;
			
			statusReg[0] 		<= !rxFifoEmpty;  // RX data  available
			statusReg[1] 		<= !txFifoFull;   // TX space available

			if (overRunError)
				statusReg[2] 	<= 1'b1;
			
			if (parityError)
				statusReg[3] 	<= 1'b1;

            if (writeRequest) begin
                unique0 case (address)
                    ADDR_DATA: begin
                        if (!txFifoFull) begin
                            txWriteData <= dataIn[7:0];
							txWriteEn	<= 1'b1;
                        end
                    end
                    ADDR_STATUS: begin
                        statusReg[3:2]  <= {dataIn[3:2]};
                    end
                    ADDR_CONTROL: begin
                        controlReg 		<= {dataIn[3:0]};
                    end
                endcase
            end
        end
    end

	assign	irq	= 	( controlReg[0] & statusReg[0] ) | 
					( controlReg[1] & statusReg[1] ) | 
					( controlReg[2] & statusReg[2] ) | 
					( controlReg[3] & statusReg[3] ); 

endmodule