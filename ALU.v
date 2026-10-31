`timescale 1ns / 1ps
//==============================================================================
// ALU.v  -  32-bit floating point ALU (top module), purely combinational
//
//  Operation | Function
//  ----------+--------------------------------------------------------------
//     0      | float add / subtract, selected by AddBar_Sub (0: a+b, 1: a-b)
//     1      | float multiply
//     2      | float divide
//     3      | float subtract  (forces a-b, AddBar_Sub is ignored)
//     4,5,6  | bitwise OR, AND, XOR
//     7, 8   | logical shift left / right of a by 1 bit
//     9      | float -> signed 32-bit integer (truncate toward zero, saturating)
//    10      | float add       (forces a+b, AddBar_Sub is ignored)
//    11      | bitwise NOT of a
//   12..15   | output 0
//
//  Flags: Exception = an operand is Inf/NaN (float ops 0-3, 10);
//         Overflow  = result rounds to Inf (float ops) or the integer saturated
//                     (op 9, also NaN/Inf input); Underflow = subnormal and inexact.
//
// Fixes against the original
//   - Operations 3 and 10 did not set the add/subtract control, so 'subtract'
//     and 'add' simply followed the AddBar_Sub pin like operation 0.
//   - Overflow/Underflow were reported only for multiply; add, subtract and
//     divide now report them too, and operation 9 reports saturation.
//   - The "Output Registers" are plain combinational wires (no clock/latch).
//==============================================================================
module ALU(
    input  [31:0] a_operand,
    input  [31:0] b_operand,
    input  [3:0]  Operation,
    input         AddBar_Sub,
    output [31:0] ALU_Output,
    output        Exception,
    output        Overflow,
    output        Underflow
);
    //------------------------------------------------------------------ units
    // one adder serves operations 0, 3 and 10; ops 3 and 10 override the pin
    wire sub_sel = (Operation == 4'd3)  ? 1'b1 :
                   (Operation == 4'd10) ? 1'b0 : AddBar_Sub;

    wire [31:0] Add_Sub_Output, Mul_Output, Div_Output, Integer_Value;
    wire        Add_Sub_Exception, Add_Sub_Overflow, Add_Sub_Underflow;
    wire        Mul_Exception,     Mul_Overflow,     Mul_Underflow;
    wire        Div_Exception,     Div_Overflow,     Div_Underflow;
    wire        Int_Overflow;

    Addition_Subtraction AU1 (
        .a_operand(a_operand), .b_operand(b_operand), .AddBar_Sub(sub_sel),
        .Exception(Add_Sub_Exception), .result(Add_Sub_Output),
        .Overflow(Add_Sub_Overflow), .Underflow(Add_Sub_Underflow));

    Multiplication MU1 (
        .a_operand(a_operand), .b_operand(b_operand),
        .Exception(Mul_Exception), .Overflow(Mul_Overflow),
        .Underflow(Mul_Underflow), .result(Mul_Output));

    Division DU1 (
        .a_operand(a_operand), .b_operand(b_operand),
        .Exception(Div_Exception), .result(Div_Output),
        .Overflow(Div_Overflow), .Underflow(Div_Underflow));

    Floating_Point_to_Integer FU1 (
        .a_operand(a_operand), .Integer_1(Integer_Value), .Overflow(Int_Overflow));

    //------------------------------------------------------------- result MUX
    reg [31:0] ALU_Output_reg;       // 'reg' only because it is assigned in always @(*)
    reg        Exception_reg, Overflow_reg, Underflow_reg;

    always @(*) begin
        ALU_Output_reg = 32'd0;
        Exception_reg  = 1'b0;
        Overflow_reg   = 1'b0;
        Underflow_reg  = 1'b0;

        case (Operation)
            4'd0, 4'd3, 4'd10: begin                 // add / subtract
                ALU_Output_reg = Add_Sub_Output;
                Exception_reg  = Add_Sub_Exception;
                Overflow_reg   = Add_Sub_Overflow;
                Underflow_reg  = Add_Sub_Underflow;
            end
            4'd1: begin                              // multiply
                ALU_Output_reg = Mul_Output;
                Exception_reg  = Mul_Exception;
                Overflow_reg   = Mul_Overflow;
                Underflow_reg  = Mul_Underflow;
            end
            4'd2: begin                              // divide
                ALU_Output_reg = Div_Output;
                Exception_reg  = Div_Exception;
                Overflow_reg   = Div_Overflow;
                Underflow_reg  = Div_Underflow;
            end
            4'd4:  ALU_Output_reg = a_operand | b_operand;
            4'd5:  ALU_Output_reg = a_operand & b_operand;
            4'd6:  ALU_Output_reg = a_operand ^ b_operand;
            4'd7:  ALU_Output_reg = a_operand << 1;
            4'd8:  ALU_Output_reg = a_operand >> 1;
            4'd9: begin                              // float -> integer
                ALU_Output_reg = Integer_Value;
                Overflow_reg   = Int_Overflow;
            end
            4'd11: ALU_Output_reg = ~a_operand;
            default: ALU_Output_reg = 32'd0;
        endcase
    end

    assign ALU_Output = ALU_Output_reg;
    assign Exception  = Exception_reg;
    assign Overflow   = Overflow_reg;
    assign Underflow  = Underflow_reg;
endmodule
