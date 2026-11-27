`timescale 1ns / 1ps

module tb_irq_post_synth #(
    parameter FORWARDING = 1
);
    reg clk = 0, rst = 1;
    reg [9:0] sources = 0;
    reg irq_cyc = 0, irq_stb = 0, irq_we = 0;
    reg [3:0] irq_sel = 0;
    reg [31:0] irq_wdata = 0;
    wire irq, irq_active, irq_ack;
    wire [31:0] pc;
    wire [10:0] sram_addr;
    wire [7:0] sram_data;
    wire cs_n, oe_n, we_n;
    reg [31:0] rom [0:63];
    integer i, entries = 0;
    integer first_count;

    always #5 clk = ~clk;
    arm_core core (
        .clk(clk), .rst(rst), .forwarding_en(FORWARDING != 0),
        .irq(irq), .irq_active(irq_active),
        .instruction_in(rom[pc[5:0]]), .pc_out(pc),
        .sram_addr(sram_addr), .sram_data(sram_data),
        .sram_cs_n(cs_n), .sram_oe_n(oe_n), .sram_we_n(we_n)
    );
    sram_model ram (
        .clk(clk), .Address(sram_addr), .DataIO(sram_data),
        .CS_n(cs_n), .OE_n(oe_n), .WE_n(we_n)
    );
    irq_controller interrupt_controller (
        .clk(clk), .rst(rst), .sources(sources), .irq(irq),
        .wb_cyc(irq_cyc), .wb_stb(irq_stb), .wb_we(irq_we),
        .wb_addr(4'h0), .wb_wdata(irq_wdata), .wb_sel(irq_sel),
        .wb_ack(irq_ack), .wb_err(), .wb_stall(), .wb_rdata()
    );

    always @(posedge irq_active)
        if (!rst) entries = entries + 1;

    function [31:0] read_word;
        input integer addr;
        begin
            read_word = {ram.memory[addr + 3], ram.memory[addr + 2],
                         ram.memory[addr + 1], ram.memory[addr]};
        end
    endfunction

    initial begin
        for (i = 0; i < 64; i = i + 1) rom[i] = 0;
        rom[0]  = 32'hea00000e; // B main
        rom[6]  = 32'hea000020; // IRQ vector: B handler
        rom[16] = 32'he3a01080; // MOV r1,#128
        rom[17] = 32'he3a0205a; // MOV r2,#90
        rom[18] = 32'he5812000; // STR r2,[r1]
        rom[19] = 32'he5913000; // LDR r3,[r1]
        rom[20] = 32'he353005a; // CMP r3,#90
        rom[21] = 32'he3a00000; // MOV r0,#0
        rom[22] = 32'he2800001; // ADD r0,r0,#1
        rom[23] = 32'he5810004; // STR r0,[r1,#4]
        rom[24] = 32'h03a06001; // MOVEQ r6,#1
        rom[25] = 32'h13a06002; // MOVNE r6,#2
        rom[26] = 32'he5816014; // STR r6,[r1,#20]
        rom[27] = 32'he581d018; // STR sp,[r1,#24]
        rom[28] = 32'heafffff8; // B to ADD
        rom[40] = 32'he2844001; // ADD r4,r4,#1
        rom[41] = 32'he3a0d064; // MOV sp,#100
        rom[42] = 32'he581d008; // STR sp,[r1,#8]
        rom[43] = 32'he581e00c; // STR lr,[r1,#12]
        rom[44] = 32'he3a05000; // MOV r5,#0
        rom[45] = 32'h03a05001; // MOVEQ r5,#1
        rom[46] = 32'he5815010; // STR r5,[r1,#16]
        rom[47] = 32'he3550000; // CMP r5,#0
        rom[48] = 32'he581401c; // STR r4,[r1,#28]
        rom[49] = 32'he25ef004; // SUBS pc,lr,#4

        #201 rst = 0;
        @(negedge clk);
        irq_cyc = 1; irq_stb = 1; irq_we = 1; irq_sel = 1; irq_wdata = 1;
        @(posedge clk); #1;
        if (!irq_ack) $fatal(1, "IRQ mask write not acknowledged");
        @(negedge clk);
        irq_cyc = 0; irq_stb = 0; irq_we = 0;

        wait (!cs_n && !we_n && sram_addr == 132);
        sources = 1;
        wait (irq_active);
        #1 sources = 0;
        wait (!irq_active);
        wait (ram.memory[132] >= 3 && ram.memory[152] == 13);
        #1;
        if (entries != 1 || read_word(128) !== 32'h5a ||
            read_word(136) !== 32'd100 || read_word(144) !== 32'd1 ||
            read_word(148) !== 32'd1 || read_word(152) !== 32'd13 ||
            read_word(156) !== 32'd5)
            $fatal(1, "First IRQ, banked SP, flags, memory or return failed");
        if ((^read_word(140)) === 1'bx ||
            read_word(140) < 32'd92 || read_word(140) > 32'd120 ||
            ram.memory[140][1:0] !== 0)
            $fatal(1, "IRQ LR does not point into the main loop");

        first_count = read_word(132);
        sources = 1;
        wait (entries == 3);
        #1 sources = 0;
        wait (!irq_active);
        wait (ram.memory[132] >= first_count + 2);
        #1;
        if (entries != 3 || read_word(156) !== 32'd7 ||
            read_word(144) !== 32'd1 || read_word(148) !== 32'd1 ||
            read_word(152) !== 32'd13)
            $fatal(1, "Level IRQ retrigger or resumed execution failed");
        $display("PASS: post-synthesis IRQ memory stall, banking, flags, return and retrigger (forwarding=%0d)", FORWARDING);
        $finish;
    end
    initial begin
        #200000;
        $fatal(1, "Post-synthesis IRQ test timed out at PC %h (entries=%0d)", pc, entries);
    end
endmodule

module tb_irq_post_synth_forwarding;
    tb_irq_post_synth #(.FORWARDING(1)) test();
endmodule

module tb_irq_post_synth_no_forwarding;
    tb_irq_post_synth #(.FORWARDING(0)) test();
endmodule
