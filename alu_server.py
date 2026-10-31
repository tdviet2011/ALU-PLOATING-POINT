#!/usr/bin/env python3
"""
Local web server for the floating point ALU demo (standard library only).

  python alu_server.py            # then open http://127.0.0.1:8000/
  python alu_server.py --open     # also opens the browser

The page in docs/ sends operand/opcode cases to /api/run; this server writes them to a
vector file, runs the Verilog testbench tb_run.v with Vivado xsim (or Icarus Verilog as a
fallback) and returns the ALU outputs. The RTL under test is the ./*.v files
(ADD_SUB, ALU, Division, Floating_Point_to_Integer, Iteration, Multiplication,
priority_encoder). The server only listens on 127.0.0.1.
"""
import argparse, glob, json, os, re, shutil, subprocess, sys, tempfile, threading, time, webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DOCS = ROOT / "docs"
BUILD = ROOT / "sim_build"
TB = ROOT / "tb_run.v"
RTL_NAMES = ["ADD_SUB.v", "ALU.v", "Division.v", "Floating_Point_to_Integer.v",
             "Iteration.v", "Multiplication.v", "priority_encoder.v"]
VARIANTS = {"rtl": ROOT}
MAX_CASES = 150000
LOCK = threading.Lock()
IS_WIN = os.name == "nt"


# ---------------------------------------------------------------- tool discovery
def which_tool(name):
    for cand in ([name + ".bat", name + ".exe", name] if IS_WIN else [name]):
        p = shutil.which(cand)
        if p:
            return p
    return None


def find_vivado_bin(explicit=None):
    """Return the Vivado bin directory (folder holding xvlog/xelab/xsim) or None."""
    cands = []
    if explicit:
        cands.append(Path(explicit))
    for var in ("VIVADO_BIN", "XILINX_VIVADO"):
        v = os.environ.get(var)
        if v:
            cands += [Path(v), Path(v) / "bin"]
    p = which_tool("xvlog")
    if p:
        cands.append(Path(p).parent)
    if IS_WIN:
        for base in ("C:/Xilinx/Vivado", "D:/Xilinx/Vivado", "C:/AMD/Vivado", "D:/AMD/Vivado", "E:/Xilinx/Vivado"):
            cands += [Path(x) / "bin" for x in sorted(glob.glob(base + "/*"), reverse=True)]
    else:
        for base in ("/tools/Xilinx/Vivado", "/opt/Xilinx/Vivado", "/opt/xilinx/Vivado"):
            cands += [Path(x) / "bin" for x in sorted(glob.glob(base + "/*"), reverse=True)]
    for c in cands:
        if any((c / (t + ext)).exists() for t in ("xvlog",) for ext in (".bat", ".exe", "")):
            return c
    return None


def tool_in(bindir, name):
    for ext in ((".bat", ".exe", "") if IS_WIN else ("",)):
        p = Path(bindir) / (name + ext)
        if p.exists():
            return str(p)
    return name


