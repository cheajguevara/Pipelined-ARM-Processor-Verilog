`timescale 1ns / 1ps

module tb_uart_c;
    localparam CLKS_PER_BIT = 16;
    localparam [10:0] UART_ADDR = 11'h1fc;

    reg clk = 0;
    reg rst = 1;
    wire [31:0] pc;
    wire [31:0] instruction;
    wire [10:0] sram_addr;
    wire [7:0] sram_data;
    wire sram_cs_n, sram_oe_n, sram_we_n;
    wire tx, overrun;
    wire uart_selected = sram_addr[10:2] == UART_ADDR[10:2];
    integer busy_reads = 0;
    reg [7:0] received;

    always #5 clk = ~clk;

    instruction_memory #(.INIT_FILE("uart_program.hex")) rom (
        .addr(pc),
        .instruction(instruction)
    );

`ifdef POST_SYNTH
    arm_core core (
`else
    arm_core #(.ARM_COMPATIBLE(1)) core (
`endif
        .clk(clk),
        .rst(rst),
        .forwarding_en(1'b1),
        .irq(1'b0),
        .irq_active(),
        .instruction_in(instruction),
        .pc_out(pc),
        .sram_addr(sram_addr),
        .sram_data(sram_data),
        .sram_cs_n(sram_cs_n),
        .sram_oe_n(sram_oe_n),
        .sram_we_n(sram_we_n)
    );

    sram_model ram (
        .clk(clk),
        .Address(sram_addr),
        .DataIO(sram_data),
        .CS_n(sram_cs_n | uart_selected),
        .OE_n(sram_oe_n),
        .WE_n(sram_we_n)
    );

    uart_mmio #(.BASE_ADDR(UART_ADDR), .CLKS_PER_BIT(CLKS_PER_BIT)) uart (
        .clk(clk),
        .rst(rst),
        .addr(sram_addr),
        .data(sram_data),
        .cs_n(sram_cs_n),
        .oe_n(sram_oe_n),
        .we_n(sram_we_n),
        .tx(tx),
        .overrun(overrun)
    );

    always @(posedge clk)
        if (!rst && !sram_cs_n && !sram_oe_n &&
            sram_addr == UART_ADDR && uart.busy)
            busy_reads = busy_reads + 1;

    task receive_byte;
        output [7:0] value;
        integer i;
        begin
            @(negedge tx);
            #(CLKS_PER_BIT * 5);
            if (tx !== 1'b0)
                $fatal(1, "Invalid UART start bit");
            for (i = 0; i < 8; i = i + 1) begin
                #(CLKS_PER_BIT * 10);
                value[i] = tx;
            end
            #(CLKS_PER_BIT * 10);
            if (tx !== 1'b1)
                $fatal(1, "Invalid UART stop bit");
        end
    endtask

    initial begin
`ifdef POST_SYNTH
        #201 rst = 0;
`else
        #31 rst = 0;
`endif
        $write("UART TX: ");
        receive_byte(received);
        if (received !== "O") $fatal(1, "Expected O, received %02x", received);
        $write("%c", received);
        receive_byte(received);
        if (received !== "K") $fatal(1, "Expected K, received %02x", received);
        $write("%c", received);
        receive_byte(received);
        if (received !== 8'h0a) $fatal(1, "Expected newline, received %02x", received);
        $write("%c", received);
        if (overrun) $fatal(1, "UART transmit overrun");
        if (busy_reads == 0) $fatal(1, "Firmware did not exercise UART busy polling");
        $display("PASS: ARM C firmware transmitted OK\\n, including busy polling");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "UART firmware test timed out (PC = %08x)", pc);
    end
endmodule
