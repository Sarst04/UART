////////////////////////////////////////////////////////////////////////////////
// File       : fifo.sv
// Author(s)  : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Created    : 2026-09-01
// Description:
//
// Revisions:
//   2026-09-01 - Initial release (Sayyid Amirreza Sayyid Torabi)
////////////////////////////////////////////////////////////////////////////////
module uartFifo #(
	parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 4 
)(
	input  wire						clk,
	input  wire						rst,

    // WRITE INTERFACE
    input  wire [DATA_WIDTH-1:0]	writeData,
    input  wire              		writeEn,
    output logic                	full,

    // READ INTERFACE
    output logic [DATA_WIDTH-1:0]	readData,
    input  wire                  	readEn,
    output logic                 	empty
);
	localparam int PTR_WIDTH  = $clog2(FIFO_DEPTH) + 1;
    localparam int ADDR_WIDTH = $clog2(FIFO_DEPTH);

	logic [DATA_WIDTH-1:0]	buffer	[FIFO_DEPTH];

	logic [PTR_WIDTH-1:0]	writePtr;
	logic [PTR_WIDTH-1:0] 	readPtr;

	assign	readData	=	buffer[readPtr[ADDR_WIDTH-1:0]];

    assign empty = (writePtr == readPtr);
    assign full  = (writePtr == {~readPtr[PTR_WIDTH-1], readPtr[PTR_WIDTH-2:0]});


	always_ff @(posedge clk or posedge rst) begin
		if (rst) begin
			for (int i=0; i < FIFO_DEPTH ; i++)
				buffer[i] <= '0;
			writePtr 	<= '0;
			readPtr 	<= '0;
		end else begin
			if (writeEn & ~full) begin
				writePtr <= writePtr +1;
				buffer[writePtr[ADDR_WIDTH-1:0]]	<= writeData;
			end
			if (readEn & ~empty) begin
				readPtr 			<= readPtr +1;
			end
		end
	end

endmodule
