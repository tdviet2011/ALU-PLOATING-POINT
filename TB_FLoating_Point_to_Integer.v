`timescale 1ns / 1ps

module TB_FLoating_Point_to_Integer;

	// Inputs
	reg [31:0] a_operand;

	// Outputs
	wire [31:0] Integer_1;

	// Instantiate the Unit Under Test (UUT)
	Floating_Point_to_Integer uut (
		.a_operand(a_operand), 
		.Integer_1(Integer_1)
	);

	initial begin
		// Test 1 : 3.0 -> 3
		a_operand = 32'h40400000;
		#100;

		// Test 2 : 2.5 -> 2
		a_operand = 32'h40200000;
		#100;

		// Test 3 : 7.75 -> 7
		a_operand = 32'h40F80000;
		#100;

		// Test 4 : 10.0 -> 10
		a_operand = 32'h41200000;
		#100;

		// Test 5 : -3.0 -> -3
		a_operand = 32'hC0400000;
		#100;

		// Test 6 : -2.5 -> -2
		a_operand = 32'hC0200000;
		#100;
		// Test 7 : 0.5 -> 0
		a_operand = 32'h3F000000;
		#100;

		// Test 8 : 0.25 -> 0
		a_operand = 32'h3E800000;
		#100;

		// Test 9 : 37.5 -> 37
		a_operand = 32'h42160000;
		#100;

		// Test 10 : -62.5 -> -62
		a_operand = 32'hC27A0000;
		#100;
	end
      
endmodule

