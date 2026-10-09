#!/usr/bin/env bash
# Run from any directory; uses your existing AWS CLI credentials.
set -euo pipefail
if [[ $# -ne 2 || ! "$2" =~ ^i-([0-9a-f]{8}|[0-9a-f]{17})$ ]]; then
  echo 'Usage: bash scripts/power.sh on|off i-INSTANCE_ID' >&2
  exit 2
fi
action="$1"
instance_id="$2"
case "$action" in
  on)
    aws ec2 start-instances --region sa-east-1 --instance-ids "$instance_id"
    aws ec2 wait instance-running --region sa-east-1 --instance-ids "$instance_id"
    echo 'EC2 is running. Verify Tailscale is online and approved before selecting Brazil.'
    ;;
  off)
    echo 'Select None in Tailscale on manually managed devices before stopping EC2.'
    aws ec2 stop-instances --region sa-east-1 --instance-ids "$instance_id"
    aws ec2 wait instance-stopped --region sa-east-1 --instance-ids "$instance_id"
    echo 'EC2 is stopped. EBS storage and other independent resources can still incur charges.'
    ;;
  *)
    echo 'Action must be on or off.' >&2
    exit 2
    ;;
esac
