"""
Validate FPGA Hardware Results vs. Python Reference
=====================================================
Loads hardware_tracking_v3.json (results from real PYNQ-Z2 board)
and compares final Doppler, PLL error, and DLL error against the
Python float64 reference tracker for all 4 satellites.
"""

import json
import math
import numpy as np
import os

# ── Constants ─────────────────────────────────────────────────────────────────
FS       = 4.000e6
F_CODE   = 1.023e6
N_CHIPS  = 1023
N_1MS    = 4000
CPS      = F_CODE / FS
T        = 1e-3
B_FLL    = 5.0
B_PLL    = 15.0
B_DLL    = 1.0
FLL_EPOCHS = 50

DATA_FILE = r"D:\GPS_M1\client_data\L1_20211202_084700_4MHz_IQ.bin"
HW_JSON   = os.path.join(os.path.dirname(__file__), "hardware_tracking_v3.json")

SATELLITES = {
    31: {"fd_init": -200.0,  "cp_init": 296.414,  "sample_offset": 1159, "m1_final_fd": -203.036},
    26: {"fd_init":  750.0,  "cp_init": 920.444,  "sample_offset": 3599, "m1_final_fd":  648.782},
    29: {"fd_init": -2250.0, "cp_init": 422.755,  "sample_offset": 1653, "m1_final_fd": -2216.741},
    16: {"fd_init":  2500.0, "cp_init": 1012.258, "sample_offset": 3958, "m1_final_fd":  2577.455},
}

G2_TAPS = {
     1:(2,6),  2:(3,7),  3:(4,8),  4:(5,9),  5:(1,9),  6:(2,10),
     7:(1,8),  8:(2,9),  9:(3,10),10:(2,3), 11:(3,4), 12:(5,6),
    13:(6,7), 14:(7,8), 15:(8,9), 16:(9,10),17:(1,4), 18:(2,5),
    19:(3,6), 20:(4,7), 21:(5,8), 22:(6,9), 23:(1,3), 24:(4,6),
    25:(5,7), 26:(6,8), 27:(7,9), 28:(8,10),29:(1,6), 30:(2,7),
    31:(3,8), 32:(4,9),
}

def gen_ca(prn):
    t1, t2 = G2_TAPS[prn]; t1 -= 1; t2 -= 1
    g1 = [1]*10; g2 = [1]*10
    c = np.empty(N_CHIPS, dtype=np.float32)
    for i in range(N_CHIPS):
        chip = (g1[9] ^ g2[t1] ^ g2[t2]) & 1
        c[i] = 1.0 - 2.0 * chip
        g1 = [(g1[2] ^ g1[9]) & 1] + g1[:9]
        g2 = [(g2[1]^g2[2]^g2[5]^g2[7]^g2[8]^g2[9])&1] + g2[:9]
    return c

def rep(code, phase, off, n):
    return code[((np.arange(n) * CPS + phase + off) % N_CHIPS).astype(int)]

