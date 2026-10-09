# Brazil Tailscale exit node and family controller

Terraform provisions an on-demand Amazon Linux 2023 EC2 host in São Paulo (`sa-east-1`), Cognito sign-in, and a JWT-protected API Gateway/Lambda power controller. Flutter provides an Android/iOS round power button; an optional Python desktop helper selects Brazil while available and clears it when offline.

The button controls EC2 power. Phones select/deselect the exit node separately in Tailscale. EC2 `running` is not proof that the VPN is ready. Select None in Tailscale on manually managed devices before stopping EC2.

## Deployment with Terraform and AWS SSO

1. Install Terraform and AWS CLI v2, then configure IAM Identity Center:

   ```bash
   aws configure sso --profile brazil-exit
   aws sso login --profile brazil-exit
   aws sts get-caller-identity --profile brazil-exit
   ```

   Use your SSO start/issuer URL and SSO region; the infrastructure region is always São Paulo regardless of SSO region. No AWS access keys belong in this project.

2. Find your VPC and a public subnet in São Paulo:

   ```bash
   aws ec2 describe-vpcs --profile brazil-exit --region sa-east-1 --filters Name=isDefault,Values=true
   aws ec2 describe-subnets --profile brazil-exit --region sa-east-1
   ```

   The subnet needs an active `0.0.0.0/0` route to an attached Internet Gateway. Validate it with:

   ```bash
   python3 scripts/deploy.py --profile brazil-exit --vpc vpc-REPLACE --subnet subnet-REPLACE
   ```

3. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`; replace the profile, VPC, subnet and unique Cognito domain prefix. Then initialize and review the plan:

   ```bash
   terraform -chdir=terraform init
   terraform -chdir=terraform validate
   terraform -chdir=terraform plan -out=deployment.tfplan
   terraform -chdir=terraform apply deployment.tfplan
   python3 scripts/configure_app.py
   ```

   A verified Terraform binary downloaded locally is available at `.tools/terraform` on the implementation machine. Use that path in place of `terraform` if it is not on PATH.

   Terraform state is local and ignored by Git. Keep the state and backups private and recoverable; they are needed to manage these resources. Commit `.terraform.lock.hcl`. Do not deploy the legacy CloudFormation template alongside Terraform. No existing stack was deployed, so this is a fresh Terraform deployment rather than a state migration.

4. Use `terraform -chdir=terraform output instance_id` to find EC2. Connect using AWS Systems Manager Session Manager. In the instance:

   ```bash
   sudo systemctl status tailscaled --no-pager
   sudo sysctl net.ipv4.ip_forward
   sudo sysctl net.ipv6.conf.all.forwarding
   sudo tailscale up --advertise-exit-node
   sudo tailscale status
   ```

   Open the login URL to join your existing tailnet. Approve Use as exit node in the Tailscale admin console. Verify client permissions to `autogroup:internet`. Consider device key expiry for the connector. Cognito accounts and tailnet membership are separate.

5. Invite your two family accounts using the Terraform `user_pool_id` output:

   ```bash
   aws cognito-idp admin-create-user --profile brazil-exit --region sa-east-1 \
     --user-pool-id YOUR_POOL_ID --username YOUR_EMAIL \
     --user-attributes Name=email,Value=YOUR_EMAIL Name=email_verified,Value=true \
     --desired-delivery-mediums EMAIL
   ```

   Repeat for the second account. Public signup is disabled; the pool does not enforce a two-user maximum. Each user completes password setup through Cognito.

6. Test on one laptop: select Brazil, verify public egress IP, select None, and verify ISP egress returns. Stop/start EC2 and verify Tailscale identity and approval persist. Only then test the phone controller and optional desktop helper.

## Flutter app

Android/iOS projects and `brazilexit://oauth` callbacks are configured. `scripts/configure_app.py` writes public endpoints/client ID from completed Terraform outputs to ignored `flutter/config.json`.

```bash
cd flutter
flutter pub get
flutter run --dart-define-from-file=config.json
flutter build apk --debug --dart-define-from-file=config.json
```

Android production distribution requires your release signing configuration. iOS requires Xcode and Apple provisioning. The app does not implement a VPN tunnel or remote client route configuration. See `flutter/README.md`.

## Desktop and terminal controls

```bash
AWS_EXIT_IP=100.x.y.z CHECK_SECONDS=20 python3 desktop/route_agent.py
AWS_PROFILE=brazil-exit bash scripts/power.sh on i-INSTANCE_ID
# Select None in Tailscale on manually managed devices before stopping.
AWS_PROFILE=brazil-exit bash scripts/power.sh off i-INSTANCE_ID
```

The desktop helper needs Python, Tailscale CLI access and permission to change local preferences. It is best-effort and may temporarily lose connectivity during failover. Test interactively before registering an OS background task.

## Costs and lifecycle

Compute and auto-assigned public IPv4 charges stop when EC2 is stopped; retained EBS continues billing. Other services and data transfer may incur charges. The original PDF's less-than-$1.20 monthly total omits EBS and is not a budget quote. Configure a billing alert in your AWS account. No Elastic IP is created. Destroying infrastructure terminates EC2 and deletes its root volume and retained Tailscale identity.

## Verification and source documents

