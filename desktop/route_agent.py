#!/usr/bin/env python3
"""Optional desktop-side Tailscale exit-node route reconciler.

Run with sufficient Tailscale administrative privileges. This utility modifies
ONLY the exit-node preference on its own device. It does not start/stop AWS.
CAUTION: no offline guarantee during the period before state is reconciled.
"""
import ipaddress
import json
import os
import subprocess
import time

AWS_EXIT_IP = os.environ.get('AWS_EXIT_IP', '')  # e.g. 100.101.102.103
CHECK_SECONDS = max(10, int(os.environ.get('CHECK_SECONDS', '20')))
def validate_config():
    try:
        address = ipaddress.ip_address(AWS_EXIT_IP)
        if address not in ipaddress.ip_network('100.64.0.0/10'):
            raise ValueError()
    except ValueError:
        raise SystemExit('Set AWS_EXIT_IP to a Tailscale IPv4 in 100.64.0.0/10')


def ts(*args):
    return subprocess.run(['tailscale', *args], capture_output=True, text=True, check=True, timeout=10)


def reconcile():
    status = json.loads(ts('status', '--json').stdout)
    peers = list((status.get('Peer') or {}).values())
    target = next((p for p in peers if AWS_EXIT_IP in (p.get('TailscaleIPs') or [])), None)
    selected = status.get('ExitNodeStatus') or {}
    selected_id = selected.get('ID')
    selected_ips = [selected.get('TailscaleIP'), *(selected.get('TailscaleIPs') or [])]
    target_id = target.get('ID') if target else None
    available = bool(target and target.get('Online') and target.get('ExitNodeOption'))
    if available and selected_id != target_id:
        ts('set', f'--exit-node={AWS_EXIT_IP}', '--exit-node-allow-lan-access=true')
        print('Selected Brazil exit node')
    elif not available and target_id and selected_id == target_id:
        ts('set', '--exit-node=')
        print('Cleared offline Brazil exit node; normal LAN Internet restored')
    elif not available and AWS_EXIT_IP in selected_ips:
        ts('set', '--exit-node=')
        print('Cleared missing Brazil exit node')


if __name__ == '__main__':
    validate_config()
    print('Checking Tailscale every', CHECK_SECONDS, 'seconds')
    while True:
        try:
            reconcile()
        except Exception as exc:
            print('Check failed; no changes:', str(exc))
        time.sleep(CHECK_SECONDS)
