# PDF requirements review

Reviewed both PDFs from Personal Projects: the original 2-page Tailscale AWS Exit Node Manual and the 13-page expanded guide. Read all pages and inspected rendered pages. The PDFs are preserved as source references.

## Requirements and implementation

| Source | Requirement | Implementation / remaining action |
| --- | --- | --- |
| Original sections 1, 3; expanded sections 3-5 | São Paulo EC2, Tailscale installation, persistent IPv4/IPv6 forwarding | `aws/stack.yaml`; deploy with `--region sa-east-1` |
| Original section 4 | Terminal start/stop scripts with EC2 waiters | Added `scripts/power.sh on\|off i-INSTANCE_ID` |
| Expanded sections 3-4 | No inbound SSH, SSM administration, least privilege | Template has no inbound rules, SSM instance profile, one-instance start/stop policy |
| Expanded sections 4, 10 | Dynamic public IP, retained node identity across stop/start | No Elastic IP; EBS persists across stop/start; live verification required |
| Expanded sections 6-7 | Invited users, code/PKCE sign-in, JWT API, round button | Cognito admin-only signup, AppAuth, API scopes, configured native callbacks |
| Expanded section 6 | GET /state returns exitNodeReady:null | Implemented; EC2 running is not claimed to establish VPN readiness |
| Expanded section 8 | Optional desktop selection and fallback | Python agent; unit-tested; still requires tests on each real desktop |
| Expanded section 9 | Phones select/deselect exit node manually | UI explanation and stop confirmation; no mobile VPN integration requested |
| Expanded section 11 | Real-client smoke test and rollback | Requires deployed stack, enrolled tailnet node, invited users and devices |
| Expanded section 12 | Readiness probe, coordinated shutdown, alarms, auto-stop, LAN gateway | Explicit future upgrades, outside the starter deliverable |

## Source corrections and caveats

- Original section 2's less-than-$1.20 monthly total excludes EBS and assumes other costs are zero. Expanded section 10 corrects this. Do not use the old total as a budget quote. AWS confirms retained EBS billing while stopped: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/how-ec2-instance-stop-start-works.html
- Original start script labels EC2 running as exit node online. The new helper says EC2 running and asks for separate Tailscale validation.
- Expanded section 7 refers to a Linux authoring environment. This workspace is on macOS; iOS still needs Xcode and signing.
- The user pool disables public signup but does not enforce a maximum of two users. Operators must invite only the intended two accounts.
- Infrastructure deployment, billing alerts, public-subnet route verification, Tailscale login/route approval and user invitations remain account-specific setup. No deployment was performed.
- Preserve separate AWS and Tailscale identities: a Cognito invitation does not grant access to the tailnet.
- Visual issue: the expanded guide's architecture table on page 3 uses white header text on a pale background, reducing contrast. Source PDFs have not been edited.

## Helper use

```bash
bash scripts/power.sh on i-0123456789abcdef0
# Deselect Brazil in Tailscale on manually managed devices first.
bash scripts/power.sh off i-0123456789abcdef0
```

The helper uses existing AWS CLI credentials and fixes the region to sa-east-1. It does not change client routes or enroll the node.

## Terraform deployment adaptation

The user selected Terraform. Active infrastructure is now `terraform/`; `aws/stack.yaml` remains a source reference. Terraform packages `aws/index.py`, which the API regression tests execute. Deployment uses AWS SSO profiles and Terraform outputs populate the Flutter configuration. Account setup, enrollment and device smoke tests above still apply.
