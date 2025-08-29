#!/usr/bin/env python3
import os
import subprocess
import sys
import urllib.request
import stat

def run_command(command):
    print(f"Running: {command}")
    result = subprocess.run(command, shell=True, text=True, capture_output=True)
    if result.returncode != 0:
        print(f"Error: {result.stderr.strip()}")
    else:
        print(result.stdout.strip())

def install_wstunnel_binary():
    url = "https://github.com/erebe/wstunnel/releases/download/v5.1/wstunnel-linux-x64"
    dest = "/usr/local/bin/wstunnel"
    try:
        print("Downloading wstunnel binary...")
        urllib.request.urlretrieve(url, "/tmp/wstunnel-linux-x64")
        os.chmod("/tmp/wstunnel-linux-x64",
                 stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                 stat.S_IRGRP | stat.S_IXGRP |
                 stat.S_IROTH | stat.S_IXOTH)
        run_command(f"mv /tmp/wstunnel-linux-x64 {dest}")
        print("wstunnel installed successfully.")
    except Exception as e:
        print(f"Failed to install wstunnel: {e}")
        sys.exit(1)

def main():
    domain = input("Enter the domain (e.g., ws.example.com) for the SSH WebSocket tunnel (required): ").strip()
    if not domain:
        print("Error: A domain is required to continue installation.")
        sys.exit(1)

    if os.geteuid() != 0:
        print("Error: This script must be run as root (use sudo).")
        sys.exit(1)

    run_command("apt-get update -y")
    run_command("apt-get install -y screen python3 wget")

    install_wstunnel_binary()

    # Kill any previous screen session named sshws to avoid conflicts
    run_command("screen -S sshws -X quit || true")

    # Launch wstunnel inside screen with output logging for diagnostics
    run_command("screen -dmS sshws /usr/local/bin/wstunnel --server ws://0.0.0.0:8880 -r localhost:22 > /tmp/wstunnel.log 2>&1")

    payload = (
        "GET /socket HTTP/1.1[crlf]\n"
        f"Host: {domain}[crlf]\n"
        "Upgrade: websocket[crlf]\n"
        "Connection: Upgrade[crlf][crlf]"
    )

    print("\nInstallation completed successfully.")
    print(f"SSH WebSocket tunnel is running on port 8880 with domain: {domain}")
    print("\nUse the following payload to connect over WebSocket SSH:\n")
    print(payload)
    print("\nTo attach to the screen session: screen -r sshws")
    print("Check log /tmp/wstunnel.log for detailed output or errors.")
    print("To manually restart the tunnel: screen -dmS sshws /usr/local/bin/wstunnel --server ws://0.0.0.0:8880 -r localhost:22")

if __name__ == "__main__":
    main()
