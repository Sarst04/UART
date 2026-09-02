////////////////////////////////////////////////////////////////////////////////
// File       : receiver.sv
// Author(s)  : Sayyid Amirreza Sayyid Torabi <sayyidtorabi@gmail.com>
// Created    : 2026-09-01
// Description: UART Receiver with Even Parity (11-bit frame: 1 Start, 8 Data, 1 Parity, 1 Stop)
//
// Revisions:
//   2026-09-01 - Initial release (Sayyid Amirreza Sayyid Torabi)
//   2026-09-03 - Added OVERSAMPLE parameter; sample counter now parameterized
////////////////////////////////////////////////////////////////////////////////
module uartReceiver #(
    parameter OVERSAMPLE = 16
) (
    input  wire         clk,
    input  wire         rst,

    input  wire         fastTick,
    input  wire         fullFifo,
    input  wire         RX,

    output logic        writeEn,
    output logic        overRunError,
    output logic        parityError,
    output logic [7:0]  writeData
);

    // Synchronizer for RX
    logic RXsync;
    logic RXsyncPre;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            RXsyncPre <= 1'b1;
            RXsync    <= 1'b1;
        end else begin
            RXsync    <= RX;
            RXsyncPre <= RXsync;
        end
    end

    // Sample counter
    localparam int SAMPLE_WIDTH = $clog2(OVERSAMPLE);
    logic [SAMPLE_WIDTH-1:0] sampleCounter;
    logic clrSampleCounter;
    logic incSampleCounter;
    logic halfBitTick;
    logic fullBitTick;

    assign halfBitTick = (sampleCounter == (OVERSAMPLE/2 - 1));
    assign fullBitTick = (sampleCounter == (OVERSAMPLE - 1));

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sampleCounter <= '0;
        end else if (clrSampleCounter) begin
            sampleCounter <= '0;
        end else if (incSampleCounter) begin
            sampleCounter <= sampleCounter + 1'b1;
        end
    end

    // Bit counter (8 data bits)
    logic [2:0] bitCounter;
    logic clrBitCounter;
    logic incBitCounter;
    logic bitCounterCarryOut;

    assign bitCounterCarryOut = &bitCounter;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bitCounter <= 3'd0;
        end else if (clrBitCounter) begin
            bitCounter <= 3'd0;
        end else if (incBitCounter) begin
            bitCounter <= bitCounter + 1'b1;
        end
    end

    // Shift register
    logic shiftEn;
    logic [7:0] shiftReg;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shiftReg <= 8'd0;
        end else if (shiftEn) begin
            shiftReg <= {RXsync, shiftReg[7:1]};
        end
    end
    assign writeData = shiftReg;

    // Parity error detection
    logic chkParity;
    logic clrChkParity;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            parityError <= 1'b0;
        end else if (clrChkParity) begin
            parityError <= 1'b0;
        end else if (chkParity) begin
            parityError <= (^shiftReg) ^ RXsync;
        end
    end

    // FSM States
    typedef enum logic [2:0] {
        IDLE,
        START,
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
        unique0 case (currentState)
            IDLE: begin
                if (!RXsync) begin
                    nextState = START;
                end
            end
            START: begin
                if (fastTick && halfBitTick) begin
                    if (!RXsync) begin
                        nextState = DATA;
                    end else begin
                        nextState = IDLE;
                    end
                end
            end
            DATA: begin
                if (fastTick && fullBitTick) begin
                    if (bitCounterCarryOut) begin
                        nextState = PARITY;
                    end
                end
            end
            PARITY: begin
                if (fastTick && fullBitTick) begin
                    nextState = STOP;
                end
            end
            STOP: begin
                if (fastTick && fullBitTick) begin
                    nextState = IDLE;
                end
            end
        endcase
    end

    always_comb begin
        clrSampleCounter = 1'b0;
        incSampleCounter = 1'b0;
        clrBitCounter    = 1'b0;
        incBitCounter    = 1'b0;
        shiftEn          = 1'b0;
        chkParity        = 1'b0;
        writeEn          = 1'b0;
        overRunError     = 1'b0;
        clrChkParity     = 1'b0;

        unique0 case (currentState)
            IDLE: begin
                clrSampleCounter = 1'b1;
                clrBitCounter    = 1'b1;
                clrChkParity     = 1'b1;
            end
            START: begin
                if (fastTick) begin
                    incSampleCounter = 1'b1;
                    if (halfBitTick) begin
                        clrSampleCounter = 1'b1;
                    end
                end
            end
            DATA: begin
                if (fastTick) begin
                    incSampleCounter = 1'b1;
                    if (fullBitTick) begin
                        shiftEn          = 1'b1;
                        incBitCounter    = 1'b1;
                        clrSampleCounter = 1'b1;
                    end
                end
            end
            PARITY: begin
                if (fastTick) begin
                    incSampleCounter = 1'b1;
                    if (fullBitTick) begin
                        chkParity        = 1'b1;
                        clrSampleCounter = 1'b1;
                    end
                end
            end
            STOP: begin
                if (fastTick) begin
                    incSampleCounter = 1'b1;
                    if (fullBitTick) begin
                        clrSampleCounter = 1'b1;
                        if (fullFifo) begin
                            overRunError = 1'b1;
                        end else begin
                            writeEn      = 1'b1;
                        end
                    end
                end
            end
        endcase
    end

endmodule