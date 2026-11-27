import argparse
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "sim" / "build" / "uart"


def run(*args):
    print("+", subprocess.list2cmdline([str(arg) for arg in args]), flush=True)
    subprocess.run([str(arg) for arg in args], cwd=BUILD, check=True)


def wsl_path(path):
    result = subprocess.run(
        ["wsl", "--exec", "wslpath", "-u", str(path)],
        check=True, capture_output=True, text=True,
    )
    return result.stdout.strip()


def check_questa_log(path):
    log = path.read_text(encoding="utf-8", errors="replace")
    if re.search(r"(?m)^\s*#?\s*\*\*\s*(?:Fatal|Error):", log):
        raise RuntimeError(f"Questa reported a simulation error; see {path}")
    if "PASS: ARM C firmware transmitted" not in log:
        raise RuntimeError(f"Questa did not report a passing UART test; see {path}")


def main():
    parser = argparse.ArgumentParser(description="Build and simulate the ARM UART C example")
    parser.add_argument("--simulator", choices=("questa", "verilator"), default="questa")
    parser.add_argument("--arm-bin", type=Path, default=Path(r"C:\Keil_v5\ARM\ARMCC\bin"))
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)

    run(args.arm_bin / "armcc.exe", "--cpu", "4T", "--arm", "-O2", "-c",
        ROOT / "sim" / "firmware" / "uart.c", "-o", "uart.o")
    run(args.arm_bin / "armlink.exe", "--scatter", ROOT / "sim" / "firmware" / "uart.sct",
        "--entry", "uart_start", "--map", "--list", "uart.map", "uart.o", "-o", "uart.axf")
    run(args.arm_bin / "fromelf.exe", "--bin", "--output", "uart.bin", "uart.axf")
    image = (BUILD / "uart.bin").read_bytes()
    if not image or len(image) > 4096 or len(image) % 4:
        raise ValueError("Firmware image must contain 1 to 1024 complete 32-bit instructions")
    words = [f"{int.from_bytes(image[i:i + 4], 'little'):032b}" for i in range(0, len(image), 4)]
    (BUILD / "uart_program.hex").write_text("\n".join(words) + "\n", encoding="ascii")

    sources = sorted((ROOT / "rtl").glob("*.v"))
    sources.extend([ROOT / "tb" / "instruction_memory.v", ROOT / "tb" / "tb_uart_c.v"])
    if args.simulator == "questa":
        if not (BUILD / "modelsim.ini").exists():
            run("vmap", "-c")
        if not (BUILD / "work").exists():
            run("vlib", "work")
        run("vmap", "work", "work")
        run("vlog", "-work", "work", *sources)
        run("vsim", "-c", "work.tb_uart_c", "-l", "uart-transcript.log", "-do",
            "onbreak {quit -code 1}; onerror {quit -code 1}; run -all; quit -f")
        check_questa_log(BUILD / "uart-transcript.log")
    else:
        run("wsl", "--cd", BUILD, "--exec", "verilator", "--binary", "--timing",
            "-Wno-fatal", "--top-module", "tb_uart_c", "--Mdir", wsl_path(BUILD / "obj_dir"),
            *(wsl_path(path) for path in sources))
        run("wsl", "--cd", BUILD, "--exec", wsl_path(BUILD / "obj_dir" / "Vtb_uart_c"))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"UART build or simulation failed: {exc}", file=sys.stderr)
        sys.exit(1)
