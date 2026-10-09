import io
import importlib.util
import json
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('agent', ROOT / 'desktop/route_agent.py')
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)

class RouteTests(unittest.TestCase):
    def check(self, status):
        agent.AWS_EXIT_IP = '100.100.100.100'
        with patch.object(agent, 'ts', return_value=types.SimpleNamespace(stdout=json.dumps(status))) as cli:
            agent.reconcile()
            return cli.call_args_list

    def test_disappeared_peer_clears_selected_ip(self):
        calls = self.check({'ExitNodeStatus': {'ID': 'gone', 'TailscaleIP': '100.100.100.100'}})
        self.assertEqual(calls[-1].args, ('set', '--exit-node='))

    def test_unrelated_exit_is_not_cleared(self):
        calls = self.check({'ExitNodeStatus': {'ID': 'other', 'TailscaleIP': '100.100.100.101'}})
        self.assertEqual(len(calls), 1)

    def test_online_approved_target_is_selected(self):
        calls = self.check({'Peer': {'key': {'ID': 'brazil', 'Online': True, 'ExitNodeOption': True, 'TailscaleIPs': ['100.100.100.100']}}})
        self.assertEqual(calls[-1].args[1], '--exit-node=100.100.100.100')

class ApiTests(unittest.TestCase):
    def setUp(self):
        code = (ROOT / 'aws/index.py').read_text()
        self.ec2 = Mock()
        self.ec2.describe_instances.return_value = {'Reservations': [{'Instances': [{'State': {'Name': 'stopped'}}]}]}
        boto = types.ModuleType('boto3'); boto.client = Mock(return_value=self.ec2)
        errors = types.ModuleType('botocore.exceptions'); errors.ClientError = type('ClientError', (Exception,), {})
        self.ns = {}
        with patch.dict(sys.modules, {'boto3': boto, 'botocore.exceptions': errors}), patch.dict('os.environ', {'INSTANCE_ID': 'i-test'}):
            exec(compile(code, 'inline_lambda', 'exec'), self.ns)

    def request(self, body):
        return self.ns['handler']({'requestContext': {'http': {'method': 'POST'}}, 'rawPath': '/power', 'body': body}, None)

    def test_costs_returns_saved_snapshot_without_billing_query(self):
        self.ec2.get_object.return_value = {'Body': io.BytesIO(b'{"status":"waiting_for_tag"}')}
        with patch.dict('os.environ', {'COST_BUCKET': 'private-costs'}):
            result = self.ns['handler']({'requestContext': {'http': {'method': 'GET'}}, 'rawPath': '/costs'}, None)
        self.assertEqual(result['statusCode'], 200)
        self.assertEqual(json.loads(result['body'])['status'], 'waiting_for_tag')
        self.ec2.get_object.assert_called_once_with(Bucket='private-costs', Key='current.json')
        self.ec2.describe_instances.assert_not_called()

    def test_invalid_payloads(self):
        for body in ('[]', 'null', '1', '"on"', '{', '{"action":"delete"}'):
            self.assertEqual(self.request(body)['statusCode'], 400)
        self.ec2.start_instances.assert_not_called()

    def test_start_and_idempotency(self):
        self.assertEqual(self.request('{"action":"on"}')['statusCode'], 202)
        self.ec2.start_instances.assert_called_once_with(InstanceIds=['i-test'])
        self.ec2.describe_instances.return_value['Reservations'][0]['Instances'][0]['State']['Name'] = 'running'
        self.assertEqual(self.request('{"action":"on"}')['statusCode'], 200)
        self.assertEqual(self.ec2.start_instances.call_count, 1)

    def test_stop_running_instance(self):
        self.ec2.describe_instances.return_value['Reservations'][0]['Instances'][0]['State']['Name'] = 'running'
        self.assertEqual(self.request('{"action":"off"}')['statusCode'], 202)
        self.ec2.stop_instances.assert_called_once_with(InstanceIds=['i-test'])

    def test_opposing_transition_is_conflict(self):
        self.ec2.describe_instances.return_value['Reservations'][0]['Instances'][0]['State']['Name'] = 'pending'
        self.assertEqual(self.request('{"action":"off"}')['statusCode'], 409)
        self.ec2.stop_instances.assert_not_called()

if __name__ == '__main__':
    unittest.main()
