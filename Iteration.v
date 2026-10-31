`timescale 1ns / 1ps
//==============================================================================
// Iteration.v  -  one Newton-Raphson step  X(n+1) = X(n) * (2 - D * X(n))
//
// NOTE: no longer instantiated. Division.v now uses an exact restoring divider
// (see the header of Division.v for the reasons). This file is kept only so the
// existing Vivado project file list stays valid; it is safe to remove it from
// the project (Vivado: Sources -> right-click -> Remove File).
//==============================================================================
module Iteration(
    input  [31:0] operand_1,       // X(n)
    input  [31:0] operand_2,       // D
    output [31:0] solution         // X(n+1)
);
    wire [31:0] Intermediate_Value1, Intermediate_Value2;

    // D * X(n)
    Multiplication M1 (.a_operand(operand_1), .b_operand(operand_2),
                       .Exception(), .Overflow(), .Underflow(),
                       .result(Intermediate_Value1));

    // 2 - D * X(n)
    Addition_Subtraction A1 (.a_operand(32'h4000_0000), .b_operand(Intermediate_Value1),
                             .AddBar_Sub(1'b1), .Exception(),
                             .result(Intermediate_Value2), .Overflow(), .Underflow());

    // X(n) * (2 - D * X(n))
    Multiplication M2 (.a_operand(operand_1), .b_operand(Intermediate_Value2),
                       .Exception(), .Overflow(), .Underflow(),
                       .result(solution));
endmodule