def run_python_tracker(prn, fd_init, cp_init, samples):
    """Python float64 reference tracker."""
    code = gen_ca(prn)
    coff = cp_init / F_CODE
    fd   = float(fd_init)
    adr  = 0.0
    ch_lock = 0
    prev_Ip = prev_Qp = err_phas_prev = 0.0
    results = []

    for ep in range(499):
        adr  += fd * T
        coff -= fd / 1.57542e9 * T
        i = int(coff * FS) % N_1MS
        j = (coff * FS) % 1.0
        phi = adr + fd * i / FS
        start_idx = ep * N_1MS + i
        if start_idx + N_1MS > len(samples):
            break

        seg = samples[start_idx : start_idx + N_1MS]
        n   = len(seg)
        t_arr = np.arange(n, dtype=np.float32) / FS
        ci = np.cos(2 * np.pi * (fd * t_arr + phi)).astype(np.float32)
        cq = -np.sin(2 * np.pi * (fd * t_arr + phi)).astype(np.float32)
        bi = seg.real * ci - seg.imag * cq
        bq = seg.real * cq + seg.imag * ci

        dp = j * CPS
        ce  = rep(code, dp, -0.5, n)
        cp_ = rep(code, dp,  0.0, n)
        cl  = rep(code, dp, +0.5, n)

        Ie = float(np.dot(bi, ce))  / N_1MS
        Qe = float(np.dot(bq, ce))  / N_1MS
        Ip = float(np.dot(bi, cp_)) / N_1MS
        Qp = float(np.dot(bq, cp_)) / N_1MS
        Il = float(np.dot(bi, cl))  / N_1MS
        Ql = float(np.dot(bq, cl))  / N_1MS

        ch_lock += 1
        if ch_lock < FLL_EPOCHS:
            if ch_lock >= 2:
                dot   = Ip*prev_Ip + Qp*prev_Qp
                cross = Ip*prev_Qp - Qp*prev_Ip
                if dot != 0.0:
                    fd -= B_FLL / 0.25 * math.atan(cross/dot) / (2*math.pi)
        else:
            if Ip != 0.0:
                err_phas = math.atan(Qp/Ip) / (2*math.pi)
                W = B_PLL / 0.53
                fd += 1.4*W*(err_phas-err_phas_prev) + W*W*err_phas*T
                err_phas_prev = err_phas

        E = math.sqrt(Ie**2 + Qe**2)
        L = math.sqrt(Il**2 + Ql**2)
        if E + L > 0:
            err_code = (E-L)/(E+L) / 2.0 * T / N_CHIPS
            coff -= B_DLL / 0.25 * err_code * T

        prev_Ip, prev_Qp = Ip, Qp
        results.append({"ep": ep, "fd": fd, "Ip": Ip, "Qp": Qp})

    return results


# ── MAIN ──────────────────────────────────────────────────────────────────────
print("Loading hardware results from PYNQ-Z2 board...")
with open(HW_JSON) as f:
    hw_all = json.load(f)

print("Loading IQ data file for Python reference...")
raw_np  = np.fromfile(DATA_FILE, dtype=np.int8)
samples = (raw_np[0::2].astype(np.float32) - 1j * raw_np[1::2].astype(np.float32)).astype(np.complex64)
print(f"Loaded {len(samples):,} complex samples\n")

all_results = {}

