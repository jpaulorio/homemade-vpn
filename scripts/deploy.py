#!/usr/bin/env python3
"""Read-only AWS prerequisite checks for Terraform deployment."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

REGION = 'sa-east-1'
ROOT = Path(__file__).resolve().parents[1]


def aws(*args, profile=None):
    command = ['aws', '--region', REGION, '--no-cli-pager']
    if profile:
        command += ['--profile', profile]
    result = subprocess.run(command + list(args), check=True, capture_output=True, text=True)
    return json.loads(result.stdout) if result.stdout.strip() else {}


def check_subnet(vpc_id, subnet_id, profile=None):
    subnets = aws('ec2', 'describe-subnets', '--subnet-ids', subnet_id, profile=profile)['Subnets']
    if len(subnets) != 1 or subnets[0]['VpcId'] != vpc_id:
        raise ValueError('Subnet does not belong to the selected VPC')
    if subnets[0].get('State') != 'available':
        raise ValueError('Subnet is not available')
    tables = aws('ec2', 'describe-route-tables', '--filters', f'Name=vpc-id,Values={vpc_id}', profile=profile)['RouteTables']
    explicit = [t for t in tables if any(a.get('SubnetId') == subnet_id for a in t.get('Associations', []))]
    effective = explicit or [t for t in tables if any(a.get('Main') for a in t.get('Associations', []))]
    if len(effective) != 1:
        raise ValueError('Could not identify one effective subnet route table')
    routes = effective[0].get('Routes', [])
    gateways = [r['GatewayId'] for r in routes if r.get('DestinationCidrBlock') == '0.0.0.0/0' and r.get('State') == 'active' and r.get('GatewayId', '').startswith('igw-')]
    if not gateways:
        raise ValueError('Subnet needs an active 0.0.0.0/0 route to an Internet Gateway')
    igws = aws('ec2', 'describe-internet-gateways', '--internet-gateway-ids', gateways[0], profile=profile)['InternetGateways']
    if not any(a.get('VpcId') == vpc_id and a.get('State') == 'available' for g in igws for a in g.get('Attachments', [])):
        raise ValueError('Internet Gateway is not attached to the selected VPC')


def main():
    parser = argparse.ArgumentParser(description='Read-only AWS subnet preflight before Terraform plan/apply')
    parser.add_argument('--vpc', required=True)
    parser.add_argument('--subnet', required=True)
    parser.add_argument('--profile')
    args = parser.parse_args()
    if shutil.which('aws') is None:
        parser.error('AWS CLI v2 is required. Install it and sign in before continuing.')
    try:
        identity = aws('sts', 'get-caller-identity', profile=args.profile)
        print(f"AWS account: {identity['Account']}; region: {REGION}")
        check_subnet(args.vpc, args.subnet, args.profile)
        print('Preflight passed: signed in, subnet/VPC match, active public Internet Gateway route.')
    except (subprocess.CalledProcessError, KeyError, ValueError) as exc:
        print((exc.stderr or str(exc)) if isinstance(exc, subprocess.CalledProcessError) else str(exc), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
