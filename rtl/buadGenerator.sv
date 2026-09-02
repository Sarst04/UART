////////////////////////////////////////////////////////////////////////////////
// File       : baudGenerator.sv
// Author(s)  : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Created    : 2026-09-01
// Description:
//
// Revisions:
//   2026-09-01 - Initial release (Sayyid Amirreza Sayyid Torabi)
////////////////////////////////////////////////////////////////////////////////
module uartBaudGenerator #(
	parameter	CLK_FREQUENCY = 50_000_000,
	parameter	BAUD_RATE 	  = 9600,
	parameter	OVERSAMPLE    = 16
)(
	input  wire		clk,
	input  wire		rst,

	output logic	fastTick,
	output logic	slowTick
);
    localparam int FAST_COUNT_MAX = (CLK_FREQUENCY / (BAUD_RATE * OVERSAMPLE)) - 1;
    localparam int SLOW_COUNT_MAX = OVERSAMPLE - 1;

    localparam int FAST_WIDTH = (FAST_COUNT_MAX > 1) ? $clog2(FAST_COUNT_MAX + 1) : 1;
    localparam int SLOW_WIDTH = $clog2(OVERSAMPLE);

	logic [FAST_WIDTH - 1: 0] fastCounter;
	logic [SLOW_WIDTH - 1: 0] slowCounter;

    // Fast tick counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            fastCounter <= '0;
            fastTick    <= 1'b0;
        end else begin
            if (fastCounter == FAST_COUNT_MAX) begin
                fastCounter <= '0;
                fastTick    <= 1'b1;
            end else begin
                fastCounter <= fastCounter + 1'b1;
                fastTick    <= 1'b0;
            end
        end
    end

	// Slow tick counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            slowCounter <= '0;
            slowTick    <= 1'b0;
        end else begin
            slowTick <= 1'b0;
            if (fastTick) begin
                if (slowCounter == SLOW_COUNT_MAX) begin
                    slowCounter <= '0;
                    slowTick    <= 1'b1;
                end else begin
                    slowCounter <= slowCounter + 1'b1;
                end
            end
        end
    end
endmodule 