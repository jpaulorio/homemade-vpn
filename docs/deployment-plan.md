# Terraform deployment plan

Historical pre-deployment plan (2026-10-08). Region: sa-east-1. See deployment-status.md for subsequent deployment and teardown.

The AWS-backed Terraform plan completed with **19 to add, 0 to change, 0 to destroy**. No resources have been created.

- One t3.micro EC2 instance; encrypted 8 GiB gp3 root disk and dynamic public IPv4.
- No inbound ports; IMDSv2 and Systems Manager administration.
- Cognito user pool, app client and Hosted UI domain; public signup disabled.
- JWT-protected API Gateway routes and Lambda controller permitted to start/stop this instance only.
- IAM instance/controller roles and 14-day Lambda log retention.

Uses existing VPC `vpc-3dfff55a`, public subnet `subnet-379b1c51`. Its active default Internet Gateway route passed preflight.

EC2 starts running upon deployment, and AWS charges begin on apply. Storage remains billed while stopped. Tailscale enrollment, exit-route approval and family-user invitations follow deployment.

A cached-provider checksum mismatch was resolved by quarantining the cache and reinstalling the signed provider against the unchanged lock file. The saved deployment plan was regenerated successfully with 19 creates and no changes or deletions.
