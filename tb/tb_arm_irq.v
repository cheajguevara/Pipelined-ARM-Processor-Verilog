`timescale 1ns / 1ps

module tb_arm_irq #(
    parameter FORWARDING = 1
);
    reg clk = 0, rst = 1;
    reg [9:0] sources = 0;
    reg irq_cyc = 0, irq_stb = 0, irq_we = 0;
    reg [3:0] irq_addr = 0, irq_sel = 0;
    reg [31:0] irq_wdata = 0;
    wire irq, irq_active, irq_ack;
    wire [31:0] pc;
    wire [10:0] sram_addr;
    wire [7:0] sram_data;
    wire cs_n, oe_n, we_n;
    wire [31:0] disabled_pc;
    wire [10:0] disabled_addr;
    wire [7:0] disabled_data;
    wire disabled_cs_n, disabled_oe_n, disabled_we_n, disabled_active;
    reg [31:0] rom [0:63];
    integer i, entries;
    reg [3:0] saved_flags;
    reg [31:0] resume_pc;

    always #5 clk = ~clk;
    arm_core #(.ARM_COMPATIBLE(1), .IRQ_SUPPORT(1)) core (
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
    arm_core #(.ARM_COMPATIBLE(1)) disabled_core (
        .clk(clk), .rst(rst), .forwarding_en(1'b1),
        .irq(1'b1), .irq_active(disabled_active),
        .instruction_in(rom[disabled_pc[5:0]]), .pc_out(disabled_pc),
        .sram_addr(disabled_addr), .sram_data(disabled_data),
        .sram_cs_n(disabled_cs_n), .sram_oe_n(disabled_oe_n),
        .sram_we_n(disabled_we_n)
    );
    sram_model disabled_ram (
        .clk(clk), .Address(disabled_addr), .DataIO(disabled_data),
        .CS_n(disabled_cs_n), .OE_n(disabled_oe_n), .WE_n(disabled_we_n)
    );
    irq_controller interrupt_controller (
        .clk(clk), .rst(rst), .sources(sources), .irq(irq),
        .wb_cyc(irq_cyc), .wb_stb(irq_stb), .wb_we(irq_we),
        .wb_addr(irq_addr), .wb_wdata(irq_wdata), .wb_sel(irq_sel),
        .wb_ack(irq_ack), .wb_err(), .wb_stall(), .wb_rdata()
    );

    always @(posedge irq_active)
        if (!rst) entries = entries + 1;

    initial begin
        for (i = 0; i < 64; i = i + 1) rom[i] = 0;
        rom[0]  = 32'hea00000e; // B main
        rom[6]  = 32'hea000010; // IRQ vector: B handler
        rom[16] = 32'he3a00000; // MOV r0,#0
        rom[17] = 32'he3a01080; // MOV r1,#128
        rom[18] = 32'he3a0205a; // MOV r2,#90
        rom[19] = 32'he5812000; // STR r2,[r1]
        rom[20] = 32'he5913000; // LDR r3,[r1]
        rom[21] = 32'he353005a; // CMP r3,#90
        rom[22] = 32'he2800001; // ADD r0,r0,#1
        rom[23] = 32'heafffffd; // B to ADD
        rom[24] = 32'he2844001; // ADD r4,r4,#1
        rom[25] = 32'he3a0d064; // MOV r13,#100
        rom[26] = 32'he3500001; // CMP r0,#1
        rom[27] = 32'he25ef004; // SUBS pc,lr,#4
        entries = 0;

        #31 rst = 0;
        @(negedge clk);
        irq_cyc = 1; irq_stb = 1; irq_we = 1; irq_sel = 1; irq_wdata = 1;
        @(posedge clk); #1;
        if (!irq_ack) $fatal(1, "IRQ mask write not acknowledged");
        @(negedge clk);
        irq_cyc = 0; irq_stb = 0; irq_we = 0;
        wait (!core.sram_ready);
        sources = 1;
        wait (irq_active);
        #1;
        saved_flags = core.irq_saved_flags;
        resume_pc = (core.irq_return_addr - 4) >> 2;
        if (core.id_stage_inst.reg_file.rf[13] !== 13)
            $fatal(1, "Main-mode SP changed on IRQ entry");
        @(negedge clk); #1;
        if (core.id_stage_inst.reg_file.irq_lr !== core.irq_return_addr)
            $fatal(1, "IRQ LR was not initialized to the return address");
        wait (core.id_stage_inst.reg_file.irq_sp == 100);
        if (entries != 1) $fatal(1, "Unexpected nested interrupt");
        wait (core.status_flags_exe != saved_flags);
        sources = 0;
        wait (!irq_active);
        #1;
        if (pc !== resume_pc || core.status_flags_exe !== saved_flags)
            $fatal(1, "IRQ return PC or flags mismatch");
        wait (core.id_stage_inst.reg_file.rf[0] >= 2);
        if (core.id_stage_inst.reg_file.rf[3] !== 32'h5a)
            $fatal(1, "Interrupted memory access did not complete");
        if (core.id_stage_inst.reg_file.rf[4] !== 5)
            $fatal(1, "IRQ handler did not run exactly once");
        if (core.id_stage_inst.reg_file.rf[13] !== 13)
            $fatal(1, "IRQ-mode SP was not banked");
        if (core.id_stage_inst.reg_file.rf[14] !== 14)
            $fatal(1, "IRQ-mode LR was not banked");
        if (core.status_flags_exe !== 4'b1000)
            $fatal(1, "Main comparison flags are incorrect");

        sources = 1;
        wait (irq_active);
        #1;
        saved_flags = core.irq_saved_flags;
        resume_pc = (core.irq_return_addr - 4) >> 2;
        if (saved_flags !== 4'b1000) $fatal(1, "Expected main comparison flags");
        if (resume_pc != 22 && resume_pc != 23)
            $fatal(1, "IRQ interrupted branch loop at unexpected PC %d", resume_pc);
        wait (core.status_flags_exe != saved_flags);
        sources = 0;
        wait (!irq_active);
        #1;
        if (pc !== resume_pc || core.status_flags_exe !== saved_flags)
            $fatal(1, "Second IRQ return PC or flags mismatch");
        repeat (12) @(posedge clk);
        #1;
        if (entries != 2 || core.id_stage_inst.reg_file.rf[4] !== 6)
            $fatal(1, "Second IRQ was missed or nested");

        sources = 1;
        wait (irq_active);
        wait (!irq_active);
        wait (irq_active);
        #1;
        if (entries != 4) $fatal(1, "A still-asserted IRQ did not retrigger");
        sources = 0;
        wait (!irq_active);
        repeat (12) @(posedge clk);
        #1;
        if (entries != 4 || core.id_stage_inst.reg_file.rf[4] !== 8)
            $fatal(1, "Level-triggered IRQ was lost or entered more than twice");
        if (disabled_active || disabled_core.id_stage_inst.reg_file.rf[4] !== 4 ||
            disabled_core.id_stage_inst.reg_file.rf[0] < 2)
            $fatal(1, "IRQ changed execution when IRQ_SUPPORT is disabled");
        $display("PASS: IRQ entry, memory stall, banked SP, flags and return");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "IRQ integration timed out at PC %h state %d", pc, core.irq_state);
    end
endmodule
