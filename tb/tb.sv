`timescale 1ns/1ps

module tb;

    localparam int CLK_FREQUENCY = 1_000_000;
    localparam int BAUD_RATE     = 15_625;
    localparam int FIFO_DEPTH    = 8;
    localparam int OVERSAMPLE    = 16;

    localparam int FAST_COUNT_MAX = (CLK_FREQUENCY/(BAUD_RATE*OVERSAMPLE)) - 1;
    localparam int CLKS_PER_BIT   = OVERSAMPLE * (FAST_COUNT_MAX + 1);

    localparam logic [31:0] ADDR_DATA    = 32'h0;
    localparam logic [31:0] ADDR_STATUS  = 32'h4;
    localparam logic [31:0] ADDR_CONTROL = 32'h8;

    localparam int STAT_RX_AVAIL  = 0;
    localparam int STAT_TX_AVAIL  = 1;
    localparam int STAT_OVERRUN   = 2;
    localparam int STAT_PARITY    = 3;

    logic         clk;
    logic         rst;
    logic         RX;
    wire          TX;
    logic         readRequest;
    logic         writeRequest;
    logic [31:0]  address;
    logic [31:0]  dataIn;
    logic [31:0]  dataOut;
    logic         irq;

    int errors = 0;
    int checks = 0;

    uart #(
        .CLK_FREQUENCY (CLK_FREQUENCY),
        .BAUD_RATE     (BAUD_RATE),
        .FIFO_DEPTH    (FIFO_DEPTH)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .RX           (RX),
        .TX           (TX),
        .readRequest  (readRequest),
        .writeRequest (writeRequest),
        .address      (address),
        .dataIn       (dataIn),
        .dataOut      (dataOut),
        .irq          (irq)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic bus_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk);
        writeRequest <= 1'b1;
        readRequest  <= 1'b0;
        address      <= addr;
        dataIn       <= data;
        @(posedge clk);
        writeRequest <= 1'b0;
        address      <= '0;
        dataIn       <= '0;
    endtask

    task automatic bus_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk);
        readRequest  <= 1'b1;
        writeRequest <= 1'b0;
        address      <= addr;
        #1;
        data = dataOut;
        @(posedge clk);
        readRequest  <= 1'b0;
        address      <= '0;
    endtask

    task automatic check(input logic cond, input string msg);
        checks++;
        if (!cond) begin
            errors++;
            $display("[%0t] FAIL: %s", $time, msg);
        end else begin
            $display("[%0t] PASS: %s", $time, msg);
        end
    endtask

    task automatic uart_send_byte(input logic [7:0] data, input bit force_bad_parity = 0);
        logic parity;
        parity = ^data;
        if (force_bad_parity) parity = ~parity;

        RX = 1'b0;
        repeat (CLKS_PER_BIT) @(posedge clk);

        for (int i = 0; i < 8; i++) begin
            RX = data[i];
            repeat (CLKS_PER_BIT) @(posedge clk);
        end

        RX = parity;
        repeat (CLKS_PER_BIT) @(posedge clk);

        RX = 1'b1;
        repeat (CLKS_PER_BIT) @(posedge clk);
    endtask

    task automatic uart_capture_byte(output logic [7:0] data, output bit parity_ok, output bit stop_ok);
        logic parity_bit;
        logic stop_bit;
        logic expected_parity;

        do begin
            @(posedge clk);
        end while (dut.transmitter.currentState !== dut.transmitter.DATA);

        repeat (CLKS_PER_BIT) @(posedge clk);

        for (int i = 0; i < 8; i++) begin
            data[i] = TX;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end

        parity_bit = TX;
        repeat (CLKS_PER_BIT) @(posedge clk);

        stop_bit = TX;

        expected_parity = ^data;
        parity_ok = (parity_bit === expected_parity);
        stop_ok   = (stop_bit === 1'b1);
    endtask

    task automatic do_reset();
        rst          = 1'b1;
        RX           = 1'b1;
        readRequest  = 1'b0;
        writeRequest = 1'b0;
        address      = '0;
        dataIn       = '0;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);
    endtask

    logic [31:0] rdata;
    logic [7:0]  captured;
    bit          parity_ok, stop_ok;
    logic [7:0]  captured_duplex;
    bit          parity_ok_dup, stop_ok_dup;
    logic [31:0] rx_data_dup;
    logic [7:0]  captured_multi [4];
    bit          parity_ok_multi [4];
    bit          stop_ok_multi [4];
    bit          idle_ok;

    initial begin
        $display("==== UART testbench start (CLKS_PER_BIT=%0d) ====", CLKS_PER_BIT);
        do_reset();

        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_RX_AVAIL] == 1'b0, "T1: no RX data available after reset");
        check(rdata[STAT_TX_AVAIL] == 1'b1, "T1: TX space available after reset");
        check(rdata[STAT_OVERRUN]  == 1'b0, "T1: overRunError clear after reset");
        check(rdata[STAT_PARITY]   == 1'b0, "T1: parityError clear after reset");

        fork
            begin
                bus_write(ADDR_DATA, 32'h000000A5);
            end
            begin
                uart_capture_byte(captured, parity_ok, stop_ok);
            end
        join
        check(captured == 8'hA5, "T2: transmitted byte matches what was written to DATA");
        check(parity_ok, "T2: transmitted parity bit is correct (even parity)");
        check(stop_ok,   "T2: stop bit is 1");

        uart_send_byte(8'h3C);
        repeat (4) @(posedge clk);

        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_RX_AVAIL] == 1'b1, "T3: RX data available after a good frame");

        bus_read(ADDR_DATA, rdata);
        check(rdata[7:0] == 8'h3C, "T3: DATA read returns the byte that was sent");

        repeat (2) @(posedge clk);
        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_RX_AVAIL] == 1'b0, "T3: RX data available deasserts after DATA is popped");
        check(rdata[STAT_PARITY]   == 1'b0, "T3: parityError not set for a good frame");

        uart_send_byte(8'h55, 1'b1);
        repeat (4) @(posedge clk);

        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_PARITY] == 1'b1, "T4: parityError set after a bad-parity frame");

        bus_read(ADDR_DATA, rdata);
        repeat (2) @(posedge clk);
        bus_write(ADDR_STATUS, 32'h0000_0000);

        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_PARITY] == 1'b0, "T4: parityError clears after writing 0 to STATUS");

        for (int i = 0; i < FIFO_DEPTH; i++) begin
            uart_send_byte(8'h11 + i);
            repeat (4) @(posedge clk);
        end
        uart_send_byte(8'hFF);
        repeat (4) @(posedge clk);

        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_OVERRUN] == 1'b1, "T5: overRunError set when RX FIFO was full");

        for (int i = 0; i < FIFO_DEPTH; i++) begin
            bus_read(ADDR_DATA, rdata);
            repeat (2) @(posedge clk);
        end
        bus_write(ADDR_STATUS, 32'h0000_0000);

        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_OVERRUN]  == 1'b0, "T5: overRunError clears after writing 0 to STATUS");
        check(rdata[STAT_RX_AVAIL] == 1'b0, "T5: no RX data available once drained");

        repeat (2*CLKS_PER_BIT*11) @(posedge clk);
        @(posedge dut.slowTick);
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            bus_write(ADDR_DATA, 32'h20 + i);
        end
        repeat (2) @(posedge clk);
        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_TX_AVAIL] == 1'b0, "T6: no TX space available once the TX FIFO is full");

        repeat (FIFO_DEPTH * CLKS_PER_BIT * 11 + 200) @(posedge clk);
        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_TX_AVAIL] == 1'b1, "T6: TX space available again once the TX FIFO drains");

        bus_write(ADDR_CONTROL, 32'h0000_0001);
        check(irq == 1'b0, "T7: irq low with rxIrqEn set but no RX data available");

        uart_send_byte(8'h7E);
        repeat (4) @(posedge clk);
        check(irq == 1'b1, "T7: irq high once RX data is available with rxIrqEn set");

        bus_read(ADDR_DATA, rdata);
        repeat (2) @(posedge clk);
        check(irq == 1'b0, "T7: irq low again once DATA is popped");

        bus_write(ADDR_CONTROL, 32'h0000_0000);

        bus_write(ADDR_CONTROL, 32'h0000_0004);
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            uart_send_byte(8'h01);
            repeat (4) @(posedge clk);
        end
        uart_send_byte(8'h02);
        repeat (4) @(posedge clk);
        check(irq == 1'b1, "T8: irq high on overrun with overRunIrqEn set");

        bus_write(ADDR_STATUS, 32'h0000_0000);
        repeat (2) @(posedge clk);
        check(irq == 1'b0, "T8: irq low again once overRunError is cleared");

        for (int i = 0; i < FIFO_DEPTH; i++) begin
            bus_read(ADDR_DATA, rdata);
            repeat (2) @(posedge clk);
        end
        bus_write(ADDR_CONTROL, 32'h0000_0000);

        repeat (2*CLKS_PER_BIT*11) @(posedge clk);
        @(posedge dut.slowTick);
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            bus_write(ADDR_DATA, 32'h40 + i);
        end
        repeat (2) @(posedge clk);

        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_TX_AVAIL] == 1'b0, "T9: TX space unavailable when FIFO full");

        bus_write(ADDR_DATA, 32'hFF);
        repeat (2) @(posedge clk);

        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_TX_AVAIL] == 1'b0, "T9: TX space still unavailable after write attempt (ignored)");

        repeat (FIFO_DEPTH * CLKS_PER_BIT * 11 + 200) @(posedge clk);
        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_TX_AVAIL] == 1'b1, "T9: TX space available after drain (only expected bytes were sent)");

        repeat (2*CLKS_PER_BIT*11) @(posedge clk);
        @(posedge dut.slowTick);
        for (int i = 0; i < FIFO_DEPTH; i++) begin
            bus_write(ADDR_DATA, 32'h50 + i);
        end
        repeat (2) @(posedge clk);

        bus_write(ADDR_CONTROL, 32'h0000_0002);
        check(irq == 1'b0, "T10: irq low while TX FIFO full and txIrqEn set");

        repeat (CLKS_PER_BIT * 11 + 5) @(posedge clk);

        check(irq == 1'b1, "T10: irq high once TX space becomes available");

        bus_write(ADDR_CONTROL, 32'h0000_0000);
        repeat (2) @(posedge clk);
        check(irq == 1'b0, "T10: irq low after disabling txIrqEn");

        repeat (FIFO_DEPTH * CLKS_PER_BIT * 11 + 200) @(posedge clk);

        bus_write(ADDR_STATUS, 32'h0000_0000);
        repeat (2) @(posedge clk);

        bus_write(ADDR_CONTROL, 32'h0000_0008);
        check(irq == 1'b0, "T11: irq low with parityIrqEn set and no error");

        uart_send_byte(8'hAA, 1'b1);
        repeat (4) @(posedge clk);

        check(irq == 1'b1, "T11: irq high on parity error with parityIrqEn set");

        bus_write(ADDR_STATUS, 32'h0000_0000);
        repeat (2) @(posedge clk);

        check(irq == 1'b0, "T11: irq low after clearing parity error");

        bus_write(ADDR_CONTROL, 32'h0000_0000);
        bus_read(ADDR_DATA, rdata);
        repeat (2) @(posedge clk);

        fork
            begin
                uart_send_byte(8'h5A);
            end
            begin
                bus_write(ADDR_DATA, 32'hC3);
                uart_capture_byte(captured_duplex, parity_ok_dup, stop_ok_dup);
            end
        join

        check(captured_duplex == 8'hC3, "T12: TX byte correct during full-duplex");
        check(parity_ok_dup, "T12: TX parity correct during full-duplex");
        check(stop_ok_dup, "T12: TX stop bit correct during full-duplex");

        repeat (4) @(posedge clk);
        bus_read(ADDR_DATA, rx_data_dup);
        check(rx_data_dup[7:0] == 8'h5A, "T12: RX byte correct during full-duplex");

        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_PARITY] == 1'b0, "T12: no parity error from full-duplex test");
        check(rdata[STAT_OVERRUN] == 1'b0, "T12: no overrun from full-duplex test");

        $display("--- Test 13: RX FIFO order ---");
        bus_write(ADDR_STATUS, 32'h0000_0000);
        repeat (2) @(posedge clk);

        uart_send_byte(8'h11);
        repeat (4) @(posedge clk);
        uart_send_byte(8'h22);
        repeat (4) @(posedge clk);
        uart_send_byte(8'h33);
        repeat (4) @(posedge clk);
        uart_send_byte(8'h44);
        repeat (5 * CLKS_PER_BIT * 11) @(posedge clk);

        for (int i = 0; i < 4; i++) begin
            bus_read(ADDR_DATA, rdata);
            check(rdata[7:0] == (8'h11 + i*8'h11), $sformatf("T13: RX byte %0d correct", i));
            repeat (2) @(posedge clk);
        end

        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_RX_AVAIL] == 1'b0, "T13: RX FIFO empty after reading all bytes");

        $display("--- Test 14: TX FIFO order ---");
        repeat (2*CLKS_PER_BIT*11) @(posedge clk);
        @(posedge dut.slowTick);

        bus_write(ADDR_DATA, 32'hAA);
        bus_write(ADDR_DATA, 32'hBB);
        bus_write(ADDR_DATA, 32'hCC);
        bus_write(ADDR_DATA, 32'hDD);

        for (int i = 0; i < 4; i++) begin
            uart_capture_byte(captured_multi[i], parity_ok_multi[i], stop_ok_multi[i]);
        end

        check(captured_multi[0] == 8'hAA, "T14: first TX byte correct");
        check(captured_multi[1] == 8'hBB, "T14: second TX byte correct");
        check(captured_multi[2] == 8'hCC, "T14: third TX byte correct");
        check(captured_multi[3] == 8'hDD, "T14: fourth TX byte correct");
        check(parity_ok_multi[0] && parity_ok_multi[1] && parity_ok_multi[2] && parity_ok_multi[3],
              "T14: all parity bits correct");
        check(stop_ok_multi[0] && stop_ok_multi[1] && stop_ok_multi[2] && stop_ok_multi[3],
              "T14: all stop bits correct");

        $display("--- Test 15: Individual status bit clearing ---");
        bus_write(ADDR_STATUS, 32'h0000_0000);
        repeat (2) @(posedge clk);

        for (int i = 0; i < FIFO_DEPTH; i++) begin
            uart_send_byte(8'h01);
            repeat (4) @(posedge clk);
        end
        uart_send_byte(8'h02);
        repeat (4) @(posedge clk);

        bus_read(ADDR_DATA, rdata);
        repeat (2) @(posedge clk);

        uart_send_byte(8'h03, 1'b1);
        repeat (4) @(posedge clk);

        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_OVERRUN] == 1'b1, "T15: overrun flag set");
        check(rdata[STAT_PARITY]  == 1'b1, "T15: parity flag set");

        bus_write(ADDR_STATUS, 32'h0000_0004);
        repeat (2) @(posedge clk);

        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_PARITY]  == 1'b0, "T15: parity flag cleared individually");
        check(rdata[STAT_OVERRUN] == 1'b1, "T15: overrun flag still set");

        bus_write(ADDR_STATUS, 32'h0000_0000);
        repeat (2) @(posedge clk);
        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_OVERRUN] == 1'b0, "T15: overrun flag cleared");

        while (1) begin
            bus_read(ADDR_STATUS, rdata);
            if (!rdata[STAT_RX_AVAIL]) break;
            bus_read(ADDR_DATA, rdata);
            repeat (2) @(posedge clk);
        end

        $display("--- Test 16: Multiple interrupts ---");
        bus_write(ADDR_CONTROL, 32'h0000_1001);
        check(irq == 1'b0, "T16: irq low initially");

        uart_send_byte(8'h5A);
        repeat (4) @(posedge clk);
        check(irq == 1'b1, "T16: irq high due to RX data available");
        bus_read(ADDR_DATA, rdata);
        repeat (2) @(posedge clk);
        check(irq == 1'b0, "T16: irq low after reading data");

        uart_send_byte(8'h5A, 1'b1);
        repeat (4) @(posedge clk);
        check(irq == 1'b1, "T16: irq high due to parity error (and RX data)");
        bus_write(ADDR_STATUS, 32'h0000_0000);
        repeat (2) @(posedge clk);
        check(irq == 1'b1, "T16: irq remains high because RX data still available");
        bus_read(ADDR_DATA, rdata);
        repeat (2) @(posedge clk);
        check(irq == 1'b0, "T16: irq low after all sources cleared");

        bus_write(ADDR_CONTROL, 32'h0000_0000);

        $display("--- Test 17: TX idle high ---");
        repeat (FIFO_DEPTH * CLKS_PER_BIT * 11 + 100) @(posedge clk);
        idle_ok = 1;
        for (int i = 0; i < 5 * CLKS_PER_BIT; i++) begin
            @(posedge clk);
            if (TX !== 1'b1) begin
                idle_ok = 0;
                break;
            end
        end
        check(idle_ok, "T17: TX line remains high when idle");

        $display("--- Test 18: Read DATA when empty ---");
        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_RX_AVAIL] == 1'b0, "T18: RX FIFO empty before read");
        bus_read(ADDR_DATA, rdata);
        bus_read(ADDR_STATUS, rdata);
        check(rdata[STAT_OVERRUN] == 1'b0, "T18: no overrun from empty read");
        check(rdata[STAT_PARITY]  == 1'b0, "T18: no parity error from empty read");

        $display("==== UART testbench done: %0d checks, %0d failures ====", checks, errors);
        if (errors == 0) $display("**** ALL TESTS PASSED ****");
        else              $display("**** %0d TEST(S) FAILED ****", errors);

        $finish;
    end

    initial begin
        #2_000_000;
        $display("ERROR: testbench timeout - simulation did not finish");
        $finish;
    end

endmodule