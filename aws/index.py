import base64
import os
import json
import boto3
from botocore.exceptions import ClientError

ec2 = boto3.client('ec2')
INSTANCE_ID = os.environ['INSTANCE_ID']
s3 = boto3.client('s3')

def reply(code, value):
    return {'statusCode': code,
            'headers': {'content-type': 'application/json', 'cache-control': 'no-store'},
            'body': json.dumps(value)}

def state():
    data = ec2.describe_instances(InstanceIds=[INSTANCE_ID])
    return data['Reservations'][0]['Instances'][0]['State']['Name']

def handler(event, context):
    method = event.get('requestContext', {}).get('http', {}).get('method')
    path = event.get('rawPath', '')
    try:
        if method == 'GET' and path == '/costs':
            try:
                data = s3.get_object(Bucket=os.environ['COST_BUCKET'], Key='current.json')
                return reply(200, json.loads(data['Body'].read()))
            except ClientError as exc:
                if exc.response.get('Error', {}).get('Code') in ('NoSuchKey', '404'):
                    return reply(200, {'status': 'pending', 'message': 'The first daily cost report has not run yet.'})
                raise
        if method == 'GET' and path == '/state':
            return reply(200, {'state': state(), 'exitNodeReady': None})
        if method == 'POST' and path == '/power':
            try:
                body = event.get('body') or '{}'
                if event.get('isBase64Encoded'):
                    body = base64.b64decode(body, validate=True).decode('utf-8')
                req = json.loads(body)
            except (ValueError, TypeError):
                return reply(400, {'error': 'invalid JSON'})
            if not isinstance(req, dict):
                return reply(400, {'error': 'JSON body must be an object'})
            action = req.get('action')
            if action not in ('on', 'off'):
                return reply(400, {'error': 'action must be on or off'})
            current = state()
            if action == 'on':
                if current == 'stopped':
                    ec2.start_instances(InstanceIds=[INSTANCE_ID])
                    return reply(202, {'state': 'pending', 'action': action})
                if current in ('running', 'pending'):
                    return reply(200, {'state': current, 'action': action})
            else:
                if current == 'running':
                    ec2.stop_instances(InstanceIds=[INSTANCE_ID])
                    return reply(202, {'state': 'stopping', 'action': action})
                if current in ('stopping', 'stopped'):
                    return reply(200, {'state': current, 'action': action})
            return reply(409, {'error': 'EC2 transitional state', 'state': current})
        return reply(404, {'error': 'not found'})
    except ClientError as exc:
        print('AWS API failed:', exc.response.get('Error', {}).get('Code', 'unknown'))
        return reply(502, {'error': 'AWS API request failed'})
