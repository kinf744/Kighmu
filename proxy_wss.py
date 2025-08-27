#!/usr/bin/env python3
import os
import subprocess
import sys

def run_command(command):
    """Execute a system command and print output."""
    print(f"Running: {command}")
    result = subprocess.run(command, shell=True, text=True, capture_output=True)
    if result.returncode != 0:
        print(f"Error: {result.stderr.strip()}")
    else:
        print(result.stdout.strip())

def install_python_packages():
    """Install necessary Python packages."""
    print("Installing required Python packages...")
    run_command(f"{sys.executable} -m pip install --upgrade pip")
    run_command(f"{sys.executable} -m pip install sshtunnel paramiko")

def main():
    # Mandatory domain input
    domain = input("Enter the domain (e.g., ws.example.com) for the SSH WebSocket tunnel (required): ").strip()
    if not domain:
        print("Error: A domain is required to continue installation.")
        sys.exit(1)

    # Check for root privileges
    if os.geteuid() != 0:
        print("Error: This script must be run as root (use sudo).")
        sys.exit(1)

    # Update and install system dependencies
    run_command("apt-get update -y")
    run_command("apt-get install -y nodejs npm screen python3-pip")

    # Install wstunnel globally via npm
    run_command("npm install -g wstunnel")

    # Install required Python packages
    install_python_packages()

    # Terminate any existing screen session named sshws
    run_command("screen -S sshws -X quit || true")

    # Start SSH WebSocket tunnel in detached screen session on port 8880
    run_command("screen -dmS sshws wstunnel -s 8880")

    # Generate and display WebSocket payload
    payload = (
        "GET /socket HTTP/1.1[crlf]"
        f"Host: {domain}[crlf]"
        "Upgrade: websocket[crlf][crlf]"
    )

    print("\nInstallation completed successfully.")
    print(f"SSH WebSocket tunnel is running on port 8880 with domain: {domain}")
    print("\nUse the following payload to connect over WebSocket SSH:\n")
    print(payload)
    print("\nTo attach to the screen session: screen -r sshws")
    print("To manually restart the tunnel: screen -dmS sshws wstunnel -s 8880")

if name == "main":
    main()
        
