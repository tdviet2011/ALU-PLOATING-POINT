# 32-bit Floating Point ALU (IEEE 754) – Verilog

A single-precision (float32) floating point ALU written in Verilog: add, subtract, multiply, divide (Newton-Raphson), float-to-integer-part conversion, and bitwise/shift operations. The whole design is **combinational** (no clock, reset or FSM).

The add/subtract/multiply/divide core is based on *Design of 32 Bit Floating Point ALU Based on Standard IEEE-754 in Verilog* (S. S. Burada, Dayalbagh Educational Institute, 2019).

## Contents

| Path | Description |
| --- | --- |
| `*.v` | ALU RTL as originally written |
| `rtl_fixed/` | Corrected RTL (see [Known issues](#7-known-issues-and-fixes)) |
| `tb_ALU.v`, `gentb.py` | Self-checking testbench (4,109 cases) and the script that generates it |
| `docs/index.html`, `docs/alu_model.js` | Web demo: enter operands, run an operation, compare with the exact float32 result |

## 1. IEEE 754 single precision format

```
 31   30        23 22                      0
+---+------------+-------------------------+
| S |  E (8 bit) |       M (23 bit)        |
+---+------------+-------------------------+
x = (-1)^S * 1.M * 2^(E-127)      (1 <= E <= 254)
E = 0   : zero / subnormal        E = 255 : Inf (M = 0) / NaN (M != 0)
```

## 2. Top-level block diagram

```mermaid
flowchart LR
    A["a_operand [31:0]"] --> ADD
    B["b_operand [31:0]"] --> ADD
    SUB["AddBar_Sub"] --> ADD
    A --> MUL
    B --> MUL
    A --> DIV
    B --> DIV
    A --> F2I
    A --> LOGIC
    B --> LOGIC

    subgraph ALU["ALU.v (top module)"]
        ADD["Addition_Subtraction<br/>ADD_SUB.v"]
        MUL["Multiplication<br/>Multiplication.v"]
        DIV["Division<br/>Division.v"]
        F2I["Floating_Point_to_Integer<br/>Floating_Point_to_Integer.v"]
        LOGIC["OR / AND / XOR<br/>SHL / SHR / NOT"]
        MUX{{"case(Operation)<br/>12-way MUX"}}
    end

    ADD -->|"result, Exception"| MUX
    MUL -->|"result, Exception,<br/>Overflow, Underflow"| MUX
    DIV -->|"result, Exception"| MUX
    F2I -->|Integer_Value| MUX
    LOGIC --> MUX
    OP["Operation [3:0]"] --> MUX

    MUX --> Y["ALU_Output [31:0]"]
    MUX --> EX["Exception"]
    MUX --> OV["Overflow"]
    MUX --> UN["Underflow"]
```

### Opcode table

| Operation | Function | Notes |
| --- | --- | --- |
| 0 | Add / Subtract | `AddBar_Sub` = 0 adds, = 1 subtracts |
| 1 | Multiply | Drives Overflow/Underflow flags |
| 2 | Divide | Newton-Raphson |
| 3 | Subtract | Shares the Addition_Subtraction hardware |
| 4 / 5 / 6 | OR / AND / XOR | Bitwise on all 32 bits |
| 7 / 8 | Shift left / right by 1 | Logical shift |
| 9 | Float → integer part (trunc) | Drops the fraction, keeps float format |
| 10 | Add | Shares the Addition_Subtraction hardware |
| 11 | NOT | |
| 12–15 | – | Output 0 |

## 3. Module hierarchy

```mermaid
flowchart TD
    ALU --> AS1["Addition_Subtraction"]
    ALU --> M1["Multiplication"]
    ALU --> D1["Division"]
    ALU --> F1["Floating_Point_to_Integer"]
    AS1 --> PE1["priority_encoder"]
    D1 --> Mx0["Multiplication (X0)"]
    D1 --> AX0["Addition_Subtraction (X0)"]
    D1 --> I1["Iteration X1"]
    D1 --> I2["Iteration X2"]
    D1 --> I3["Iteration X3"]
    D1 --> MEND["Multiplication (END)"]
    I1 --> IM1["2x Multiplication + 1x Addition_Subtraction"]
```

## 4. Data path of each algorithm

### 4.1 Add / Subtract (`ADD_SUB.v`, `priority_encoder.v`)

```mermaid
flowchart TD
    IN["a, b"] --> SWAP["Compare |a| and |b|,<br/>swap so that |a| >= |b|"]
    SWAP --> SGN["Result sign and<br/>effective operation (add/sub)"]
    SWAP --> HID["Add hidden bit 1<br/>(hidden bit 0 when E = 0)"]
    HID --> DIFF["d = Ea - Eb"]
    DIFF --> SHIFT["Shift b's significand right by d"]
    SHIFT --> OP{"Effective add?"}
    OP -->|Add| SUM["Significand a + b (25 bit)"]
    OP -->|Subtract| COMP["Two's complement of b, then add a"]
    SUM --> CARRY{"Carry out (bit 24)?"}
    CARRY -->|Yes| NORM1["Shift right 1, E + 1"]
    CARRY -->|No| NORM2["Keep, exponent of a"]
    COMP --> PE["Priority encoder:<br/>count leading zeros = k"]
    PE --> NORM3["Shift left k, E - k"]
    NORM1 --> OUT["Pack {sign, E, M}"]
    NORM2 --> OUT
    NORM3 --> OUT
    OUT --> RES["result<br/>(Exception if E = 255 → 0)"]
```

### 4.2 Multiply (`Multiplication.v`)

```mermaid
flowchart TD
    IN["a, b"] --> S["sign = Sa XOR Sb"]
    IN --> HID["Add hidden bit: 1.Ma, 1.Mb (24 bit)"]
    IN --> EXP["exp = Ea + Eb - 127"]
    HID --> MULT["24 x 24 = 48-bit product"]
    MULT --> NRM{"Bit 47 = 1?"}
    NRM -->|Yes| N1["Keep, exp + 1"]
    NRM -->|No| N2["Shift left 1"]
    N1 --> RND["Round: guard = bit 23,<br/>sticky = OR of bits 22:0"]
    N2 --> RND
    RND --> CHK{"exp[8:7]"}
    EXP --> CHK
    CHK -->|"01"| OVF["Overflow"]
    CHK -->|"11"| UNF["Underflow"]
    CHK -->|"00"| PACK["Pack {sign, exp[7:0], mantissa}"]
    S --> PACK
```

### 4.3 Divide – Newton-Raphson (`Division.v`, `Iteration.v`)

```mermaid
flowchart TD
    IN["a, b"] --> SPC{"NaN / Inf / 0?"}
    SPC -->|Yes| SPCOUT["Return NaN / Inf / 0 from the special-case table"]
    SPC -->|No| SCALE["Scale divisor to D in [0.5, 1):<br/>exponent = 126, move the shift into a's exponent"]
    SCALE --> X0["X0 = 48/17 - 32/17 * D<br/>(Multiplication + Addition_Subtraction)"]
    X0 --> I1["Iteration 1: X1 = X0 * (2 - D * X0)"]
    I1 --> I2["Iteration 2: X2 = X1 * (2 - D * X1)"]
    I2 --> I3["Iteration 3: X3 = X2 * (2 - D * X2)"]
    I3 --> FIN["a_scaled * X3 ≈ a / b<br/>(Multiplication END)"]
    FIN --> RES["result = {sign, solution[30:0]}"]
```

Each `Iteration` is two float multiplications and one float subtraction: `X(n+1) = X(n) * (2 - D * X(n))`. The error squares at every step (quadratic convergence).

### 4.4 Float → integer part (`Floating_Point_to_Integer.v`)

```mermaid
flowchart TD
    IN["a_operand"] --> E{"Exponent E"}
    E -->|"E <= 126 (absolute value below 1)"| Z["Clear the whole mantissa"]
    E -->|"127 <= E <= 149"| MASK["n = E - 127<br/>mask keeps the top n bits of M"]
    E -->|"E >= 150"| KEEP["Keep mantissa<br/>(already an integer)"]
    Z --> PACK["Pack {sign, E, new mantissa}"]
    MASK --> PACK
    KEEP --> PACK
```

## 5. Web demo

Open `docs/index.html` in a browser (double-click, no server needed). Enter operands as decimal numbers, `inf`, `nan` or hex bit patterns, choose an operation, and the page shows:

- the ALU output (hex, bit fields, decimal) and the Exception / Overflow / Underflow flags;
- the float32 reference (round-to-nearest) and the exact 64-bit value;
- absolute error, relative error, error in ULP and a verdict (bit-exact / within 1 ULP / small error / mismatch);
- a preset test suite and a 5,000-sample random accuracy test per operation.

The page runs `docs/alu_model.js`, a bit-accurate JavaScript port of the corrected RTL. It was checked against 182,304 Icarus Verilog simulation vectors (outputs and flags) with 0 mismatches. To publish it with GitHub Pages: *Settings → Pages → Deploy from a branch → `main` / `/docs`*.

## 6. Simulation and verification

- Tools: Icarus Verilog, ModelSim or Vivado Simulator.
- Self-checking testbench: `tb_ALU.v` (top = `tb_ALU`). It prints `TONG: N case, DUNG=…, SAI=…` (total / pass / fail) and lists each failing case. Add `rtl_fixed/*.v` and `tb_ALU.v` to the simulation sources.
- `gentb.py` regenerates the testbench; expected values come from Python float32 (round-to-nearest). Change the output path inside the script if you run it on your machine.

Measured accuracy of the corrected RTL against IEEE 754 float32 (normal inputs and results, 20,000 random pairs plus edge cases):

| Operation | Bit-exact | Within 1 ULP | Max ULP |
| --- | --- | --- | --- |
| Add | 69.6% | 99.3% | 8 |
| Subtract | 69.7% | 99.4% | 16 |
| Multiply | 100% | 100% | 0 |
| Divide | 28.1% | 68.2% | 4 |

## 7. Known issues and fixes

Fixes already in `rtl_fixed/`:

1. `Multiplication.v`: missing `assign result` and `endmodule`, duplicated assignments (the original does not compile).
2. `Multiplication.v`: the `zero` flag was derived from the result mantissa, so every power of two (e.g. 1.0 × 1.0) returned 0; it now tests the operands.
3. `Division.v`: Newton-Raphson seed constant changed from −37/17 (`C00B4B4B`) to −32/17 (`BFF0F0F1`).
4. `Multiplication.v`: round-to-nearest-even with the rounding carry propagated into the exponent.
5. `ADD_SUB.v`: 25-bit two's complement (exponent difference ≥ 24 no longer corrupts the result) and x − x returns 0.

Still open:

- Add/Subtract truncate instead of rounding (no guard/round/sticky bits), so results can be 1 ULP off.
- Divide error is 2–4 ULP because the internal adders truncate; no Overflow/Underflow flag for divide.
- Subnormal numbers are not supported; Inf/NaN inputs to add, subtract and multiply return 0.
- Opcodes 3 and 10 do not force `AddBar_Sub`, so they behave like opcode 0.
- Opcode 9 only clears the fraction bits (the result stays in float format, and |x| < 1 keeps the exponent).
