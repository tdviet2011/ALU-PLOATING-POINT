# 32-bit Floating Point ALU (IEEE 754) – Verilog

ALU số thực dấu phẩy động 32 bit (single precision) viết bằng Verilog, gồm cộng, trừ, nhân, chia (Newton-Raphson), chuyển float sang phần nguyên và các phép logic/dịch bit. Toàn bộ thiết kế là **mạch tổ hợp** (không có clock, reset hay FSM).

Phần lõi cộng/trừ/nhân/chia dựa trên *Design of 32 Bit Floating Point ALU Based on Standard IEEE-754 in Verilog* (S. S. Burada, Dayalbagh Educational Institute, 2019).

## 1. Định dạng IEEE 754 single precision

```
 31   30        23 22                      0
+---+------------+-------------------------+
| S |  E (8 bit) |       M (23 bit)        |
+---+------------+-------------------------+
x = (-1)^S * 1.M * 2^(E-127)      (1 <= E <= 254)
E = 0   : 0 / subnormal           E = 255 : Inf (M=0) / NaN (M!=0)
```

## 2. Sơ đồ khối tổng thể

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

    subgraph ALU["ALU.v (module top)"]
        ADD["Addition_Subtraction<br/>ADD_SUB.v"]
        MUL["Multiplication<br/>Multiplication.v"]
        DIV["Division<br/>Division.v"]
        F2I["Floating_Point_to_Integer<br/>Floating_Point_to_Integer.v"]
        LOGIC["OR / AND / XOR<br/>SHL / SHR / NOT"]
        MUX{{"case(Operation)<br/>MUX 12 phép toán"}}
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

### Bảng opcode

| Operation | Phép toán | Ghi chú |
| --- | --- | --- |
| 0 | Cộng/Trừ | `AddBar_Sub` = 0 cộng, = 1 trừ |
| 1 | Nhân | Có cờ Overflow/Underflow |
| 2 | Chia | Newton-Raphson |
| 3 | Trừ | Dùng chung mạch Addition_Subtraction |
| 4 / 5 / 6 | OR / AND / XOR | Bitwise trên 32 bit |
| 7 / 8 | Dịch trái / phải 1 bit | |
| 9 | Float → Integer (trunc) | Cắt phần lẻ, giữ định dạng float |
| 10 | Cộng | Dùng chung mạch Addition_Subtraction |
| 11 | NOT | |
| 12–15 | – | Ra 0 |

## 3. Phân cấp module

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
    I1 --> IM1["Multiplication x2 + Addition_Subtraction"]
```

## 4. Đường đi dữ liệu từng thuật toán

### 4.1 Cộng / Trừ (`ADD_SUB.v`, `priority_encoder.v`)

```mermaid
flowchart TD
    IN["a, b"] --> SWAP["So sánh |a| và |b|<br/>đổi chỗ để |a| >= |b|"]
    SWAP --> SGN["Dấu kết quả và loại phép<br/>cộng/trừ hiệu dụng"]
    SWAP --> HID["Thêm bit ẩn 1<br/>(E=0 thì bit ẩn 0)"]
    HID --> DIFF["d = Ea - Eb"]
    DIFF --> SHIFT["Dịch phải mantissa b đi d bit"]
    SHIFT --> OP{"Cộng hiệu dụng?"}
    OP -->|Cộng| SUM["Mantissa a + b (25 bit)"]
    OP -->|Trừ| COMP["Bù 2 của b rồi cộng a"]
    SUM --> CARRY{"Có carry bit 24?"}
    CARRY -->|Có| NORM1["Dịch phải 1 bit, E + 1"]
    CARRY -->|Không| NORM2["Giữ nguyên, E của a"]
    COMP --> PE["Priority encoder:<br/>đếm số 0 đầu = k"]
    PE --> NORM3["Dịch trái k bit, E - k"]
    NORM1 --> OUT["Ghép {sign, E, M}"]
    NORM2 --> OUT
    NORM3 --> OUT
    OUT --> RES["result<br/>(Exception nếu E = 255 → 0)"]
