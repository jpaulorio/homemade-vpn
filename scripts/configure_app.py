#!/usr/bin/env python3
"""Write public Flutter configuration from completed Terraform outputs."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
terraform = str(root / '.tools/terraform') if (root / '.tools/terraform').exists() else 'terraform'
result = subprocess.run([terraform, '-chdir=' + str(root / 'terraform'), 'output', '-json', 'flutter_config'], check=True, capture_output=True, text=True)
config = json.loads(result.stdout)
required = {'API_BASE_URL', 'COGNITO_ISSUER', 'COGNITO_CLIENT_ID'}
if set(config) != required or any(not isinstance(v, str) or not v for v in config.values()):
    raise ValueError('Terraform outputs do not contain complete app configuration')
path = root / 'flutter/config.json'
path.write_text(json.dumps(config, indent=2) + '\n')
print('Public configuration written to', path)
