`timescale 1ns / 1ps

module tb_arm_irq_branch_stall;
    reg clk = 0, rst = 1, irq = 0;
    wire irq_active;
    wire [31:0] pc;
    wire [10:0] sram_addr;
    wire [7:0] sram_data;
    wire cs_n, oe_n, we_n;
    reg [31:0] rom [0:63];
    integer i;

    always #5 clk = ~clk;
    arm_core #(.ARM_COMPATIBLE(1), .IRQ_SUPPORT(1)) core (
        .clk(clk), .rst(rst), .forwarding_en(1'b1),
        .irq(irq), .irq_active(irq_active),
        .instruction_in(rom[pc[5:0]]), .pc_out(pc),
        .sram_addr(sram_addr), .sram_data(sram_data),
        .sram_cs_n(cs_n), .sram_oe_n(oe_n), .sram_we_n(we_n)
    );
    sram_model ram (
        .clk(clk), .Address(sram_addr), .DataIO(sram_data),
        .CS_n(cs_n), .OE_n(oe_n), .WE_n(we_n)
    );

    initial begin
        for (i = 0; i < 64; i = i + 1) rom[i] = 0;
        rom[0]  = 32'hea00000e; // B main
        rom[6]  = 32'hea000010; // B handler
        rom[16] = 32'he3a01080; // MOV r1,#128
        rom[17] = 32'he3a02001; // MOV r2,#1
        rom[18] = 32'he5812000; // STR r2,[r1]
        rom[19] = 32'hea000001; // B target
        rom[20] = 32'he3a080ee; // Wrong path: MOV r8,#238
        rom[21] = 32'he3a080ee;
        rom[22] = 32'he2800001; // Target: ADD r0,r0,#1
        rom[23] = 32'heafffffd; // B target
        rom[24] = 32'he2844001; // Handler: ADD r4,r4,#1
        rom[25] = 32'he25ef004; // SUBS pc,lr,#4
        #31 rst = 0;
        wait (!core.sram_ready && core.b_ex);
        irq = 1;
        wait (irq_active);
        irq = 0;
        wait (!irq_active);
        wait (core.id_stage_inst.reg_file.rf[0] >= 2);
        if (core.id_stage_inst.reg_file.rf[8] !== 8 ||
            core.id_stage_inst.reg_file.rf[4] !== 5 ||
            ram.memory[128] !== 1)
            $fatal(1, "Branch, store, or IRQ handler failed across memory stall");
        $display("PASS: branch held across SRAM stall and IRQ serviced");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "Branch/stall IRQ test timed out at PC %h", pc);
    end
endmodule
