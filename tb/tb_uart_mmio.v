`timescale 1ns / 1ps

module tb_uart_mmio;
    localparam CLKS_PER_BIT = 4;
    reg clk = 0;
    reg rst = 1;
    reg [10:0] addr = 11'h1fc;
    reg [7:0] data_out = 0;
    reg drive = 0;
    reg cs_n = 1;
    reg oe_n = 1;
    reg we_n = 1;
    wire [7:0] data;
    wire tx, overrun;
    reg [7:0] received;
    integer i;

    assign data = drive ? data_out : 8'bz;
    always #5 clk = ~clk;

    uart_mmio #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart (
        .clk(clk), .rst(rst), .addr(addr), .data(data),
        .cs_n(cs_n), .oe_n(oe_n), .we_n(we_n),
        .tx(tx), .overrun(overrun)
    );

    task write_byte;
        input [7:0] value;
        begin
            @(negedge clk);
            data_out = value;
            drive = 1;
            cs_n = 0;
            we_n = 0;
            @(negedge clk);
            drive = 0;
            cs_n = 1;
            we_n = 1;
        end
    endtask

    initial begin
        #30 rst = 0;
        fork
            begin
                write_byte(8'ha5);
                write_byte(8'h5a);
            end
            begin
                @(negedge tx);
                #(CLKS_PER_BIT * 5);
                if (tx !== 0) $fatal(1, "Invalid UART start bit");
                for (i = 0; i < 8; i = i + 1) begin
                    #(CLKS_PER_BIT * 10);
                    received[i] = tx;
                end
                #(CLKS_PER_BIT * 10);
                if (tx !== 1 || received !== 8'ha5)
                    $fatal(1, "UART frame corrupted after busy write: %02x", received);
                #(CLKS_PER_BIT * 10);
                if (!overrun || uart.busy)
                    $fatal(1, "Expected latched overrun and transmitter ready");
                $display("PASS: UART busy write reports overrun without corrupting the frame");
                $finish;
            end
        join
    end

    initial begin
        #5000;
        $fatal(1, "UART unit test timed out");
    end
endmodule
