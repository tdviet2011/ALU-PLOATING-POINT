`timescale 1ns / 1ps

module Division(
	input [31:0] a_operand,
	input [31:0] b_operand,
	output Exception,
	output [31:0] result
    );
wire sign;
wire [7:0] shift;
wire [7:0] exponent_a;
wire [31:0] divisor;
wire [31:0] operand_a;
wire [31:0] Intermediate_X0;
wire [31:0] Iteration_X0;
wire [31:0] Iteration_X1;
wire [31:0] Iteration_X2;
wire [31:0] Iteration_X3;
wire [31:0] solution;
;
wire [31:0] operand_a_change;

wire a_inf,b_inf,a_nan,b_nan;

assign a_inf =
    (a_operand[30:23]==8'hFF) &&
    (a_operand[22:0]==0);

assign b_inf =
    (b_operand[30:23]==8'hFF) &&
    (b_operand[22:0]==0);

assign a_nan =
    (a_operand[30:23]==8'hFF) &&
    (a_operand[22:0]!=0);

assign b_nan =
    (b_operand[30:23]==8'hFF) &&
    (b_operand[22:0]!=0);

wire a_zero;
wire b_zero;

assign a_zero = (a_operand[30:0] == 31'd0);
assign b_zero = (b_operand[30:0] == 31'd0);

assign Exception = (&a_operand[30:23]) | (&b_operand[30:23]);
assign sign = a_operand[31] ^ b_operand[31];
assign shift = 8'd126 - b_operand[30:23];
assign divisor = {1'b0,8'd126,b_operand[22:0]};


assign exponent_a = a_operand[30:23] + shift;

assign operand_a = {a_operand[31],exponent_a,a_operand[22:0]};
//32'hC00B_4B4B = (-37)/17
Multiplication x0(32'hC00B4B4B,divisor,,,,Intermediate_X0);
Addition_Subtraction X0(32'h4034_B4B5,Intermediate_X0,1'b0,,Iteration_X0);
Iteration X1(Iteration_X0,divisor,Iteration_X1);
Iteration X2(Iteration_X1,divisor,Iteration_X2);
Iteration X3(Iteration_X2,divisor,Iteration_X3);
Multiplication END(Iteration_X3,operand_a,,,,solution);
assign result =
    // NaN
    (a_nan || b_nan)
        ? 32'h7FC00000 :
    // 0/0 = NaN
    (a_zero && b_zero)
        ? 32'h7FC00000 :
    // Inf/Inf = NaN
    (a_inf && b_inf)
        ? 32'h7FC00000 :
    // Inf/x = Inf
    a_inf
        ? {sign,8'hFF,23'd0} :
    // x/Inf = 0
    b_inf
        ? {sign,31'd0} :

    // x/0 = Inf
    b_zero
        ? {sign,8'hFF,23'd0} :
	// 0/x = 0
    a_zero
        ? {sign,31'd0} :

    // Newton-Raphson
    {sign,solution[30:0]};
endmodule
