`timescale 1ns / 1ps

// Exercises the existing RISC-V SoC decoder, not a proposed replacement.
module tb_riscv_address_map;
    reg [31:0] addr = 0;
    wire [5:0] selected;
    wire ack;
    wire [31:0] data;

    memory_wrapper decoder (
        .i_wb_cyc(1'b1), .i_wb_stb(1'b1), .i_wb_we(1'b0),
        .i_wb_addr(addr), .i_wb_data(32'd0), .i_wb_sel(4'hf),
        .o_wb_ack(ack), .o_wb_stall(), .o_wb_data(data),

        .o_device0_wb_cyc(selected[0]), .o_device0_wb_stb(),
        .o_device0_wb_we(), .o_device0_wb_addr(), .o_device0_wb_data(), .o_device0_wb_sel(),
        .i_device0_wb_ack(1'b1), .i_device0_wb_stall(1'b0), .i_device0_wb_data(32'h0),
        .o_device1_wb_cyc(selected[1]), .o_device1_wb_stb(),
        .o_device1_wb_we(), .o_device1_wb_addr(), .o_device1_wb_data(), .o_device1_wb_sel(),
        .i_device1_wb_ack(1'b1), .i_device1_wb_stall(1'b0), .i_device1_wb_data(32'h1),
        .o_device2_wb_cyc(selected[2]), .o_device2_wb_stb(),
        .o_device2_wb_we(), .o_device2_wb_addr(), .o_device2_wb_data(), .o_device2_wb_sel(),
        .i_device2_wb_ack(1'b1), .i_device2_wb_stall(1'b0), .i_device2_wb_data(32'h2),
        .o_device3_wb_cyc(selected[3]), .o_device3_wb_stb(),
        .o_device3_wb_we(), .o_device3_wb_addr(), .o_device3_wb_data(), .o_device3_wb_sel(),
        .i_device3_wb_ack(1'b1), .i_device3_wb_stall(1'b0), .i_device3_wb_data(32'h3),
        .o_device4_wb_cyc(selected[4]), .o_device4_wb_stb(),
        .o_device4_wb_we(), .o_device4_wb_addr(), .o_device4_wb_data(), .o_device4_wb_sel(),
        .i_device4_wb_ack(1'b1), .i_device4_wb_stall(1'b0), .i_device4_wb_data(32'h4),
        .o_device5_wb_cyc(selected[5]), .o_device5_wb_stb(),
        .o_device5_wb_we(), .o_device5_wb_addr(), .o_device5_wb_data(), .o_device5_wb_sel(),
        .i_device5_wb_ack(1'b1), .i_device5_wb_stall(1'b0), .i_device5_wb_data(32'h5)
    );

    task check_address;
        input [31:0] address;
        input [5:0] expected;
        input expected_ack;
        input [31:0] expected_data;
        begin
            addr = address;
            #1;
            if (selected !== expected || ack !== expected_ack || data !== expected_data)
                $fatal(1, "Address %h: select=%b ack=%b data=%h",
                       address, selected, ack, data);
        end
    endtask

    initial begin
        check_address(32'h00000000, 6'b000001, 1, 0);
        check_address(32'h80000000, 6'b000010, 1, 1);
        check_address(32'h8000004f, 6'b000010, 1, 1);
        check_address(32'h80000050, 6'b000100, 1, 2);
        check_address(32'h8000009f, 6'b000100, 1, 2);
        check_address(32'h800000a0, 6'b001000, 1, 3);
        check_address(32'h800000ef, 6'b001000, 1, 3);
        check_address(32'h800000f0, 6'b010000, 1, 4);
        check_address(32'h8000013f, 6'b010000, 1, 4);
        check_address(32'h80000140, 6'b000000, 0, 0);
        check_address(32'h80000144, 6'b000000, 0, 0);
        check_address(32'h80000148, 6'b000000, 0, 0);
        check_address(32'h8000014c, 6'b000000, 0, 0);
        check_address(32'h8000014f, 6'b000000, 0, 0);
        check_address(32'hc0000140, 6'b100000, 1, 5);
        $display("PASS: RISC-V decoder ranges; candidate IRQ window is unmapped");
        $finish;
    end
endmodule