class Engine:
    def __init__(self, preference, vivado_bin):
        self.vivado_bin = find_vivado_bin(vivado_bin) if preference in ("auto", "vivado") else None
        self.iverilog = which_tool("iverilog") if preference in ("auto", "iverilog") else None
        self.vvp = which_tool("vvp") if self.iverilog else None
        if self.vivado_bin:
            self.name = "vivado"
        elif self.iverilog and self.vvp:
            self.name = "iverilog"
        else:
            self.name = None
        self.built = {}  # variant -> stamp used for the build

    def info(self):
        return {"engine": self.name, "vivado": str(self.vivado_bin) if self.vivado_bin else None,
                "iverilog": self.iverilog,
                "variants": {k: all((d / n).exists() for n in RTL_NAMES) for k, d in VARIANTS.items()}}

    # -- build -----------------------------------------------------------
    def sources(self, variant):
        return [VARIANTS[variant] / n for n in RTL_NAMES] + [TB]

    def stamp(self, variant):
        return max(p.stat().st_mtime for p in self.sources(variant))

    def run_cmd(self, cmd, cwd):
        r = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True, errors="replace", timeout=300)
        return r.returncode, (r.stdout or "") + (r.stderr or "")

    def build(self, variant):
        d = BUILD / (self.name + "_" + variant)
        d.mkdir(parents=True, exist_ok=True)
        st = self.stamp(variant)
        if self.built.get(variant) == st:
            return d
        files = [str(p) for p in self.sources(variant)]
        if self.name == "vivado":
            xvlog, xelab = tool_in(self.vivado_bin, "xvlog"), tool_in(self.vivado_bin, "xelab")
            rc, out = self.run_cmd([xvlog] + files, d)
            if rc != 0:
                raise RuntimeError("xvlog failed:\n" + out[-3000:])
            rc, out = self.run_cmd([xelab, "--timescale", "1ns/1ps", "-debug", "off", "work.tb_run", "-s", "snap"], d)
            if rc != 0:
                raise RuntimeError("xelab failed:\n" + out[-3000:])
        else:
            rc, out = self.run_cmd([self.iverilog, "-g2005", "-o", "snap.vvp"] + files, d)
            if rc != 0:
                raise RuntimeError("iverilog failed:\n" + out[-3000:])
        self.built[variant] = st
        return d

    # -- run -------------------------------------------------------------
    def run(self, variant, cases):
        if self.name is None:
            raise RuntimeError("No simulator found. Install Vivado (xvlog/xelab/xsim) or Icarus Verilog, "
                               "or pass --vivado-bin <path to Vivado bin>.")
        with LOCK:
            t0 = time.time()
            d = self.build(variant)
            fd, vec = tempfile.mkstemp(suffix=".hex", dir=str(d))
            with os.fdopen(fd, "w") as f:
                for op, sub, a, b in cases:
                    f.write("%08x\n%08x\n%08x\n" % (a, b, (op << 1) | sub))
            try:
                vecp = Path(vec).as_posix()
                if self.name == "vivado":
                    cmd = [tool_in(self.vivado_bin, "xsim"), "snap", "-runall", "-nolog", "-testplusarg", "VEC=" + vecp]
                else:
                    cmd = [self.vvp, "-n", "snap.vvp", "+VEC=" + vecp]
                rc, out = self.run_cmd(cmd, d)
            finally:
                try:
                    os.remove(vec)
                except OSError:
                    pass
            results = [None] * len(cases)
            for m in re.finditer(r"^RES (\d+) (\S+) ([01xXzZ]{3})\s*$", out, re.M):
                i, h, fl = int(m.group(1)), m.group(2), m.group(3)
                if i < len(results):
                    val = None if re.search(r"[xXzZ]", h) else int(h, 16)
                    results[i] = [val, [c == "1" for c in fl]]
            if any(r is None for r in results):
                raise RuntimeError("Simulation produced no result for every case (%s):\n%s" % (self.name, out[-2000:]))
            return {"engine": self.name, "variant": variant, "seconds": round(time.time() - t0, 2), "results": results}


# ---------------------------------------------------------------- HTTP
ENGINE = None


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=str(DOCS), **k)

    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _local_only(self):
        host = (self.headers.get("Host") or "").split(":")[0]
        origin = self.headers.get("Origin")
        if host not in ("127.0.0.1", "localhost"):
            return False
        if origin and re.sub(r"^https?://", "", origin).split(":")[0] not in ("127.0.0.1", "localhost"):
            return False
        return True

    def do_GET(self):
        if self.path.split("?")[0] == "/api/status":
            return self._json(200, ENGINE.info()) if self._local_only() else self._json(403, {"error": "forbidden"})
        return super().do_GET()

    def do_POST(self):
        if self.path != "/api/run":
            return self._json(404, {"error": "not found"})
        if not self._local_only():
            return self._json(403, {"error": "forbidden"})
        try:
            n = int(self.headers.get("Content-Length", "0"))
            if n <= 0 or n > 20_000_000:
                raise ValueError("bad body size")
            req = json.loads(self.rfile.read(n))
            variant = req.get("variant", "rtl")
            if variant not in VARIANTS:
                raise ValueError("unknown variant")
            cases = []
            for c in req["cases"]:
                op, sub, a, b = (int(x) for x in c)
                if not (0 <= op < 16 and sub in (0, 1) and 0 <= a < 2**32 and 0 <= b < 2**32):
                    raise ValueError("case out of range")
                cases.append((op, sub, a, b))
            if not cases or len(cases) > MAX_CASES:
                raise ValueError("need 1..%d cases" % MAX_CASES)
        except (ValueError, KeyError, TypeError, json.JSONDecodeError) as e:
            return self._json(400, {"error": "bad request: %s" % e})
        try:
            self._json(200, ENGINE.run(variant, cases))
        except Exception as e:  # report simulator problems to the page
            self._json(500, {"error": str(e)})


def main():
    global ENGINE
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8000)
    ap.add_argument("--sim", choices=["auto", "vivado", "iverilog"], default="auto")
    ap.add_argument("--vivado-bin", help=r"Vivado bin folder, e.g. C:\Xilinx\Vivado\2023.2\bin")
    ap.add_argument("--open", action="store_true", help="open the browser")
    args = ap.parse_args()
    ENGINE = Engine(args.sim, args.vivado_bin)
    print("Simulator:", ENGINE.name or "NONE (JS model only)", "|", json.dumps(ENGINE.info()))
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = "http://127.0.0.1:%d/" % args.port
    print("Serving", url, "- Ctrl+C to stop")
    if args.open:
        threading.Timer(0.8, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
