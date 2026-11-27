//=============================================================================
// File Name:    register_file.v
// Design:       5-Stage Pipelined ARM Processor (ARMv4T Subset)
// Author:       Alireza Najafi Motiei (ID: 810100224)
// Affiliation:  Department of Electrical and Computer Engineering, University of Tehran
// Course:       Computer Architecture Laboratory (Dr. Saeed Safari)
// Description:  16 x 32-bit Banked Register File with negative-edge write and dual read ports.
//=============================================================================
`timescale 1ns / 1ps

module register_file (
    input  wire        clk,
    input  wire        rst,
    input  wire [3:0]  src1,
    input  wire [3:0]  src2,
    input  wire [3:0]  dest_wb,
    input  wire [31:0] result_wb,
    input  wire        write_back_en,
    input  wire        irq_mode,
    input  wire        irq_save_lr,
    input  wire [31:0] irq_return_addr,
    output wire [31:0] reg1,
    output wire [31:0] reg2,
    output wire [31:0] irq_lr
);
    reg [31:0] rf [15:0];
    reg [31:0] irq_sp, irq_lr_reg;
    integer i;

    // Asynchronous dual read
    assign reg1 = irq_mode && src1 == 13 ? irq_sp :
                  irq_mode && src1 == 14 ? irq_lr_reg : rf[src1];
    assign reg2 = irq_mode && src2 == 13 ? irq_sp :
                  irq_mode && src2 == 14 ? irq_lr_reg : rf[src2];
    assign irq_lr = irq_lr_reg;

    // Synchronous write on negative clock edge to avoid RAW hazards across half-cycles
    always @(negedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1)
                rf[i] <= i;
            irq_sp <= 32'd13;
            irq_lr_reg <= 32'd14;
        end else begin
            if (irq_save_lr)
                irq_lr_reg <= irq_return_addr;
            else if (write_back_en && irq_mode && dest_wb == 14)
                irq_lr_reg <= result_wb;

            if (write_back_en && irq_mode && dest_wb == 13)
                irq_sp <= result_wb;
            else if (write_back_en && !(irq_mode && dest_wb == 14))
                rf[dest_wb] <= result_wb;
        end
    end
endmodule
