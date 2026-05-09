---
title: "Privacy Policy"
date: 2026-05-09T00:00:00+00:00
author: "Viktor Barzin"
draft: false
description: "Privacy policy for viktorbarzin.me and self-hosted applications operated by Viktor Barzin."
tags: []
---

**Last updated:** 9 May 2026

This privacy policy applies to `viktorbarzin.me` and to applications operated by
Viktor Barzin (the "Operator") that connect to third-party services such as
Meta (Facebook / Instagram). It explains what personal data is collected, how
it is used, and the rights of the people it relates to ("you").

## Who this policy is about

The `viktorbarzin.me` infrastructure is a personal home-lab. The Operator is
the **only** end-user of the applications running on it. There is no public
sign-up, no shared multi-tenant service, no advertising, and no data sale.
Where this policy refers to "users" or "you", it refers to the Operator and,
incidentally, to anyone who happens to access the public marketing pages of
the website.

## Data collected

| Source | Data | Purpose |
|---|---|---|
| Website visitors (`viktorbarzin.me`) | IP address, user agent, request path, timestamp (server access logs only) | Operational diagnostics; logs rotated within 30 days |
| Meta APIs (Facebook, Instagram) | OAuth access token, IG user ID, page ID, IG handle, Page name | Allow the Operator's tools to publish content on his own social accounts |
| Operator's own photos | Image binaries fetched from the Operator's self-hosted Immich library | Re-encoded and delivered to the Operator's own messaging or social tooling |
| Application metrics | Aggregate request counts, latencies, error counts (Prometheus, Uptime Kuma) | Operational monitoring |

No third-party analytics or advertising trackers are loaded on the website.

## How the data is used

- Operating, maintaining, and debugging applications running for the
  Operator's personal use.
- Authenticating the Operator with Meta APIs in order to publish his own
  content to his own accounts.
- Providing the Operator with monitoring and alerting on his own
  infrastructure.

The data is not used for advertising, profiling, or sale of any kind.

## How the data is shared

- **Meta (Facebook / Instagram):** OAuth tokens are stored encrypted in
  HashiCorp Vault and used only to call the official Graph API on behalf of
  the Operator's own social accounts. Tokens are not shared with any third
  party.
- **Cloudflare:** Reverse-proxies website traffic. Cloudflare may retain
  request metadata under its own privacy policy
  (<https://www.cloudflare.com/privacypolicy/>).
- **No other sharing.** The Operator does not share, sell, rent, or otherwise
  disclose any personal data to advertisers, data brokers, analytics
  vendors, or any unrelated third parties.

## Data retention

- Web access logs: 30 days.
- Application monitoring metrics: up to 90 days, then aggregated.
- Meta OAuth tokens: retained for as long as the integration is active; deleted
  when the Operator disconnects the integration in the application UI or
  revokes the token at <https://www.facebook.com/settings?tab=business_tools>.
- Photos fetched from Immich are not retained beyond the time required to
  deliver them; on-disk caches are limited to a few megabytes per asset and
  are discarded when the underlying source asset is deleted from Immich.

## Your rights

Because the only intentional user of these applications is the Operator, the
following rights apply primarily to the Operator and, by reasonable extension,
to anyone whose personal data may inadvertently appear in the access logs:

- **Right of access** — request a copy of any personal data the Operator
  holds that relates to you.
- **Right of rectification** — request correction of inaccurate data.
- **Right of erasure** — request deletion of any personal data that relates
  to you.
- **Right to withdraw consent** — for OAuth-mediated access, revoke the token
  at the third-party provider (e.g.
  <https://www.facebook.com/settings?tab=business_tools>); the Operator will
  delete any cached copy on request.

## Children

The applications are not directed at children, do not knowingly collect any
data from children, and are not used by anyone under 13.

## Cookies

The website does not set tracking cookies. A small number of session and
preference cookies may be set by self-hosted applications behind Authentik
single-sign-on; these are first-party, are used only for session management,
and are deleted when the session ends.

## Changes to this policy

This policy may be updated to reflect changes in the way the applications
operate. The "Last updated" date at the top of this page reflects the most
recent revision.

## Contact

Email: `viktor@viktorbarzin.me`

If you believe your personal data has been processed by any application
operated under `viktorbarzin.me` and you would like it corrected or
deleted, please email the address above with the relevant details.
