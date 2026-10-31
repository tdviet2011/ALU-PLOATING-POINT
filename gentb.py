import struct,math,random
random.seed(7)
def f2h(x): return struct.unpack('<I',struct.pack('<f',x))[0]
def h2f(h): return struct.unpack('<f',struct.pack('<I',h))[0]
def f32(x):
    try: return struct.unpack('<f',struct.pack('<f',x))[0]
    except OverflowError: return math.copysign(math.inf,x)
cases=[]  # (name, op, sub, a, b, expected_hex, tol_ulp)
def add(name,op,s,a,b,exp,tol): cases.append((name,op,s,a,b,exp,tol))
vals=[1.0,-1.0,2.0,0.5,0.75,1.5,3.0,5.0,10.0,100.0,0.1,0.3333333,3.14159265,2.71828183,1e-3,1e3,1e6,1e-6,1e10,-7.25,123.456,-0.015625,65504.0,1.17549435e-38*4,3.0e38]
def cl(op,s,A,B):
    if op==0: return f32(A-B if s else A+B)
    if op==1: return f32(A*B)
    if op==2: return f32(A/B)
for A in vals:
  for B in vals:
    for s in(0,1):
        r=cl(0,s,A,B)
        if r!=0 and math.isfinite(r): add('add_sub',0,s,f2h(A),f2h(B),f2h(r),1)
    r=cl(1,0,A,B)
    if math.isfinite(r) and r!=0 and abs(r)>1.2e-38: add('mul',1,0,f2h(A),f2h(B),f2h(r),1)
    r=cl(2,0,A,B)
    if math.isfinite(r) and r!=0 and abs(r)>1.2e-38: add('div',2,0,f2h(A),f2h(B),f2h(r),4)
for i in range(400):  # random
    A=random.uniform(-1,1)*10**random.uniform(-4,4); B=random.uniform(-1,1)*10**random.uniform(-4,4)
    if B==0: continue
    for op,s,t in((0,0,1),(0,1,1),(1,0,1),(2,0,4)):
        r=cl(op,s,A,B)
        if math.isfinite(r) and r!=0 and abs(r)>1.2e-38 and abs(A)>1.2e-38 and abs(B)>1.2e-38:
            add('rand',op,s,f2h(A),f2h(B),f2h(r),t)
# exact-zero results
for A in(1.0,-2.5,100.0,0.1): add('x-x=0',0,1,f2h(A),f2h(A),0,0)
for A in(1.0,2.0,-3.5): add('x*0=0',1,0,f2h(A),0,0,0); add('0*x=0',1,0,0,f2h(A),0,0)
add('0/x=0',2,0,0,f2h(5.0),0,0); add('x/0=Inf',2,0,f2h(5.0),0,0x7f800000,0); add('0/0=NaN',2,0,0,0,0x7fc00000,0)
add('x/x=1',2,0,f2h(3.0),f2h(3.0),f2h(1.0),0)
add('Inf/Inf=NaN',2,0,0x7f800000,0x7f800000,0x7fc00000,0)
add('x/Inf=0',2,0,f2h(5.0),0x7f800000,0,0)
add('Inf/x=Inf',2,0,0x7f800000,f2h(5.0),0x7f800000,0)
for A in(5.0,-5.0,123.75,1e8,0.0): add('trunc',9,0,f2h(A),0,f2h(math.trunc(A)),0)
# bitwise ops
for op,fn,nm in((4,lambda a,b:a|b,'or'),(5,lambda a,b:a&b,'and'),(6,lambda a,b:a^b,'xor')):
    for _ in range(20):
        a,b=random.getrandbits(32),random.getrandbits(32); add(nm,op,0,a,b,fn(a,b),0)
for _ in range(10):
    a=random.getrandbits(32)
    add('shl',7,0,a,0,(a<<1)&0xffffffff,0); add('shr',8,0,a,0,a>>1,0); add('not',11,0,a,0,(~a)&0xffffffff,0)
add('op12_default',12,0,0x12345678,0x9abcdef0,0,0)
out=['`timescale 1ns/1ps','// Testbench tu kiem tra cho ALU float32. Sinh boi gentb.py; expected tinh bang float32 chuan (RNE).','// tol = sai so ULP cho phep. Khong dung $finish voi loi: in so case dung/sai.','module tb_ALU;','reg [31:0] a,b; reg [3:0] op; reg s; wire [31:0] y; wire ex,ov,un;',
'ALU dut(.a_operand(a),.b_operand(b),.Operation(op),.AddBar_Sub(s),.ALU_Output(y),.Exception(ex),.Overflow(ov),.Underflow(un));',
'integer pass=0, fail=0;',
'function integer ord; input [31:0] h; begin ord = h[31] ? -(h[30:0]) : h[30:0]; end endfunction',
'task chk; input [255:0] name; input [3:0] o; input sb; input [31:0] ia, ib, exp; input integer tol; integer d; begin',
'  op=o; s=sb; a=ia; b=ib; #5;',
'  d = ord(y) - ord(exp); if (d<0) d=-d;',
'  if (d<=tol && !((exp[30:23]==8\'hff) && (exp[22:0]!=0) && y!==exp)) pass=pass+1;',
'  else begin fail=fail+1; $display("FAIL %0s op=%0d sub=%0d a=%h b=%h got=%h exp=%h (ulp diff %0d)",name,o,sb,ia,ib,y,exp,d); end',
'end endtask',
'initial begin']
for n,op,s,a,b,e,t in cases:
    out.append('  chk("%s",4\'d%d,1\'b%d,32\'h%08x,32\'h%08x,32\'h%08x,%d);'%(n,op,s,a,b,e,t))
out+=['  $display("TONG: %0d case, DUNG=%0d, SAI=%0d",pass+fail,pass,fail);','  $finish;','end','endmodule']
open('/mnt/project-files/alu_fixed/tb_ALU.v','w').write('\n'.join(out)+'\n')
print(len(cases))
