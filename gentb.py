#!/usr/bin/env python3
"""
Generates tb_ALU.v, a self-checking Verilog testbench for the ALU (module ALU, ALU.v).

Expected values are computed with Python's own IEEE 754 binary32 arithmetic
(struct pack/unpack through 'f', i.e. the same bits as a real float32 unit),
so every add/sub/mul/div/trunc case is checked for a bit-exact match (the
current RTL is bit-exact against IEEE 754, see README.md "Simulation and
verification"). Edit CASES below and rerun to add more.
"""
import math, random, struct

OUT = "tb_ALU.v"
random.seed(7)


def f2h(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def h2f(h):
    return struct.unpack('<f', struct.pack('<I', h))[0]


def f32(x):
    try:
        return struct.unpack('<f', struct.pack('<f', x))[0]
    except OverflowError:
        return math.copysign(math.inf, x)


NAN = 0x7FC00000


def ref_addsub(a, b, sub):
    A, B = h2f(a), h2f(b)
    if math.isnan(A) or math.isnan(B):
        return NAN
    Bv = -B if sub else B
    if math.isinf(A) and math.isinf(Bv):
        return NAN if A != Bv else f2h(A)
    if math.isinf(A):
        return f2h(A)
    if math.isinf(Bv):
        return f2h(Bv)
    return f2h(f32(A - B if sub else A + B))


def ref_mul(a, b):
    A, B = h2f(a), h2f(b)
    if math.isnan(A) or math.isnan(B):
        return NAN
    if (math.isinf(A) and B == 0) or (math.isinf(B) and A == 0):
        return NAN
    return f2h(f32(A * B))


def ref_div(a, b):
    A, B = h2f(a), h2f(b)
    if math.isnan(A) or math.isnan(B):
        return NAN
    if (A == 0 and B == 0) or (math.isinf(A) and math.isinf(B)):
        return NAN
    if math.isinf(A):
        return f2h(math.copysign(math.inf, A) * math.copysign(1.0, B))
    if math.isinf(B) or B == 0:
        v = math.copysign(math.inf, A) * math.copysign(1.0, B) if B == 0 else math.copysign(0.0, A) * math.copysign(1.0, B)
        return f2h(v)
    if A == 0:
        return f2h(math.copysign(0.0, A) * math.copysign(1.0, B))
    return f2h(f32(A / B))


def ref_f2i(a):
    s, e, m = (a >> 31) & 1, (a >> 23) & 255, a & 0x7FFFFF
    if e == 255 and m != 0:            # NaN
        return 0
    A = h2f(a)
    if math.isinf(A):
        return 0x80000000 if s else 0x7FFFFFFF
    if abs(A) < 1:
        return 0
    t = math.trunc(A)
    if t == -2**31:
        return 0x80000000
    if t >= 2**31 or t < -2**31:
        return 0x80000000 if s else 0x7FFFFFFF
    return t & 0xFFFFFFFF


SPECIALS = [0x00000000, 0x80000000, 0x3F800000, 0xBF800000, 0x40000000, 0x3F000000,
            0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00001, 0x00000001, 0x80000001,
            0x007FFFFF, 0x00800000, 0x7F7FFFFF, 0xFF7FFFFF, 0x40490FDB, 0x4B000000,
            0x4F000000, 0xCF000000]

CASES = []  # (name, op, sub, a, b, expected)


def add(name, op, sub, a, b, exp):
    CASES.append((name, op, sub, a, b, exp))


# --- add/sub/mul/div, all pairs of special values, all control combos -------
CTRL = [(0, 0), (0, 1), (3, 0), (10, 1), (1, None), (2, None)]
for a in SPECIALS:
    for b in SPECIALS:
        for op, sub in CTRL:
            if op in (0, 3, 10):
                s = sub if op == 0 else (1 if op == 3 else 0)
                add('addsub_special', op, s, a, b, ref_addsub(a, b, s))
            elif op == 1:
                add('mul_special', op, 0, a, b, ref_mul(a, b))
            elif op == 2:
                add('div_special', op, 0, a, b, ref_div(a, b))

# --- random normal/subnormal operands ---------------------------------------
def rnd_bits():
    r = random.random()
    if r < 0.5:
        return f2h(random.uniform(-1, 1) * 10 ** random.uniform(-6, 6))
    if r < 0.8:
        return random.getrandbits(32)
    return (random.getrandbits(1) << 31) | random.getrandbits(23)  # subnormal

for _ in range(1500):
    a, b = rnd_bits(), rnd_bits()
    for op, sub in ((0, 0), (0, 1), (1, 0), (2, 0)):
        if op == 0:
            add('rand_addsub', op, sub, a, b, ref_addsub(a, b, sub))
        elif op == 1:
            add('rand_mul', op, 0, a, b, ref_mul(a, b))
        else:
            add('rand_div', op, 0, a, b, ref_div(a, b))

# --- float -> integer ---------------------------------------------------
for v in SPECIALS + [f2h(x) for x in (5.0, -5.0, 123.75, -123.75, 0.75, -0.75,
                                       2147483647.0, -2147483648.0, 3e9, -3e9,
                                       1.0, -1.0, 2**24 + 0.5)]:
    add('f2i', 9, 0, v, 0, ref_f2i(v))

# --- bitwise / shift / unused opcodes ---------------------------------------
for _ in range(50):
    a, b = random.getrandbits(32), random.getrandbits(32)
    add('or', 4, 0, a, b, a | b)
    add('and', 5, 0, a, b, a & b)
    add('xor', 6, 0, a, b, a ^ b)
    add('shl', 7, 0, a, 0, (a << 1) & 0xFFFFFFFF)
    add('shr', 8, 0, a, 0, a >> 1)
    add('not', 11, 0, a, 0, (~a) & 0xFFFFFFFF)
add('unused_opcode', 12, 0, 0x12345678, 0x9ABCDEF0, 0)

# ----------------------------------------------------------------- emit ----
lines = [
    '`timescale 1ns/1ps',
    '// Self-checking testbench for ALU.v. Generated by gentb.py -- do not edit by hand.',
    '// Expected values are bit-exact IEEE 754 (Python struct-based float32 arithmetic).',
    'module tb_ALU;',
    '  reg [31:0] a, b; reg [3:0] op; reg s;',
    '  wire [31:0] y; wire ex, ov, un;',
    '',
    '  ALU dut(.a_operand(a), .b_operand(b), .Operation(op), .AddBar_Sub(s),',
    '          .ALU_Output(y), .Exception(ex), .Overflow(ov), .Underflow(un));',
    '',
    '  integer pass = 0, fail = 0;',
    '  task chk; input [255:0] name; input [3:0] o; input sb; input [31:0] ia, ib, exp; begin',
    '    op = o; s = sb; a = ia; b = ib; #5;',
    '    if (y === exp) pass = pass + 1;',
    '    else begin',
    '      fail = fail + 1;',
    '      $display("FAIL %0s op=%0d sub=%0d a=%h b=%h got=%h exp=%h", name, o, sb, ia, ib, y, exp);',
    '    end',
    '  end endtask',
    '',
    '  initial begin',
]
for n, op, sub, a, b, exp in CASES:
    lines.append('    chk("%s", 4\'d%d, 1\'b%d, 32\'h%08x, 32\'h%08x, 32\'h%08x);' % (n, op, sub, a, b, exp))
lines += [
    '    $display("TONG: %0d case, DUNG=%0d, SAI=%0d", pass + fail, pass, fail);',
    '    $finish;',
    '  end',
    'endmodule',
]
open(OUT, 'w').write('\n'.join(lines) + '\n')
print('%s: %d cases' % (OUT, len(CASES)))
