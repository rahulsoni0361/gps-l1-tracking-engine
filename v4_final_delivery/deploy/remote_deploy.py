import paramiko
import os
import sys

# Configuration
HOST = "192.168.1.155"
USER = "xilinx"
PASS = "xilinx"

LOCAL_DEPLOY_DIR = r"d:\pclient\gps\v3\deploy"
DATA_FILE = r"D:\GPS_M1\client_data\L1_20211202_084700_4MHz_IQ.bin"

REMOTE_DIR = "/home/xilinx/v3_deploy"

def deploy_and_run():
    print(f"Connecting to {HOST}...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username=USER, password=PASS)
    
    # Create remote directory
    ssh.exec_command(f"mkdir -p {REMOTE_DIR}")
    
    print("Uploading files to PYNQ board...")
    sftp = ssh.open_sftp()
    
    files_to_upload = [
        (os.path.join(LOCAL_DEPLOY_DIR, "track_on_hw.py"), "track_on_hw.py"),
        (os.path.join(LOCAL_DEPLOY_DIR, "tracker_hw.bit"), "tracker_hw.bit"),
        (os.path.join(LOCAL_DEPLOY_DIR, "tracker_hw.hwh"), "tracker_hw.hwh"),
    ]
    
    for local_path, remote_name in files_to_upload:
        remote_path = f"{REMOTE_DIR}/{remote_name}"
        print(f"  Uploading {local_path} -> {remote_path} ...")
        sftp.put(local_path, remote_path)
        
    print("Executing tracking script on board via sudo...")
    # Use the special pynq environment as seen in v1
    ssh_cmd = f'cd {REMOTE_DIR} && echo {PASS} | sudo -S bash -l -c "/usr/local/share/pynq-venv/bin/python3 -u track_on_hw.py /home/xilinx/v2_deploy_test/L1_20211202_084700_4MHz_IQ.bin"'
    
    stdin, stdout, stderr = ssh.exec_command(ssh_cmd)
    
    while not stdout.channel.exit_status_ready():
        if stdout.channel.recv_ready():
            print(stdout.channel.recv(1024).decode('utf-8'), end='')
        if stderr.channel.recv_ready():
            print(stderr.channel.recv(1024).decode('utf-8'), end='')
        import time
        time.sleep(0.1)
        
    print(stdout.read().decode('utf-8'), end='')
    print(stderr.read().decode('utf-8'), end='')
    
    exit_status = stdout.channel.recv_exit_status()
    print(f"Script finished with exit status: {exit_status}")
    
    if exit_status == 0:
        print("Downloading results...")
        sftp.get(f"{REMOTE_DIR}/hardware_tracking_v3.json", os.path.join(LOCAL_DEPLOY_DIR, "hardware_tracking_v3.json"))
        print("Downloaded hardware_tracking_v3.json to host!")
        
    sftp.close()
    ssh.close()

if __name__ == "__main__":
    deploy_and_run()
 
