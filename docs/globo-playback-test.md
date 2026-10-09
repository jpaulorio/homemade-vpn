# AWS browser playback test — 2026-10-08

Tested the Palmeiras × Bahia live page in a browser actually running on EC2 `i-0f46ebc7f5ddc3901` in São Paulo. Accessed its virtual display through a loopback-only noVNC endpoint and an IAM-authenticated AWS Systems Manager port tunnel. No inbound security-group ports were added, and the instance type was not changed.

The Amazon Linux Firefox build loaded the page but lacked an AAC decoder and exceeded the initial browser memory cap. A second test used Google's official Chrome build with its sandbox intact and additional temporary swap. The user authorized sharing the server's estimated location with ge.globo.com for this test; Chrome's one-time location permission was selected.

After opening the live viewing options, TV Globo displayed the same message as on the Mac: “Esse jogo ao vivo não está disponível para a sua localização.” Screenshot: `globo-aws-test.jpg`. This demonstrates that simply running the browser on this AWS server did not resolve the restriction. It does not determine whether Globo rejected the IP classification, could not establish an acceptable device location, or applied another eligibility rule. Allowing location access does not establish that the browser returned valid coordinates.

The separate ge TV option was offered as free but required Conta Globo login. That authenticated alternative was not tested; no Globo credentials were entered. No working video or audio rebroadcast was established, and RustDesk was not installed on EC2.

Temporary browser, display and proxy services were stopped, test profiles and swap removed, and the two test package-install transactions reverted. The local AWS Session Manager plugin remains inside ignored `.tools/` only, with no system-wide installation.
