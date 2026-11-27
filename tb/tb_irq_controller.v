`timescale 1ns / 1ps

module tb_irq_controller;
    reg clk = 0, rst = 1;
    reg [9:0] sources = 0;
    wire irq, wb_ack, wb_err, wb_stall;
    reg wb_cyc = 0, wb_stb = 0, wb_we = 0;
    reg [3:0] wb_addr = 0, wb_sel = 0;
    reg [31:0] wb_wdata = 0;
    wire [31:0] wb_rdata;
    integer source_index;

    always #5 clk = ~clk;
    irq_controller dut (
        .clk(clk), .rst(rst), .sources(sources), .irq(irq),
        .wb_cyc(wb_cyc), .wb_stb(wb_stb), .wb_we(wb_we),
        .wb_addr(wb_addr), .wb_wdata(wb_wdata), .wb_sel(wb_sel),
        .wb_ack(wb_ack), .wb_err(wb_err), .wb_stall(wb_stall), .wb_rdata(wb_rdata)
    );

    task access;
        input we;
        input [3:0] addr;
        input [3:0] sel;
        input [31:0] value;
        begin
            @(negedge clk);
            wb_cyc = 1; wb_stb = 1; wb_we = we;
            wb_addr = addr; wb_sel = sel; wb_wdata = value;
            @(posedge clk); #1;
            if (!wb_ack || wb_err || wb_stall) $fatal(1, "Wishbone request did not complete");
            @(negedge clk);
            wb_cyc = 0; wb_stb = 0;
        end
    endtask

    initial begin
        #21 rst = 0;
        sources = 10'b1000001010;
        #1;
        if (irq) $fatal(1, "Interrupt must be masked after reset");
        access(1, 0, 4'b0011, 32'h20a);
        if (!irq) $fatal(1, "Enabled level interrupt was not asserted");
        access(0, 4, 0, 0);
        if (wb_rdata !== 32'h20a) $fatal(1, "Pending register mismatch");
        access(0, 8, 0, 0);
        if (wb_rdata !== 32'h11) $fatal(1, "Priority must select source 1");
        sources[1] = 0;
        access(0, 8, 0, 0);
        if (wb_rdata !== 32'h13) $fatal(1, "Priority must advance to source 3");
        access(1, 0, 4'b0001, 0);
        access(0, 0, 0, 0);
        if (wb_rdata !== 32'h200) $fatal(1, "Byte write corrupted other enable bits");
        access(0, 8, 0, 0);
        if (wb_rdata !== 32'h19) $fatal(1, "Priority must select source 9");
        sources = 0;
        access(0, 8, 0, 0);
        if (irq || wb_rdata !== 32'h0f) $fatal(1, "IRQ must clear when sources clear");
        access(1, 0, 4'b0011, 32'h3ff);
        for (source_index = 0; source_index < 10; source_index = source_index + 1) begin
            sources = 10'b1 << source_index;
            access(0, 4, 0, 0);
            if (!irq || wb_rdata !== (32'b1 << source_index))
                $fatal(1, "Source %0d did not appear in pending", source_index);
            access(0, 8, 0, 0);
            if (wb_rdata !== (32'h10 | source_index))
                $fatal(1, "Source %0d priority mismatch", source_index);
        end
        access(1, 0, 4'b0011, 0);
        access(0, 12, 0, 0);
        if (irq || wb_rdata !== 32'h200)
            $fatal(1, "Raw source must remain visible when masked");
        @(posedge clk); #1;
        if (wb_ack) $fatal(1, "ACK remained asserted without a request");
        @(negedge clk);
        wb_cyc = 1; wb_stb = 1; wb_addr = 1;
        @(posedge clk); #1;
        if (wb_ack || !wb_err) $fatal(1, "Unaligned request did not report an error");
        $display("PASS: IRQ mask, priority, level behavior and Wishbone accesses");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "IRQ controller test timed out");
    end
endmodule