```

### 4.2 Nhân (`Multiplication.v`)

```mermaid
flowchart TD
    IN["a, b"] --> S["sign = Sa XOR Sb"]
    IN --> HID["Thêm bit ẩn: 1.Ma, 1.Mb (24 bit)"]
    IN --> EXP["exp = Ea + Eb - 127"]
    HID --> MULT["Nhân 24 x 24 = 48 bit"]
    MULT --> NRM{"Bit 47 = 1?"}
    NRM -->|Có| N1["Giữ nguyên, exp + 1"]
    NRM -->|Không| N2["Dịch trái 1 bit"]
    N1 --> RND["Làm tròn:<br/>guard = bit 23, sticky = OR bit 22:0"]
    N2 --> RND
    RND --> CHK{"exp[8:7]"}
    EXP --> CHK
    CHK -->|"01"| OVF["Overflow"]
    CHK -->|"11"| UNF["Underflow"]
    CHK -->|"00"| PACK["Ghép {sign, exp[7:0], mantissa}"]
    S --> PACK
```

### 4.3 Chia – Newton-Raphson (`Division.v`, `Iteration.v`)

```mermaid
flowchart TD
    IN["a, b"] --> SPC{"NaN / Inf / 0?"}
    SPC -->|Có| SPCOUT["Trả NaN / Inf / 0 theo bảng đặc biệt"]
    SPC -->|Không| SCALE["Đưa mẫu số về D in [0.5, 1):<br/>mũ = 126, bù mũ vào tử số"]
    SCALE --> X0["X0 = 48/17 - 32/17 * D<br/>(Multiplication + Addition_Subtraction)"]
    X0 --> I1["Iteration 1: X1 = X0 * (2 - D * X0)"]
    I1 --> I2["Iteration 2: X2 = X1 * (2 - D * X1)"]
    I2 --> I3["Iteration 3: X3 = X2 * (2 - D * X2)"]
    I3 --> FIN["a_scaled * X3 ≈ a / b<br/>(Multiplication END)"]
    FIN --> RES["result = {sign, solution[30:0]}"]
```

Mỗi vòng `Iteration` gồm 2 phép nhân và 1 phép trừ float: `X(n+1) = X(n) * (2 - D * X(n))`. Sai số bình phương sau mỗi vòng (hội tụ bậc 2).

### 4.4 Float → Integer (`Floating_Point_to_Integer.v`)

```mermaid
flowchart TD
    IN["a_operand"] --> E{"Mũ E"}
    E -->|"E <= 126 (|x| < 1)"| Z["Xóa toàn bộ mantissa"]
    E -->|"127 <= E <= 149"| MASK["n = E - 127<br/>mask giữ n bit cao của M"]
    E -->|"E >= 150"| KEEP["Giữ nguyên mantissa<br/>(đã là số nguyên)"]
    Z --> PACK["Ghép {sign, E, mantissa mới}"]
    MASK --> PACK
    KEEP --> PACK
```

## 5. Mô phỏng

- Công cụ: Icarus Verilog / ModelSim / Vivado Simulator.
- Testbench tự kiểm tra: `tb_ALU.v` (top = `tb_ALU`). Cuối mô phỏng in `TONG: N case, DUNG=…, SAI=…`.
- Script sinh testbench: `gentb.py` (kết quả chuẩn tính bằng float32 của Python, làm tròn về gần nhất).

## 6. Hạn chế đã biết

- Cộng/trừ cắt bỏ (không làm tròn), nên có thể lệch 1 ULP; chưa có bit guard/round/sticky.
- Chia bằng Newton-Raphson 3 vòng nên sai số còn 2–4 ULP; chưa có cờ Overflow/Underflow cho chia.
- Chưa hỗ trợ subnormal; Inf/NaN ở đầu vào của cộng/trừ/nhân cho kết quả 0.
- Opcode 9 chỉ cắt phần lẻ, vẫn ở dạng float.
