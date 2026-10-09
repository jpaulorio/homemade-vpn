# Deployment status

**Current status (2026-10-09): torn down.** Terraform removed all 42 managed resources, and direct AWS checks found no project resources remaining. The entries below describe the historical deployment; their URLs are no longer active. See [teardown.md](teardown.md) and [teardown-verification.json](teardown-verification.json).

Terraform apply succeeded: 19 resources added, none changed or destroyed.

- Region: sa-east-1
- EC2: i-0f46ebc7f5ddc3901 (running)
- User pool: sa-east-1_vYYMDVdKH
- API: https://ymzt5vzji5.execute-api.sa-east-1.amazonaws.com
- Hosted sign-in: https://brazil-exit-093414603506.auth.sa-east-1.amazoncognito.com

Verified: Systems Manager online; cloud-init done; tailscaled active; IPv4 and IPv6 forwarding enabled; unauthenticated API request returns 401; deployed Lambda GET /state returns running with exitNodeReady:null. Android debug APK rebuilt with the deployed endpoint/client configuration.

Cognito invitations were requested successfully for both user-specified family accounts; both are enabled and require first-login password changes. Email receipt is not verified.

Pending: Tailscale tailnet enrollment, exit-route approval, first-login password setup, real-device sign-in and egress testing. EC2 is running and incurs AWS runtime charges.

## Browser controller and Tailscale update — 2026-10-08

The user confirmed Android login works and approved the exit node. SSM verified Tailscale BackendState Running, Self Online true, ExitNodeOption true, and no health errors. Node: `brazil-tailscale-exit`, address `100.109.78.109`. Device egress verification is still pending.

The browser controller uses a dedicated Cognito client, authorization code with PKCE and state validation, tab session storage, and authenticated API calls. Terraform adds private S3 hosting with CloudFront HTTPS and scoped API CORS. Browser assets are in `web/`; logic checks run with `node tests/test_web.mjs`.

Browser deployment completed: 12 resources added, 2 changed, 0 destroyed. URL: https://d345xhc3zo69sc.cloudfront.net/. Browser client: `4ltimcimh9pqvpnas496el7ubg`. CloudFront distribution: `E32FZ3BSMDZX85`. Verified live browser OAuth PKCE callback completed using the existing user session; authenticated GET /state displayed Server running. No live stop/start was performed during verification. Preview: `docs/browser-controller.png`.

## Cost reporting — 2026-10-08

Deployed 11 resources and updated 6 in place, with no deletions, for daily private cost reporting. The `Project costs` panel is available after sign-in at https://d345xhc3zo69sc.cloudfront.net/. The collector runs at 12:00 UTC daily and writes only fixed-project billing results to the private `brazil-exit-costs-53c80cad562f00c04d68321bd2/current.json` snapshot. Function: `brazil-exit-costs-brazil-exit-093414603506`. The controller can read the snapshot but cannot query Cost Explorer. EBS volume tags were added for cost attribution.

First invocation succeeded with `waiting_for_tag`: AWS has not yet exposed the Project tag in cost allocation. The collector will activate it when available. This is deliberately displayed without a zero-dollar total. Verified the pending state in the authenticated live browser. Daily/service charts, decimal billing aggregation, pagination, negative adjustments, and missing-data handling are tested; actual billing charts await AWS data. Preview: `docs/cost-dashboard.png`.

Costs are unblended, in USD, for the fixed project tag only. This is not a full account invoice: untagged/unsupported charges, taxes, credits, and reporting API fees can be absent. Reporting adds normally one $0.01 Cost Explorer query per day once attribution is active, plus pagination/retries, Lambda/logs/S3 usage. No budget notifications were configured.

The native iOS project has source and local Xcode is installed, but no signed native iPhone build has been delivered. Wife can currently use the browser controller from Safari plus the separate Tailscale iOS app.
