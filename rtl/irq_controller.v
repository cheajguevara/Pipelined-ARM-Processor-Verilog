`timescale 1ns / 1ps

// Level-sensitive interrupt concentrator. The SoC must decode the register
// window and pass only accesses to this peripheral to the Wishbone interface.
module irq_controller (
    input wire clk,
    input wire rst,
    input wire [9:0] sources,
    output wire irq,

    input wire wb_cyc,
    input wire wb_stb,
    input wire wb_we,
    input wire [3:0] wb_addr,
    input wire [31:0] wb_wdata,
    input wire [3:0] wb_sel,
    output reg wb_ack,
    output reg wb_err,
    output wire wb_stall,
    output reg [31:0] wb_rdata
);
    reg [9:0] enable;
    wire [9:0] pending = sources & enable;
    reg [3:0] priority_index;
    integer i;

    assign irq = |pending;
    assign wb_stall = 1'b0;

    always @(*) begin
        priority_index = 4'hf;
        for (i = 9; i >= 0; i = i - 1)
            if (pending[i])
                priority_index = i[3:0];
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            enable <= 10'd0;
            wb_ack <= 1'b0;
            wb_err <= 1'b0;
            wb_rdata <= 32'd0;
        end else begin
            wb_ack <= wb_cyc && wb_stb && wb_addr[1:0] == 0;
            wb_err <= wb_cyc && wb_stb && wb_addr[1:0] != 0;
            if (wb_cyc && wb_stb && wb_addr[1:0] == 0) begin
                if (wb_we && wb_addr == 4'h0) begin
                    if (wb_sel[0]) enable[7:0] <= wb_wdata[7:0];
                    if (wb_sel[1]) enable[9:8] <= wb_wdata[9:8];
                end
                case (wb_addr)
                    4'h0: wb_rdata <= {22'd0, enable};
                    4'h4: wb_rdata <= {22'd0, pending};
                    4'h8: wb_rdata <= {27'd0, irq, priority_index};
                    4'hc: wb_rdata <= {22'd0, sources};
                    default: wb_rdata <= 32'd0;
                endcase
            end
        end
    end
endmodule
