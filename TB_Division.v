`timescale 1ns / 1ps

module TB_Division;

	// Inputs
	reg [31:0] a_operand;
	reg [31:0] b_operand;

	// Outputs
	wire Exception;
	wire [31:0] result;

	// Instantiate the Unit Under Test (UUT)
	Division uut (
		.a_operand(a_operand), 
		.b_operand(b_operand), 
		.Exception(Exception), 
		.result(result)
	);

	initial begin
// Test 1: 8.0 / 2.0 = 4.0
a_operand = 32'h41000000;
b_operand = 32'h40000000;
// Expected = 40800000
#100;
// Test 2: -6.0 / 3.0 = -2.0
a_operand = 32'hC0C00000;
b_operand = 32'h40400000;
// Expected = C0000000
#100;
// Test 3: -4.0 / -8.0 = 0.5
a_operand = 32'hC0800000;
b_operand = 32'hC1000000;
// Expected = 3F000000
#100;
// Test 4: 1.0 / 4.0 = 0.25
a_operand = 32'h3F800000;
b_operand = 32'h40800000;
// Expected = 3E800000
#100;
// Test 5: 37.5 / 12.5 = 3.0
a_operand = 32'h42160000;
b_operand = 32'h41480000;
// Expected = 40400000
#100;
// Test 6: -62.5 / 25.0 = -2.5
a_operand = 32'hC27A0000;
b_operand = 32'h41C80000;
// Expected = C0200000
#100;
// Test 7: 0.0 / 5.0 = 0.0
a_operand = 32'h00000000;
b_operand = 32'h40A00000;
// Expected = 00000000
#100;
// Test 8: -0.0 / 5.0 = -0.0
a_operand = 32'h80000000;
b_operand = 32'h40A00000;
// Expected = 80000000
#100;
// Test 9: 5.0 / 0.0 = +Infinity
a_operand = 32'h40A00000;
b_operand = 32'h00000000;
// Expected = 7F800000
#100;
// Test 10: 0.0 / 5.0 = 0.0
a_operand = 32'h00000000;
b_operand = 32'h40A00000;
// Expected = 00000000
#100;
// Test 11: -0.0 / 5.0 = -0.0
a_operand = 32'h80000000;
b_operand = 32'h40A00000;
// Expected = 80000000
#100;
// Test 12: 5.0 / 0.0 = +Infinity
a_operand = 32'h40A00000;
b_operand = 32'h00000000;
// Expected = 7F800000
#100;
// +Inf
a_operand = 32'h7F800000;
b_operand = 32'h40000000;
// Exception = 1
#100;
// -Inf
a_operand = 32'hFF800000;
b_operand = 32'h40000000;
// Exception = 1
#100;
// NaN
a_operand = 32'h7FC00000;
b_operand = 32'h40000000;
// Exception = 1
#100;
// NaN
a_operand = 32'h3F800000;
b_operand = 32'h7FC00000;
// Exception = 1
#100;
$finish;
	end
      
endmodule

