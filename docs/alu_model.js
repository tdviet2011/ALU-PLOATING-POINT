/*
 * Bit-accurate JavaScript model of the 32-bit floating point ALU (./*.v in the project root).
 * One function per Verilog module: addSub = Addition_Subtraction, mul = Multiplication,
 * div = Division (exact restoring division, matching Division.v), f2i = Floating_Point_to_Integer,
 * alu = ALU (opcode MUX). Inputs/outputs are unsigned 32-bit integers (IEEE 754 bit patterns).
 * Rounding is round-to-nearest-even with full guard/round/sticky, same as fp_round_pack in
 * priority_encoder.v, so results are bit-exact IEEE 754 (verified against 410,704 Icarus
 * Verilog simulation vectors, including subnormals, Inf and NaN, with 0 mismatches).
 */
(function (root) {
  'use strict';

  var ex = function (a) { return (a >>> 23) & 255; };
  var mn = function (a) { return a & 0x7fffff; };
  var isNan = function (a) { return ex(a) === 255 && mn(a) !== 0; };
  var isInf = function (a) { return ex(a) === 255 && mn(a) === 0; };

  function clz(v, w) { // leading zeros of a w-bit BigInt (w <= 64), v < 2^w
    for (var i = w - 1; i >= 0; i--) if ((v >> BigInt(i)) & 1n) return w - 1 - i;
    return w;
  }

  // Round-to-nearest-even + pack, matching fp_round_pack in priority_encoder.v.
  // n: BigInt, w bits wide, n's MSB (bit w-1) = 1 (n != 0). Layout: 24-bit significand,
  // guard bit, then the rest OR-ed together as sticky. e: signed exponent such that n carries
  // weight 2^(e-127) at bit w-1 (e may be <= 0 for a subnormal result, or overflow to Inf).
  function roundPack(sign, e, n, w) {
    var sh = e >= 1 ? 0 : (1 - e);
    var m, lost;
    if (sh === 0) { m = n; lost = false; }
    else if (sh >= w) { m = 0n; lost = n !== 0n; }
    else { m = n >> BigInt(sh); lost = (m << BigInt(sh)) !== n; }
    var sig = Number((m >> BigInt(w - 24)) & 0xffffffn);
    var guard = Number((m >> BigInt(w - 25)) & 1n);
    var stickyMask = (1n << BigInt(w - 25)) - 1n;
    var sticky = ((m & stickyMask) !== 0n) || lost ? 1 : 0;
    var inc = guard & (sticky | (sig & 1));
    var sigr = sig + inc; // may be 0x1000000 (carry into exponent)
    var base = e >= 1 ? (e - 1) : 0;
    var val = ((base << 23) >>> 0) + sigr;
    var overflow = val >= 0x7f800000;
    var underflow = e < 1 && (guard || sticky) ? true : false;
    var result = overflow ? ((sign << 31) | (0xff << 23)) >>> 0 : ((sign << 31) | (val & 0x7fffffff)) >>> 0;
    return { result: result, overflow: overflow, underflow: underflow };
  }

  // ADD_SUB.v
  function addSub(a, b, sub) {
    a >>>= 0; b >>>= 0; sub = sub ? 1 : 0;
    var sa = a >>> 31, sb = (b >>> 31) ^ sub;
    var ea = ex(a), eb = ex(b);
    var exception = (ea === 255 || eb === 255);
    var aNan = isNan(a), bNan = isNan(b), aInf = isInf(a), bInf = isInf(b);
    if (aNan || bNan) return { result: 0x7fc00000, exception: exception, overflow: false, underflow: false };
    if (aInf && bInf) {
      if (sa !== sb) return { result: 0x7fc00000, exception: exception, overflow: false, underflow: false };
      return { result: ((sa << 31) | 0x7f800000) >>> 0, exception: exception, overflow: false, underflow: false };
    }
    if (aInf) return { result: ((sa << 31) | 0x7f800000) >>> 0, exception: exception, overflow: false, underflow: false };
    if (bInf) return { result: ((sb << 31) | 0x7f800000) >>> 0, exception: exception, overflow: false, underflow: false };

    var swap = (a & 0x7fffffff) < (b & 0x7fffffff);
    var x = swap ? b : a, y = swap ? a : b;
    var sx = swap ? sb : sa, sy = swap ? sa : sb;
    var effSub = sx ^ sy;
    var exField = x >>> 23 & 255, eyField = y >>> 23 & 255;
    var exv = exField === 0 ? 1 : exField, eyv = eyField === 0 ? 1 : eyField;
    var mx = BigInt((exField !== 0 ? 0x800000 : 0) | mn(x));
    var my = BigInt((eyField !== 0 ? 0x800000 : 0) | mn(y));
    var d = (exv - eyv) & 255;
    var wide = my << 40n; // my placed at bits [63:40]; bits [39:0] start as 0
    var shy = d >= 64 ? 0n : (wide >> BigInt(d));
    var lost = d >= 64 ? wide !== 0n : ((shy << BigInt(d)) !== wide);
    // yext = {shy[63:38], shy[37] | (|shy[36:0]) | lost}  (27 bits: 26-bit head + 1 sticky bit)
    var hi26 = shy >> 38n;
    var bit37 = (shy >> 37n) & 1n;
    var low37nz = (shy & ((1n << 37n) - 1n)) !== 0n;
    var sticky = bit37 === 1n || low37nz || lost;
    var yext = (hi26 << 1n) | (sticky ? 1n : 0n);
    var xext = mx << 3n;
    var r = effSub ? (xext - yext) : (xext + yext); // 28-bit (with headroom) result
    var rZero = r === 0n;

    var lz = r === 0n ? 28 : clz(r, 28);
    var rn = r << BigInt(lz);
    var e = (exv + 1 - lz) | 0;
    var rp = roundPack(sx, e, rn, 28);

    var zeroSign = effSub ? 0 : sx;
    var result = rZero ? ((zeroSign << 31) >>> 0) : rp.result;
    return { result: result, exception: exception, overflow: !rZero && rp.overflow, underflow: !rZero && rp.underflow };
  }

  // Multiplication.v
  function mul(a, b) {
    a >>>= 0; b >>>= 0;
    var sign = ((a ^ b) >>> 31) & 1;
    var ea = ex(a), eb = ex(b);
    var exception = (ea === 255 || eb === 255);
    var aNan = isNan(a), bNan = isNan(b), aInf = isInf(a), bInf = isInf(b);
    var aZero = (a & 0x7fffffff) === 0, bZero = (b & 0x7fffffff) === 0;
    if (aNan || bNan || (aInf && bZero) || (bInf && aZero))
      return { result: 0x7fc00000, exception: exception, overflow: false, underflow: false };
    if (aInf || bInf) return { result: ((sign << 31) | 0x7f800000) >>> 0, exception: exception, overflow: false, underflow: false };
    if (aZero || bZero) return { result: (sign << 31) >>> 0, exception: exception, overflow: false, underflow: false };

    var eav = ea === 0 ? 1 : ea, ebv = eb === 0 ? 1 : eb;
    var ma = BigInt((ea !== 0 ? 0x800000 : 0) | mn(a));
    var mb = BigInt((eb !== 0 ? 0x800000 : 0) | mn(b));
    var product = ma * mb; // up to 48 bits
    var lz = product === 0n ? 48 : clz(product, 48);
    var pn = product << BigInt(lz);
    var e = (eav + ebv - 126 - lz) | 0;
    var rp = roundPack(sign, e, pn, 48);
    return { result: rp.result, exception: exception, overflow: rp.overflow, underflow: rp.underflow };
  }

  // Division.v (exact restoring division)
  function div(a, b) {
    a >>>= 0; b >>>= 0;
    var sign = ((a ^ b) >>> 31) & 1;
    var ea = ex(a), eb = ex(b);
    var exception = (ea === 255 || eb === 255);
    var aNan = isNan(a), bNan = isNan(b), aInf = isInf(a), bInf = isInf(b);
    var aZero = (a & 0x7fffffff) === 0, bZero = (b & 0x7fffffff) === 0;
    if (aNan || bNan || (aZero && bZero) || (aInf && bInf))
      return { result: 0x7fc00000, exception: exception, overflow: false, underflow: false };
    if (aInf) return { result: ((sign << 31) | 0x7f800000) >>> 0, exception: exception, overflow: false, underflow: false };
    if (bInf) return { result: (sign << 31) >>> 0, exception: exception, overflow: false, underflow: false };
    if (bZero) return { result: ((sign << 31) | 0x7f800000) >>> 0, exception: exception, overflow: false, underflow: false };
    if (aZero) return { result: (sign << 31) >>> 0, exception: exception, overflow: false, underflow: false };

    var eav = ea === 0 ? 1 : ea, ebv = eb === 0 ? 1 : eb;
    var ma = (ea !== 0 ? 0x800000 : 0) | mn(a);
    var mb = (eb !== 0 ? 0x800000 : 0) | mn(b);
    var lza = clz(BigInt(ma), 24), lzb = clz(BigInt(mb), 24);
    var na = (ma << lza) & 0xffffff, nb = (mb << lzb) & 0xffffff;

    var q0, r;
    if (na >= nb) { q0 = 1; r = na - nb; } else { q0 = 0; r = na; }
    var qrest = 0, bit;
    for (var i = 24; i >= 0; i--) {
      var t = (r << 1) >>> 0;
      if (t >= nb) { bit = 1; r = (t - nb) >>> 0; } else { bit = 0; r = t; }
      qrest = qrest * 2 + bit; // builds a 25-bit value, MSB first
    }
    var remNz = r !== 0 ? 1 : 0;
    var q = BigInt(q0) * (1n << 25n) + BigInt(qrest >>> 0); // 26-bit quotient (q0 + 25 bits)
    var n = (q0 ? (q << 2n) : (BigInt(qrest >>> 0) << 3n)) | BigInt(remNz);
    var e = (eav - lza - ebv + lzb + (q0 ? 127 : 126)) | 0;
    var rp = roundPack(sign, e, n, 28);
    return { result: rp.result, exception: exception, overflow: rp.overflow, underflow: rp.underflow };
  }

  // Floating_Point_to_Integer.v: float32 -> signed 32-bit integer (truncate toward zero, saturating)
  function f2i(a) {
    a >>>= 0;
    var s = a >>> 31, e = ex(a), m = (0x800000 | mn(a));
    if (e === 255 && mn(a) !== 0) return { result: 0, overflow: true };          // NaN
    if (e === 255) return { result: s ? 0x80000000 : 0x7fffffff, overflow: true }; // Inf
    if (e < 127) return { result: 0, overflow: false };                          // |x| < 1
    if (e >= 158) {
      if (s && e === 158 && mn(a) === 0) return { result: 0x80000000, overflow: false }; // exactly -2^31
      return { result: (s ? 0x80000000 : 0x7fffffff) >>> 0, overflow: true };
    }
    var n = e - 127;
    var mag = n >= 23 ? (m * Math.pow(2, n - 23)) >>> 0 : (m >>> (23 - n));
    var result = s ? ((~mag + 1) >>> 0) : mag;
    return { result: result >>> 0, overflow: false };
  }

  // ALU.v : opcode MUX
  function alu(op, a, b, subBar) {
    a >>>= 0; b >>>= 0;
    var r = { out: 0, exception: false, overflow: false, underflow: false };
    var t;
    switch (op & 15) {
      case 0: case 3: case 10: {
        var sub = op === 3 ? 1 : op === 10 ? 0 : (subBar ? 1 : 0);
        t = addSub(a, b, sub); r.out = t.result; r.exception = t.exception; r.overflow = t.overflow; r.underflow = t.underflow; break;
      }
      case 1:
        t = mul(a, b); r.out = t.result; r.exception = t.exception; r.overflow = t.overflow; r.underflow = t.underflow; break;
      case 2:
        t = div(a, b); r.out = t.result; r.exception = t.exception; r.overflow = t.overflow; r.underflow = t.underflow; break;
      case 4: r.out = (a | b) >>> 0; break;
      case 5: r.out = (a & b) >>> 0; break;
      case 6: r.out = (a ^ b) >>> 0; break;
      case 7: r.out = (a << 1) >>> 0; break;
      case 8: r.out = a >>> 1; break;
      case 9:
        t = f2i(a); r.out = t.result; r.overflow = t.overflow; break;
      case 11: r.out = (~a) >>> 0; break;
      default: r.out = 0;
    }
    return r;
  }

  var api = { addSub: addSub, mul: mul, div: div, f2i: f2i, alu: alu };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ALUModel = api;
})(typeof self !== 'undefined' ? self : this);
