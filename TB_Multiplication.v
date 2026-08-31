`timescale 1ns / 1ps

module TB_Multiplication;

	// Inputs
	reg [31:0] a_operand;
	reg [31:0] b_operand;

	// Outputs
	wire Exception;
	wire Overflow;
	wire Underflow;
	wire [31:0] result;

	// Instantiate the Unit Under Test (UUT)
	Multiplication uut (
		.a_operand(a_operand), 
		.b_operand(b_operand), 
		.Exception(Exception), 
		.Overflow(Overflow), 
		.Underflow(Underflow), 
		.result(result)
	);
	
	initial begin
// Test 1: 2.0 * 3.0 = 6.0
a_operand = 32'h40000000;
b_operand = 32'h40400000;
// Expected = 40C00000 (6.0)
		#100;

// Test 2: -2.0 * 3.0 = -6.0
a_operand = 32'hC0000000;
b_operand = 32'h40400000;
// Expected = C0C00000 (-6.0)	
#100;
// Test 3: -2.5 * -4.0 = 10.0
a_operand = 32'hC0200000;
b_operand = 32'hC0800000;
// Expected = 41200000 (10.0)
#100;
// Test 4: 1.5 * 1.5 = 2.25
a_operand = 32'h3FC00000;
b_operand = 32'h3FC00000;
// Expected = 40100000 (2.25)
#100;
// Test 5: 0.5 * 0.25 = 0.125
a_operand = 32'h3F000000;
b_operand = 32'h3E800000;
// Expected = 3E000000 (0.125)
#100;
// Test 6: 100.0 * 0.01 = 1.0
a_operand = 32'h42C80000;
b_operand = 32'h3C23D70A;
// Expected ≈ 3F800000 (1.0)
#100;
// Test 7: 0.0 * 5.0 = 0.0
a_operand = 32'h00000000;
b_operand = 32'h40A00000;
// Expected = 00000000
#100;
// Test 8: +Infinity * 2.0 = +Infinity
a_operand = 32'h7F800000;
b_operand = 32'h40000000;
// Expected = 7F800000
#100;
// Test 9: +Infinity * 0.0 = NaN
a_operand = 32'h7F800000;
b_operand = 32'h00000000;
// Expected = 7FC00000 (NaN)
#100;
// Test 10: NaN * 3.0 = NaN
a_operand = 32'h7FC00000;
b_operand = 32'h40400000;
// Expected = 7FC00000 (NaN)
end
     
endmodule

