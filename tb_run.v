`timescale 1ns/1ps
// Batch testbench driven by alu_server.py.
// Usage: +VEC=<hex file>. The file holds 3 words per case: a, b, ctrl where ctrl = {Operation[3:0], AddBar_Sub}.
// Prints one line per case:  RES <index> <ALU_Output hex> <Exception><Overflow><Underflow>
module tb_run;
  reg [31:0] a, b;
  reg [3:0]  op;
  reg        s;
  wire [31:0] y;
  wire ex, ov, un;

  ALU dut(.a_operand(a), .b_operand(b), .Operation(op), .AddBar_Sub(s),
          .ALU_Output(y), .Exception(ex), .Overflow(ov), .Underflow(un));

  reg [31:0] mem [0:599999];
  reg [8*512:1] path;
  integer i;

  initial begin
    if (!$value$plusargs("VEC=%s", path)) begin
      $display("ERR no +VEC argument");
      $finish;
    end
    $readmemh(path, mem);
    i = 0;
    while (i < 200000 && mem[i*3] !== 32'hxxxxxxxx) begin
      a  = mem[i*3];
      b  = mem[i*3+1];
      op = mem[i*3+2][4:1];
      s  = mem[i*3+2][0];
      #1;
      $display("RES %0d %h %b%b%b", i, y, ex, ov, un);
      i = i + 1;
    end
    $display("DONE %0d", i);
    $finish;
  end
endmodule