```bash
python3 -m unittest discover -s tests -v
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
cd flutter
flutter analyze
flutter test
```

Both source PDFs are preserved in `docs/`; `docs/implementation-review.md` maps requirements and source caveats. `aws/stack.yaml` is the original CloudFormation reference; Terraform is the active deployment path. Terraform packages the tested Lambda source in `aws/index.py`.

The original project guides are included in `docs/`. Platform callbacks follow [Flutter AppAuth documentation](https://pub.dev/packages/flutter_appauth); routing uses the [Tailscale CLI](https://tailscale.com/docs/reference/tailscale-cli).

The original deployment was exercised on Android and through the browser controller. Its AWS infrastructure was torn down on 2026-10-09. See `docs/deployment-status.md` for the deployment history and teardown verification. Deploy your own infrastructure before using the app.

## Verification status

Python API, routing, subnet-preflight, and cost-report tests pass (18 tests). Browser checks cover PKCE, OAuth state rejection, authenticated requests, expired sessions, stop cancellation, and cost display. Android was built and sign-in worked on a physical device; the browser controller also completed live sign-in. The native iOS project requires Apple signing and has not been tested on an iPhone.

Generated deployment configuration, Terraform state/plans, credentials, local tools, signing keys, and build output are excluded from version control. Use the example configuration files for a new deployment.

### Browser controller

Terraform hosts `web/` over HTTPS with CloudFront and a private S3 origin. Open the `browser_url` output and choose **Sign in** using your invited Cognito account. A dedicated public client uses authorization code flow with PKCE and verifies OAuth state before exchanging the code. Tokens stay in this tab’s session storage; sessions expire after one hour and require another sign-in. Sign out clears the local session and the Cognito browser session.

The page polls power status every ten seconds while visible. Starting/stopping uses the existing authenticated API; stopping asks for confirmation because it disconnects other users. Choose the exit node separately in Tailscale. Server power does not verify VPN readiness. The API accepts browser requests only from the controller’s HTTPS origin.

Deploy web changes with the usual Terraform plan/apply flow. Assets disable caching so deployments do not require a CloudFront invalidation. Hosting adds S3 and CloudFront usage charges.

### Cost reporting

The browser's **Project costs** panel shows AWS-attributed month-to-date and previous-month unblended costs in USD, daily spending, costs by AWS service, and a downloadable daily CSV. These are delayed billing records, not a live meter or a complete invoice. It explicitly shows pending/unavailable data instead of treating missing attribution as zero cost.

A separate Lambda writes an encrypted private S3 snapshot every day at 12:00 UTC. Only that collector can query Cost Explorer; the controller can only read the project snapshot. All invited controller accounts can view the project report. The fixed `Project=brazil-tailscale-exit` filter excludes unrelated account spend. AWS does not support billing attribution for every charge, so untagged/unsupported charges and some credits, taxes, or Cost Explorer request fees can be absent. Consult AWS Billing for the full invoice. EBS volume tags are applied separately from the EC2 instance tags.

The collector activates the `Project` cost allocation tag when AWS makes it available; tag discovery and billing updates may each take 24 hours or longer. Earlier unallocated usage is not automatically recovered; use AWS Billing's cost allocation tag backfill if needed. If Cost Explorer is not enabled, enable it in the AWS Billing console and let the next scheduled report run. It cannot be disabled after enablement.

Cost Explorer charges $0.01 per query page. The collector normally makes one query daily (about $0.30 for 30 single-page runs), plus any pagination, retries, or manual runs. It does not query from page polling. The reporting Lambda, logs, and S3 storage incur their normal usage charges. To generate a report manually:

```sh
aws lambda invoke --profile brazil-exit --region sa-east-1 \
  --function-name "$(.tools/terraform -chdir=terraform output -raw cost_report_function)" \
  /tmp/brazil-cost-report-result.json
```

Run billing tests with `python3 -m unittest discover -s tests`, and browser logic tests with `node tests/test_web.mjs`. Stopping EC2 leaves the EBS disk, web controller, and cost reporting infrastructure in place; they can continue generating charges.

## Full teardown

Select **None** as the exit node on your devices first. Stopping EC2 retains its billed disk and the controller infrastructure. To remove the deployment, sign in to AWS, review the destroy plan, and disable the daily reporter before deleting its generated snapshot:

```sh
aws sso login --profile brazil-exit
terraform -chdir=terraform plan -destroy -out=teardown.tfplan
# Use your configured domain_prefix for the rule name:
aws events disable-rule --profile brazil-exit --region sa-east-1 \
  --name "brazil-exit-daily-costs-YOUR_DOMAIN_PREFIX"
aws s3 rm "s3://$(terraform -chdir=terraform output -raw cost_report_bucket)/current.json" \
  --profile brazil-exit --region sa-east-1
terraform -chdir=terraform apply teardown.tfplan
terraform -chdir=terraform state list
```

The snapshot is generated by Lambda and is not managed as a Terraform S3 object, so it must be removed before its bucket can be deleted. CloudFront deletion may take several minutes. Verify directly in AWS that the root disk, buckets, distribution, Lambda functions, scheduled rule, and log groups are gone; an empty Terraform state alone is insufficient. Previously accrued usage can appear in billing after teardown. Remove the offline server entry from the Tailscale admin console if desired.
