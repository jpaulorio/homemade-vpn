#!/bin/bash
set -euxo pipefail
cat >/etc/sysctl.d/99-tailscale-exit.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL
sysctl --system
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
# Enroll interactively through Session Manager; no auth key in Terraform state.
