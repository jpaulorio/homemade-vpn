"""Daily, project-filtered billing snapshot; never exposes account-wide totals."""
import json
import os
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

ce = boto3.client('ce', region_name='us-east-1')
s3 = boto3.client('s3')
PROJECT = os.environ['PROJECT_TAG']
BUCKET = os.environ['COST_BUCKET']


def summarize(rows, month):
    daily, services = [], {}
    total = Decimal('0')
    estimated = False
    for row in rows:
        if not row['TimePeriod']['Start'].startswith(month):
            continue
        amount = Decimal('0')
        estimated |= row.get('Estimated', False)
        for group in row.get('Groups', []):
            metric = group['Metrics']['UnblendedCost']
            if metric['Unit'] != 'USD':
                raise ValueError('Unexpected billing currency')
            cost = Decimal(metric['Amount'])
            name = group['Keys'][0]
            services[name] = services.get(name, Decimal('0')) + cost
            amount += cost
        daily.append({'date': row['TimePeriod']['Start'], 'amount': str(amount)})
        total += amount
    return {'month': month, 'total': str(total), 'estimated': estimated,
            'daily': daily, 'services': [{'name': k, 'amount': str(v)} for k, v in
                                       sorted(services.items(), key=lambda item: item[1], reverse=True)]}


def build_report(now):
    today = now.date()
    current = today.replace(day=1)
    previous = (current - timedelta(days=1)).replace(day=1)
    base = {'generatedAt': now.isoformat(), 'currency': 'USD', 'metric': 'UnblendedCost',
            'project': PROJECT, 'tagKey': 'Project', 'periodStart': str(previous),
            'periodEndExclusive': str(today + timedelta(days=1)),
            'coverage': 'Only AWS charges attributed to Project=' + PROJECT + '. Untagged or unsupported charges, taxes, credits, and Cost Explorer API fees may be absent. This is not the full account bill.'}
    tags = ce.list_cost_allocation_tags(TagKeys=['Project']).get('CostAllocationTags', [])
    if not tags:
        return dict(base, status='waiting_for_tag', message='AWS has not made the Project billing tag available yet. The daily job will activate it when available. No cost total is reported yet.')
    if tags[0]['Status'] != 'Active':
        ce.update_cost_allocation_tags_status(CostAllocationTagsStatus=[{'TagKey': 'Project', 'Status': 'Active'}])
        return dict(base, status='waiting_for_activation', message='Project cost allocation was activated. AWS billing data may take 24 hours or longer to appear. No cost total is reported yet.')
    rows, next_token = [], None
    for _ in range(20):
        args = dict(TimePeriod={'Start': str(previous), 'End': str(today + timedelta(days=1))},
                    Granularity='DAILY', Metrics=['UnblendedCost'],
                    Filter={'Tags': {'Key': 'Project', 'Values': [PROJECT], 'MatchOptions': ['EQUALS']}},
                    GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}])
        if next_token:
            args['NextPageToken'] = next_token
        result = ce.get_cost_and_usage(**args)
        rows.extend(result['ResultsByTime'])
        next_token = result.get('NextPageToken')
        if not next_token:
            break
    else:
        raise ValueError('Billing pagination limit exceeded; incomplete report discarded')
    months = [summarize(rows, current.strftime('%Y-%m')), summarize(rows, previous.strftime('%Y-%m'))]
    has_groups = any(row.get('Groups') for row in rows)
    return dict(base, status='ready' if has_groups else 'waiting_for_data', months=months,
                message='AWS billing data is delayed, usually refreshed daily. Current-month amounts are provisional.' if has_groups else 'No attributed billing rows are available yet. This does not mean the project is free. Tag activation does not automatically recover earlier unallocated costs.')


def handler(event, context):
    now = datetime.now(timezone.utc)
    try:
        report = build_report(now)
    except (ClientError, ValueError) as error:
        code = error.response.get('Error', {}).get('Code', 'unknown') if isinstance(error, ClientError) else 'InvalidReport'
        print('Cost report failed:', code)
        report = {'status': 'unavailable', 'generatedAt': now.isoformat(), 'project': PROJECT,
                  'message': 'AWS billing report is unavailable (' + code + '). Check Cost Explorer access and enablement in the AWS Billing console. No cost total is reported.'}
    s3.put_object(Bucket=BUCKET, Key='current.json', Body=json.dumps(report).encode(),
                  ContentType='application/json', ServerSideEncryption='AES256')
    return {'status': report['status']}
