import sys
import time
import numpy as np
from pynq import Overlay, MMIO, allocate
import json

F_CODE = 1.023e6
FS = 4e6
N_CHIPS = 1023
N_1MS = 4000
T = 1e-3
CPS = F_CODE / FS

B_FLL = 5.0
B_PLL = 15.0
B_DLL = 1.0
FLL_EPOCHS = 50

class HwTrackerV2:
    def __init__(self, overlay_path, prn, init_doppler, init_code_phase):
        self.overlay = Overlay(overlay_path)
        self.tracker_ip = self.overlay.gps_tracker_0
        self.dma = self.overlay.axi_dma_0
        
        self.config_mmio = MMIO(0x40000000, 0x10000) 
        self.status_mmio = MMIO(0x40010000, 0x10000) 
        
        self.prn = prn
        self.fd = init_doppler
        self.code_phase = init_code_phase 
        
        self.carrier_phase = 0
        
        self.tx_buffer = allocate(shape=(N_1MS,), dtype=np.uint32)
        
        self.ch_lock = 0
        self.prev_Ip = 0.0
        self.prev_Qp = 0.0
        self.err_phas_prev = 0.0

    def step(self, epoch_idx, iq_samples_int8):
        I_array = iq_samples_int8[0::2].astype(np.uint32) & 0xFF
        Q_array = iq_samples_int8[1::2].astype(np.uint32) & 0xFF
        packed_data = (Q_array << 8) | I_array
        
        np.copyto(self.tx_buffer, packed_data)
        self.tx_buffer.flush()
        
        carrier_step = int(round((self.fd / FS) * (1 << 32)))
        f_code_doppler = F_CODE * (1.0 + self.fd / 1.57542e9)
        code_step = int(round((f_code_doppler / FS) * 65536))
        
        # Convert chips to Q16.16 format for hardware
        code_phase_hw = int(self.code_phase * 65536) & 0xFFFFFFFF
        
        self.config_mmio.write(0x10, self.prn)
        self.config_mmio.write(0x18, carrier_step & 0xFFFFFFFF)
        self.config_mmio.write(0x20, self.carrier_phase & 0xFFFFFFFF)
        self.config_mmio.write(0x28, code_phase_hw)
        self.config_mmio.write(0x30, code_step & 0xFFFFFFFF)
        
        self.dma.sendchannel.transfer(self.tx_buffer)
        
        self.config_mmio.write(0x00, 0x1) 
        
        dma_timeout = time.time() + 1.0
        while not self.dma.sendchannel.idle:
            if time.time() > dma_timeout:
                print(f"Error: DMA transfer timeout at epoch {epoch_idx}")
                return False
        
        timeout = time.time() + 1.0
        while True:
            ctrl = self.config_mmio.read(0x00)
            if (ctrl & 0x2) != 0:
                break
            if time.time() > timeout:
                print(f"Error: Tracker timeout at epoch {epoch_idx}. Ctrl reg: {hex(ctrl)}")
                return False
                
        def read_signed(addr):
            val = self.status_mmio.read(addr)
            return val - 2**32 if val & 0x80000000 else val

        Ie = read_signed(0x10) / 131072000.0  
        Qe = read_signed(0x20) / 131072000.0
        Ip = read_signed(0x30) / 131072000.0
        Qp = read_signed(0x40) / 131072000.0
        Il = read_signed(0x50) / 131072000.0
        Ql = read_signed(0x60) / 131072000.0
        
        self.carrier_phase = self.status_mmio.read(0x70)
        final_code_phase_hw = self.status_mmio.read(0x80)
        self.code_phase = (final_code_phase_hw / 65536.0) % N_CHIPS
        
        E = np.sqrt(Ie*Ie + Qe*Qe)
        L = np.sqrt(Il*Il + Ql*Ql)
        
        self.ch_lock += 1
        
        if self.ch_lock < FLL_EPOCHS:
            if self.ch_lock >= 2:
                dot = Ip * self.prev_Ip + Qp * self.prev_Qp
                cross = Ip * self.prev_Qp - Qp * self.prev_Ip
                if dot != 0.0:
                    err_freq = np.arctan(cross / dot) / (2.0 * np.pi)
                    self.fd -= B_FLL / 0.25 * err_freq
            pe = np.arctan2(Qp, Ip)
        else:
            if Ip != 0.0:
                err_phas = np.arctan(Qp / Ip) / (2.0 * np.pi)
                W = B_PLL / 0.53
                self.fd += 1.4 * W * (err_phas - self.err_phas_prev) + W * W * err_phas * T
                self.err_phas_prev = err_phas
            pe = np.arctan2(Qp, Ip)
            
        de = 0.0
        if E + L > 0.0:
            err_code = (E - L) / (E + L) / 2.0
            # Applying correction exactly as Python baseline would, but keeping units in chips.
            self.code_phase -= (B_DLL / 0.25) * err_code * T
            de = err_code
            
        self.prev_Ip = Ip
        self.prev_Qp = Qp
        
        return {
            'ep': epoch_idx,
            'fd': self.fd,
            'pe': float(np.degrees((pe + np.pi/2) % np.pi - np.pi/2)),
            'de': float(de),
            'Ip': float(Ip),
            'Qp': float(Qp)
        }

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 track_on_hw_v2.py <iq_file.bin>")
        sys.exit(1)
        
    bin_file = sys.argv[1]
    print(f"Loading IQ data from {bin_file}...")
    raw_data = np.fromfile(bin_file, dtype=np.int8)
    
    all_history = {}
    
    SATELLITES = {
        31: {"fd_init": -200.0,   "cp_init": 296.414},
        26: {"fd_init":  750.0,   "cp_init": 920.444},
        29: {"fd_init": -2250.0,  "cp_init": 422.755},
        16: {"fd_init":  2500.0,  "cp_init": 1012.258},
    }
    
    for target_prn, sat in SATELLITES.items():
        init_fd = sat["fd_init"]
        cp_init = sat["cp_init"]
        
        coff = cp_init / F_CODE
        sample_offset = int(coff * FS) % 4000
        j = (coff * FS) % 1.0
        init_code_phase = j * CPS
        
        history = {
            'ep': [], 'fd': [], 'pe': [], 'de': [], 'Ip': [], 'Qp': []
        }
        
        tracker = HwTrackerV2(overlay_path="tracker_hw.bit", prn=target_prn, init_doppler=init_fd, init_code_phase=init_code_phase)
        
        print(f"Starting v2 hardware tracking loop for PRN {target_prn}...")
        num_epochs = 499
        
        start_time = time.perf_counter()
        
        for ep in range(num_epochs):
            start_idx = (sample_offset + ep * N_1MS) * 2 
            if start_idx + N_1MS*2 > len(raw_data):
                break
                
            iq_chunk = raw_data[start_idx : start_idx + N_1MS*2]
            
            res = tracker.step(ep, iq_chunk)
            if not res:
                break
                
            history['ep'].append(res['ep'])
            history['fd'].append(res['fd'])
            history['pe'].append(res['pe'])
            history['de'].append(res['de'])
            history['Ip'].append(res['Ip'])
            history['Qp'].append(res['Qp'])
            
            if ep % 50 == 0 or ep == num_epochs - 1:
                print(f"Ep {ep:03d}: f_D = {res['fd']:+7.1f} Hz, PLL err = {res['pe']:+6.1f}°, DLL err = {res['de']:+.3f} chips")
                
        elapsed = time.perf_counter() - start_time
        print("-" * 50)
        print(f"Tracking PRN {target_prn} complete in {elapsed:.6f} seconds.")
        if history['ep']:
            print(f"Average time per epoch: {elapsed/len(history['ep'])*1000:.3f} ms")
        print("-" * 50)
        
        all_history[str(target_prn)] = history
        
    out_file = "hardware_tracking_v3.json"
    with open(out_file, "w") as f:
        json.dump(all_history, f)
    print(f"Saved {out_file}")