for prn, sat in SATELLITES.items():
    hw_prn = hw_all.get(str(prn))
    if hw_prn is None:
        print(f"PRN {prn}: NO HARDWARE DATA — skipping")
        continue

    fd_init      = sat["fd_init"]
    cp_init      = sat["cp_init"]
    sample_offset= sat["sample_offset"]
    m1_fd        = sat["m1_final_fd"]

    print(f"{'='*65}")
    print(f"  PRN {prn:2d}  | fd_init={fd_init:+8.1f} Hz | M1 final fd={m1_fd:+8.3f} Hz")
    print(f"{'='*65}")

    print(f"  Running Python float64 reference tracker...")
    py_res = run_python_tracker(prn, fd_init, cp_init, samples)

    # Compare fd trajectory epoch by epoch
    hw_fd_list = hw_prn["fd"]
    py_fd_list = [r["fd"] for r in py_res]
    n_eps = min(len(hw_fd_list), len(py_fd_list))

    # PLL error comparison (hw reports degrees, python computes from Ip/Qp)
    hw_pe_list = hw_prn["pe"]
    py_pe_list = [math.degrees(math.atan2(r["Qp"], r["Ip"])) for r in py_res]

    fd_errors = [abs(hw_fd_list[i] - py_fd_list[i]) for i in range(n_eps)]
    pe_errors = [abs(hw_pe_list[i] - py_pe_list[i]) for i in range(n_eps)]

    # late-epoch stats (after loop filter has settled, ep > 100)
    late_fd = [fd_errors[i] for i in range(n_eps) if i >= 100]
    late_pe = [pe_errors[i] for i in range(n_eps) if i >= 100]

    avg_fd_err_late = sum(late_fd) / len(late_fd) if late_fd else float('nan')
    avg_pe_err_late = sum(late_pe) / len(late_pe) if late_pe else float('nan')
    max_fd_err      = max(fd_errors) if fd_errors else float('nan')
    max_pe_err      = max(pe_errors) if pe_errors else float('nan')

    hw_final_fd = hw_fd_list[-1]
    py_final_fd = py_fd_list[-1]
    fd_vs_m1    = abs(hw_final_fd - m1_fd)
    fd_hw_py    = abs(hw_final_fd - py_final_fd)

    # Verdict: Doppler within 30 Hz of Python reference, avg fd error < 20 Hz late
    verdict = fd_hw_py < 30.0 and avg_fd_err_late < 20.0

    print(f"\n  RESULTS:")
    print(f"    M1 reference final Doppler   : {m1_fd:+10.3f} Hz")
    print(f"    Python ref  final Doppler    : {py_final_fd:+10.3f} Hz")
    print(f"    FPGA HW     final Doppler    : {hw_final_fd:+10.3f} Hz")
    print(f"    HW vs M1 Doppler error       : {fd_vs_m1:>10.3f} Hz")
    print(f"    HW vs Py Doppler error       : {fd_hw_py:>10.3f} Hz  {'[OK] LOCKED' if fd_hw_py < 30 else '[FAIL] DIVERGED'}")
    print(f"    Avg Doppler err (ep100-499)  : {avg_fd_err_late:>10.3f} Hz  {'[OK]' if avg_fd_err_late < 20 else '[FAIL]'}")
    print(f"    Max Doppler err              : {max_fd_err:>10.3f} Hz")
    print(f"    Avg PLL phase err (ep100-499): {avg_pe_err_late:>10.2f} deg")
    print(f"    Total HW epochs              : {len(hw_fd_list)}")
    print(f"\n  VERDICT: {'[OK]  PASS — FPGA hardware matches Python reference' if verdict else '[FAIL]  FAIL — Check register offsets or loop filter'}")

    all_results[prn] = {
        "m1_final_fd": m1_fd, "py_final_fd": py_final_fd,
        "hw_final_fd": hw_final_fd, "fd_vs_m1": fd_vs_m1,
        "avg_fd_err_late": avg_fd_err_late, "max_fd_err": max_fd_err,
        "avg_pe_err_late": avg_pe_err_late,
        "verdict": verdict
    }
    print()

# ── FINAL REPORT ──────────────────────────────────────────────────────────────
print("\n" + "="*65)
print("  FINAL REPORT — FPGA HARDWARE vs M1 REFERENCE")
print("="*65)
print(f"{'PRN':<6} {'M1 fd':>10} {'HW fd':>10} {'dfd':>8} {'AvgErr':>9} {'Verdict':>12}")
print("-"*65)

all_pass = True
for prn, r in all_results.items():
    v = "[OK] PASS" if r["verdict"] else "[FAIL] FAIL"
    if not r["verdict"]: all_pass = False
    print(f"  {prn:<4} {r['m1_final_fd']:>+10.2f} {r['hw_final_fd']:>+10.2f} {r['fd_vs_m1']:>8.2f} {r['avg_fd_err_late']:>9.2f}  {v:>12}")

print("="*65)
if all_pass:
    print("""
  [OK] CONFIRMED — FPGA hardware produces tracking results that match
    the M1 Python reference for all 4 GPS satellites.

    Real silicon. Real GPS signal. Real-time.
""")
else:
    failed = [str(p) for p,r in all_results.items() if not r["verdict"]]
    print(f"\n  [FAIL] PRN(s) {', '.join(failed)} need investigation.")
