`timescale 1ns / 1ps

module cpu (
    input  wire       clk,
    input  wire       reset,
    input  wire [7:0] mem_data,
    output wire [7:0] mem_addr,

    input  wire [3:0] port0_in,
    output wire [3:0] port0_out,
    input  wire [3:0] port1_in,
    output wire [3:0] port1_out,

    output wire [3:0] r0,
    output wire [3:0] r1,
    output wire [7:0] pc,
    output wire [7:0] ir,
    output wire       c,
    output wire       v,
    output wire       halted
);

localparam [1:0] STATE_FETCH   = 2'd0;
localparam [1:0] STATE_EXECUTE = 2'd1;
localparam [1:0] STATE_HALT    = 2'd2;

localparam [2:0] R0_SEL_HOLD = 3'd0;
localparam [2:0] R0_SEL_ALU  = 3'd1;
localparam [2:0] R0_SEL_IMM  = 3'd2;
localparam [2:0] R0_SEL_R1   = 3'd3;
localparam [2:0] R0_SEL_PORT = 3'd4;

localparam [1:0] R1_SEL_HOLD = 2'd0;
localparam [1:0] R1_SEL_ALU  = 2'd1;
localparam [1:0] R1_SEL_IMM  = 2'd2;
localparam [1:0] R1_SEL_R0   = 2'd3;

reg [1:0] state_reg;
reg [7:0] pc_reg;
reg [7:0] ir_reg;
reg [3:0] r0_reg;
reg [3:0] r1_reg;
reg       c_reg;
reg       v_reg;
reg       halted_reg;
reg [3:0] port0_out_reg;
reg [3:0] port1_out_reg;

wire [3:0] opcode;
wire [3:0] operand;
wire [2:0] decoded_r0_sel;
wire       decoded_r0_load;
wire [1:0] decoded_r1_sel;
wire       decoded_r1_load;
wire [2:0] decoded_alu_op;
wire       decoded_alu_enable;
wire       decoded_flags_write;
wire       decoded_branch_unconditional;
wire       decoded_branch_on_c;
wire       decoded_branch_on_v;
wire       decoded_io_read;
wire       decoded_io_write;
wire       decoded_io_valid;
wire       decoded_io_port;
wire       decoded_halt;

wire [3:0] alu_result;
wire       alu_carry;
wire       alu_overflow;
wire       branch_taken;
reg  [3:0] r0_data;
reg  [3:0] r1_data;

assign mem_addr = pc_reg;
assign port0_out = port0_out_reg;
assign port1_out = port1_out_reg;
assign r0 = r0_reg;
assign r1 = r1_reg;
assign pc = pc_reg;
assign ir = ir_reg;
assign c = c_reg;
assign v = v_reg;
assign halted = halted_reg;

assign opcode = ir_reg[7:4];
assign operand = ir_reg[3:0];

assign branch_taken = decoded_branch_unconditional ||
                      (decoded_branch_on_c && c_reg) ||
                      (decoded_branch_on_v && v_reg);

always @* begin
    r0_data = r0_reg;
    case (decoded_r0_sel)
        R0_SEL_ALU:  r0_data = alu_result;
        R0_SEL_IMM:  r0_data = operand;
        R0_SEL_R1:   r0_data = r1_reg;
        R0_SEL_PORT: r0_data = decoded_io_port ? port1_in : port0_in;
        default:     r0_data = r0_reg;
    endcase

    r1_data = r1_reg;
    case (decoded_r1_sel)
        R1_SEL_ALU: r1_data = alu_result;
        R1_SEL_IMM: r1_data = operand;
        R1_SEL_R0:  r1_data = r0_reg;
        default:    r1_data = r1_reg;
    endcase
end

alu u_alu (
    .a        (r0_reg),
    .b        (r1_reg),
    .op       (decoded_alu_op),
    .result   (alu_result),
    .carry    (alu_carry),
    .overflow (alu_overflow)
);

decoder u_decoder (
    .opcode               (opcode),
    .operand              (operand),
    .r0_sel               (decoded_r0_sel),
    .r0_load              (decoded_r0_load),
    .r1_sel               (decoded_r1_sel),
    .r1_load              (decoded_r1_load),
    .alu_op               (decoded_alu_op),
    .alu_enable           (decoded_alu_enable),
    .flags_write          (decoded_flags_write),
    .branch_unconditional (decoded_branch_unconditional),
    .branch_on_c          (decoded_branch_on_c),
    .branch_on_v          (decoded_branch_on_v),
    .io_read              (decoded_io_read),
    .io_write             (decoded_io_write),
    .io_valid             (decoded_io_valid),
    .io_port              (decoded_io_port),
    .halt                 (decoded_halt)
);

always @(posedge clk or posedge reset) begin
    if (reset) begin
        state_reg       <= STATE_FETCH;
        pc_reg          <= 8'd0;
        ir_reg          <= 8'd0;
        r0_reg          <= 4'd0;
        r1_reg          <= 4'd0;
        c_reg           <= 1'b0;
        v_reg           <= 1'b0;
        halted_reg      <= 1'b0;
        port0_out_reg   <= 4'd0;
        port1_out_reg   <= 4'd0;
    end else begin
        case (state_reg)
            STATE_FETCH: begin
                ir_reg  <= mem_data;
                pc_reg  <= pc_reg + 8'd1;
                state_reg <= STATE_EXECUTE;
            end

            STATE_EXECUTE: begin
                if (decoded_halt) begin
                    halted_reg <= 1'b1;
                    state_reg  <= STATE_HALT;
                end else begin
                    if (decoded_r0_load) begin
                        r0_reg <= r0_data;
                    end
                    if (decoded_r1_load) begin
                        r1_reg <= r1_data;
                    end
                    if (decoded_flags_write) begin
                        c_reg <= alu_carry;
                        v_reg <= alu_overflow;
                    end
                    if (decoded_io_write && decoded_io_valid) begin
                        if (decoded_io_port) begin
                            port1_out_reg <= r0_reg;
                        end else begin
                            port0_out_reg <= r0_reg;
                        end
                    end
                    if (branch_taken) begin
                        pc_reg <= pc_reg + {{4{ir_reg[3]}}, ir_reg[3:0]};
                    end
                    state_reg <= STATE_FETCH;
                end
            end

            STATE_HALT: begin
                // Hold all architectural state until reset.
            end

            default: begin
                state_reg <= STATE_FETCH;
            end
        endcase
    end
end

endmodule
