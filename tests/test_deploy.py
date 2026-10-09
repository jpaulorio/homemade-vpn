import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('deploy', Path(__file__).resolve().parents[1] / 'scripts/deploy.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)

class SubnetTests(unittest.TestCase):
    def fixtures(self, route=None, explicit=True):
        return [
            {'Subnets': [{'VpcId': 'vpc-test', 'State': 'available'}]},
            {'RouteTables': [{'Associations': [{'SubnetId': 'subnet-test'} if explicit else {'Main': True}], 'Routes': [route or {'DestinationCidrBlock': '0.0.0.0/0', 'GatewayId': 'igw-test', 'State': 'active'}]}]},
            {'InternetGateways': [{'Attachments': [{'VpcId': 'vpc-test', 'State': 'available'}]}]},
        ]

    def test_explicit_and_main_routes(self):
        for explicit in (True, False):
            with patch.object(deploy, 'aws', side_effect=self.fixtures(explicit=explicit)):
                deploy.check_subnet('vpc-test', 'subnet-test')

    def test_vpc_mismatch(self):
        with patch.object(deploy, 'aws', return_value={'Subnets': [{'VpcId': 'vpc-other'}]}):
            with self.assertRaisesRegex(ValueError, 'does not belong'):
                deploy.check_subnet('vpc-test', 'subnet-test')

    def test_private_or_blackhole_routes(self):
        for route in ({'DestinationCidrBlock': '0.0.0.0/0', 'GatewayId': 'igw-test', 'State': 'blackhole'}, {'DestinationCidrBlock': '0.0.0.0/0', 'NatGatewayId': 'nat-test', 'State': 'active'}):
            with patch.object(deploy, 'aws', side_effect=self.fixtures(route=route)):
                with self.assertRaisesRegex(ValueError, 'active.*Internet Gateway'):
                    deploy.check_subnet('vpc-test', 'subnet-test')

    def test_detached_gateway(self):
        fixtures = self.fixtures()
        fixtures[-1] = {'InternetGateways': [{'Attachments': []}]}
        with patch.object(deploy, 'aws', side_effect=fixtures):
            with self.assertRaisesRegex(ValueError, 'not attached'):
                deploy.check_subnet('vpc-test', 'subnet-test')

if __name__ == '__main__':
    unittest.main()
