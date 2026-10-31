/*
 * Bit-accurate JavaScript model of the 32-bit floating point ALU (corrected RTL in ../rtl_fixed).
 * One function per Verilog module: addSub = Addition_Subtraction (+ priority_encoder),
 * mul = Multiplication, div = Division (+ Iteration), f2i = Floating_Point_to_Integer,
 * alu = ALU (opcode MUX). Inputs/outputs are unsigned 32-bit integers (IEEE 754 bit patterns).
 */
(function (root) {
  'use strict';

  var ex = function (a) { return (a >>> 23) & 255; };
  var mn = function (a) { return a & 0x7fffff; };

  // priority_encoder.v: normalise a 25-bit difference, returns new significand and exponent
  function priority(v, ea) {
    var sig, shift;
    if (v === 0) { sig = 0; shift = 24; }
    else if ((v >>> 24) & 1) {
      var k = 0;
      while (k < 24 && !((v >>> (23 - k)) & 1)) k++;
      if (k === 24) { sig = 0; shift = 24; }
      else { sig = (v << k) & 0x1ffffff; shift = k; }
    } else { sig = ((~v) + 1) & 0x1ffffff; shift = 0; }
    return { sig: sig, exp: (ea - shift) & 255 };
  }

  // ADD_SUB.v
  function addSub(a, b, sub) {
    a >>>= 0; b >>>= 0; sub = sub ? 1 : 0;
    var aLess = (a & 0x7fffffff) < (b & 0x7fffffff);
    var opa = aLess ? b : a, opb = aLess ? a : b;
    var comp = aLess ? 1 : 0;
    var ea = ex(opa), eb = ex(opb);
    var exception = (ea === 255 || eb === 255);
    var sa = opa >>> 31, sb = opb >>> 31;
    var osign = sub ? (comp ? sa ^ 1 : sa) : sa;
    var opAdd = sub ? (sa ^ sb) : ((sa ^ sb) ^ 1);
    var siga = (ea ? 0x800000 : 0) | mn(opa);
    var sigb = (eb ? 0x800000 : 0) | mn(opb);
    var ed = (ea - eb) & 255;
    var sigbs = ed >= 24 ? 0 : (sigb >>> ed);
    var sigAdd = opAdd ? (siga + sigbs) : 0;
    var carry = (sigAdd >>> 24) & 1;
    var addMant = carry ? ((sigAdd >>> 1) & 0x7fffff) : (sigAdd & 0x7fffff);
    var addExp = carry ? ((ea + 1) & 255) : ea;
    var comp25 = opAdd ? 0 : ((0x1000000 - sigbs) & 0x1ffffff);
    var sigSub = (siga + comp25) & 0x1ffffff;
    var pe = priority(sigSub, ea);
    var subDiff = ((pe.exp & 255) << 23) | (pe.sig & 0x7fffff);
    var result;
    if (exception) result = 0;
    else if (!opAdd && (sigSub & 0xffffff) === 0 && ((sigSub >>> 24) & 1)) result = 0;
    else if (!opAdd) result = ((osign << 31) | subDiff) >>> 0;
    else result = ((osign << 31) | (addExp << 23) | addMant) >>> 0;
    return { result: result, exception: exception };
  }

  // Multiplication.v
  function mul(a, b) {
    a >>>= 0; b >>>= 0;
    var sign = ((a ^ b) >>> 31) & 1;
    var ea = ex(a), eb = ex(b);
    var exception = (ea === 255 || eb === 255);
    var A = BigInt((ea ? 0x800000 : 0) | mn(a));
    var B = BigInt((eb ? 0x800000 : 0) | mn(b));
    var product = A * B;
    var normalised = Number((product >> 47n) & 1n);
    var pn = normalised ? product : ((product << 1n) & 0xffffffffffffn);
    var round = (pn & 0x7fffffn) !== 0n ? 1 : 0;
    var g = Number((pn >> 23n) & 1n);
    var top = Number((pn >> 24n) & 0x7fffffn);
    var lsb = top & 1;
    var mantRnd = top + (g & (round | lsb));
    var rcarry = (mantRnd >>> 23) & 1;
    var mant = mantRnd & 0x7fffff;
    var zero = exception ? 0 : (((a & 0x7fffffff) === 0) || ((b & 0x7fffffff) === 0)) ? 1 : 0;
    var expo = (ea + eb - 127 + normalised + rcarry) & 0x1ff;
    var b8 = (expo >>> 8) & 1, b7 = (expo >>> 7) & 1;
    var overflow = !!(b8 && !b7 && !zero);
    var underflow = !!(b8 && b7 && !zero);
    var result;
    if (exception) result = 0;
    else if (zero) result = (sign << 31) >>> 0;
    else if (overflow) result = ((sign << 31) | (0xff << 23)) >>> 0;
    else if (underflow) result = (sign << 31) >>> 0;
    else result = ((sign << 31) | ((expo & 255) << 23) | mant) >>> 0;
    return { result: result, exception: exception, overflow: overflow, underflow: underflow };
  }

  // Iteration.v : x * (2 - x*d)
  function iteration(x, d) {
    var m1 = mul(x, d).result;
    var t = addSub(0x40000000, m1, 1).result;
    return mul(x, t).result;
  }

  // Division.v (Newton-Raphson, 3 iterations)
  function div(a, b) {
    a >>>= 0; b >>>= 0;
    var sa = a >>> 31, sb = b >>> 31, sign = sa ^ sb;
    var ea = ex(a), eb = ex(b);
    var aInf = ea === 255 && mn(a) === 0, bInf = eb === 255 && mn(b) === 0;
    var aNan = ea === 255 && mn(a) !== 0, bNan = eb === 255 && mn(b) !== 0;
    var aZero = (a & 0x7fffffff) === 0, bZero = (b & 0x7fffffff) === 0;
    var exception = (ea === 255 || eb === 255);
    var shift = (126 - eb) & 255;
    var divisor = ((126 << 23) | mn(b)) >>> 0;
    var expA = (ea + shift) & 255;
    var opA = ((sa << 31) | (expA << 23) | mn(a)) >>> 0;
    var m0 = mul(0xBFF0F0F1, divisor).result;
    var x0 = addSub(0x4034B4B5, m0, 0).result;
    var x1 = iteration(x0, divisor);
    var x2 = iteration(x1, divisor);
    var x3 = iteration(x2, divisor);
    var solution = mul(x3, opA).result;
    var result;
    if (aNan || bNan) result = 0x7fc00000;
    else if (aZero && bZero) result = 0x7fc00000;
    else if (aInf && bInf) result = 0x7fc00000;
    else if (aInf) result = ((sign << 31) | 0x7f800000) >>> 0;
    else if (bInf) result = (sign << 31) >>> 0;
    else if (bZero) result = ((sign << 31) | 0x7f800000) >>> 0;
    else if (aZero) result = (sign << 31) >>> 0;
    else result = ((sign << 31) | (solution & 0x7fffffff)) >>> 0;
    return { result: result, exception: exception };
  }

  // Floating_Point_to_Integer.v (truncate fraction, keep float format)
  function f2i(a) {
    a >>>= 0;
    var e = ex(a), frac;
    if (e <= 126) frac = 0;
    else if (e >= 150) frac = mn(a);
    else {
      var n = e - 127;
      var mask = (0x7fffff << (23 - n)) & 0x7fffff;
      frac = mn(a) & mask;
    }
    return (((a >>> 31) << 31) | (e << 23) | frac) >>> 0;
  }

  // ALU.v : opcode MUX
  function alu(op, a, b, subBar) {
    a >>>= 0; b >>>= 0;
    var r = { out: 0, exception: false, overflow: false, underflow: false };
    var t;
    switch (op & 15) {
      case 0: case 3: case 10:
        t = addSub(a, b, subBar); r.out = t.result; r.exception = t.exception; break;
      case 1:
        t = mul(a, b); r.out = t.result; r.exception = t.exception; r.overflow = t.overflow; r.underflow = t.underflow; break;
      case 2:
        t = div(a, b); r.out = t.result; r.exception = t.exception; break;
      case 4: r.out = (a | b) >>> 0; break;
      case 5: r.out = (a & b) >>> 0; break;
      case 6: r.out = (a ^ b) >>> 0; break;
      case 7: r.out = (a << 1) >>> 0; break;
      case 8: r.out = a >>> 1; break;
      case 9: r.out = f2i(a); break;
      case 11: r.out = (~a) >>> 0; break;
      default: r.out = 0;
    }
    return r;
  }

  var api = { addSub: addSub, mul: mul, div: div, f2i: f2i, alu: alu };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ALUModel = api;
})(typeof self !== 'undefined' ? self : this);
