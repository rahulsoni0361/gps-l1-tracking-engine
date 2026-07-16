import json

with open('hardware_tracking_v3.json') as f:
    d = json.load(f)

print("=== RAW HARDWARE JSON CONTENTS ===")
print(f"Top-level keys: {list(d.keys())}")
print()

for prn_key, v in d.items():
    print(f"--- PRN {prn_key} ---")
    print(f"  Keys in record: {list(v.keys())}")
    for k, val in v.items():
        if isinstance(val, list):
            print(f"  {k}: list of {len(val)} items, first={val[0]:.4f}, last={val[-1]:.4f}")
        else:
            print(f"  {k}: {val}")
    print()
