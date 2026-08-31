`timescale 1ns / 10ps



module tb_Addition_Subtraction;

	// Inputs
	reg [31:0] a_operand;
	reg [31:0] b_operand;
	reg AddBar_Sub;

	// Outputs
	wire Exception;
	wire [31:0] result;

	// Instantiate the Unit Under Test (UUT)
	Addition_Subtraction uut (
		.a_operand(a_operand), 
		.b_operand(b_operand), 
		.AddBar_Sub(AddBar_Sub), 
		.Exception(Exception), 
		.result(result)
	);

	initial begin
		  // Test 1: 1.5 + (-2.5) = -1.0
a_operand = 32'h3FC00000;   // 1.5
b_operand = 32'hC0200000;   // -2.5
AddBar_Sub = 1'b0;
// Expected = BF800000 (-1.0) 
			#100;
// Test 2: -1.75 + (-2.25) = -4.0
a_operand = 32'hBFE00000;   // -1.75
b_operand = 32'hC0100000;   // -2.25
AddBar_Sub = 1'b0;
// Expected = C0800000 (-4.0)
		  #100;
// Test 3: -5.5 - (-2.5) = -3.0
a_operand = 32'hC0B00000;   // -5.5
b_operand = 32'hC0200000;   // -2.5
AddBar_Sub = 1'b1;
// Expected = C0400000 (-3.0)
		#100;
// Test 4: -2.5 - (-5.5) = 3.0
a_operand = 32'hC0200000;   // -2.5
b_operand = 32'hC0B00000;   // -5.5
AddBar_Sub = 1'b1;
// Expected = 40400000 (3.0) 
		#100;
// Test 5: 3.0 + (-3.0) = 0.0
a_operand = 32'h40400000;   // 3.0
b_operand = 32'hC0400000;   // -3.0
AddBar_Sub = 1'b0;
// Expected = 00000000 (+0.0)
		#100;

// Test 6: +Infinity + 1.0 = +Infinity
a_operand = 32'h7F800000;   // +Inf
b_operand = 32'h3F800000;   // 1.0
AddBar_Sub = 1'b0;
// Expected = 7F800000 (+Inf)
		#100;
// Test 7: +Infinity + (-Infinity) = NaN
a_operand = 32'h7F800000;
b_operand = 32'hFF800000;
AddBar_Sub = 1'b0;
// Expected = NaN (thường 7FC00000)
		#100;
		// Test 8: 1000.0 + 0.125 = 1000.125
a_operand = 32'h447A0000;   // 1000.0
b_operand = 32'h3E000000;   // 0.125
AddBar_Sub = 1'b0;
// Expected = 447A0800 (1000.125)
		#100;
// Test 9: 0.1 + 0.2 ≈ 0.3000000119
a_operand = 32'h3DCCCCCD;   // 0.1
b_operand = 32'h3E4CCCCD;   // 0.2
AddBar_Sub = 1'b0;
// Expected = 3E99999A (≈ 0.3000000119)
		#100;
// Test 10: -0.0 + 0.0 = +0.0
a_operand = 32'h80000000;
b_operand = 32'h00000000;
AddBar_Sub = 1'b0;
// Expected = 00000000
	end
endmodule

