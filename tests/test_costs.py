import importlib.util
import json
import os
import sys
import types
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]

class CostTests(unittest.TestCase):
    def setUp(self):
        self.ce, self.s3 = Mock(), Mock()
        boto = types.ModuleType('boto3')
        boto.client = lambda name, **kwargs: self.ce if name == 'ce' else self.s3
        errors = types.ModuleType('botocore.exceptions')
        errors.ClientError = type('ClientError', (Exception,), {})
        spec = importlib.util.spec_from_file_location('costs', ROOT / 'aws/cost_report.py')
        self.module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {'boto3': boto, 'botocore.exceptions': errors}), patch.dict(os.environ, {'PROJECT_TAG':'brazil-tailscale-exit','COST_BUCKET':'private-report'}):
            spec.loader.exec_module(self.module)
        self.now = datetime(2026, 10, 8, tzinfo=timezone.utc)
        self.ce.list_cost_allocation_tags.return_value = {'CostAllocationTags':[{'Status':'Active'}]}

    def row(self, date, amount, name='EC2', estimated=False):
        return {'TimePeriod':{'Start':date},'Estimated':estimated,'Groups':[{'Keys':[name], 'Metrics':{'UnblendedCost':{'Amount':amount,'Unit':'USD'}}}]}

    def test_decimal_aggregation_and_month_boundary(self):
        result = self.module.summarize([self.row('2026-10-01','0.1'),self.row('2026-10-02','0.2',estimated=True),self.row('2026-10-03','-0.05'),self.row('2026-09-30','99')], '2026-10')
        self.assertEqual(result['total'],'0.25')
        self.assertEqual(result['services'][0]['amount'],'0.25')
        self.assertTrue(result['estimated'])

    def test_missing_tag_is_pending_not_zero(self):
        self.ce.list_cost_allocation_tags.return_value = {'CostAllocationTags':[]}
        report = self.module.build_report(self.now)
        self.assertEqual(report['status'],'waiting_for_tag')
        self.assertNotIn('months',report)
        self.ce.get_cost_and_usage.assert_not_called()

    def test_activate_tag_before_querying(self):
        self.ce.list_cost_allocation_tags.return_value = {'CostAllocationTags':[{'Status':'Inactive'}]}
        self.assertEqual(self.module.build_report(self.now)['status'],'waiting_for_activation')
        self.ce.update_cost_allocation_tags_status.assert_called_once_with(CostAllocationTagsStatus=[{'TagKey':'Project','Status':'Active'}])
        self.ce.get_cost_and_usage.assert_not_called()

    def test_filter_and_pagination(self):
        self.ce.get_cost_and_usage.side_effect = [
            {'ResultsByTime':[self.row('2026-10-01','1')], 'NextPageToken':'next'},
            {'ResultsByTime':[self.row('2026-10-02','2')]},
        ]
        report = self.module.build_report(self.now)
        self.assertEqual(report['months'][0]['total'],'3')
        for call in self.ce.get_cost_and_usage.call_args_list:
            self.assertEqual(call.kwargs['Filter'],{'Tags':{'Key':'Project','Values':['brazil-tailscale-exit'],'MatchOptions':['EQUALS']}})
        self.assertEqual(self.ce.get_cost_and_usage.call_args.kwargs['NextPageToken'],'next')
        self.assertEqual(report['periodEndExclusive'],'2026-10-09')

    def test_no_attributed_rows_not_ready(self):
        self.ce.get_cost_and_usage.return_value = {'ResultsByTime':[{'TimePeriod':{'Start':'2026-10-01'},'Groups':[]}]}
        self.assertEqual(self.module.build_report(self.now)['status'],'waiting_for_data')

    def test_snapshot_private_and_encrypted(self):
        self.ce.list_cost_allocation_tags.return_value = {'CostAllocationTags':[]}
        self.module.handler({},None)
        saved = self.s3.put_object.call_args.kwargs
        self.assertEqual(saved['Bucket'],'private-report')
        self.assertEqual(saved['ServerSideEncryption'],'AES256')
        self.assertNotIn('months',json.loads(saved['Body']))
