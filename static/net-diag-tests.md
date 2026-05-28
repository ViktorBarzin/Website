# net-diag test matrix

Walk these scenarios on a macOS laptop after deploying. The script is
purely read-only, so all probes are safe to run anywhere.

## Quick reference

| Scenario                                | Expected top-level verdict                                                    |
|-----------------------------------------|--------------------------------------------------------------------------------|
| Home Wi-Fi on `5G Tower`, healthy       | Link ✓ · DNS ✓ · Captive ✓ · v4 ✓ · v6 ✓ · Path ✓ · Perf ✓ · **Homelab ✓** · System ✓ |
| Cafe Wi-Fi, healthy                     | Link ✓ · DNS ✓ · Captive ✓ · v4 ✓ · v6 ✓/○ · Path ✓ · Perf ✓ · **Homelab ○ skipped** · System ✓ |
| Wi-Fi before captive sign-in            | Link ✓ · DNS ✓/⚠ · **Captive ✗** · v4 ⚠ · v6 ○ · Path ⚠ · Perf ⚠ · Homelab ○ · System ✓ |
| Airplane mode / no associated network   | **Link ✗** (no default route) · everything else skipped                       |
| Wi-Fi up, DHCP got address but no DNS   | Link ✓ · **DNS ✗** (system broken, public ✓) · Captive ⚠ · v4 ✓ (via IP) · ... |
| ISP DNS hijack (returns NXDOMAIN→ad page)| Link ✓ · **DNS ⚠** (slow or noanswer) · captive ✓ · …                         |
| IPv6 black-holed (RA but no transit)    | Link ✓ · DNS ✓ · v4 ✓ · **v6 ✗** (advertised but TCP fails)                    |
| On Headscale, off home network          | Homelab ○ (skipped — SSID ≠ `5G Tower`). Run with `--home` to force.          |
| Force homelab mode off home network     | `--home` enables homelab probes; **Homelab ✗** if Traefik LB unreachable      |
| Upload while online                     | Final line: `Report uploaded — expires in 1month` + PB URL                    |
| Upload while truly offline              | All probes fail/skip; `Upload failed` warning; report still printed locally   |

## Walk-through

### 1. Happy path on home Wi-Fi
```sh
curl -fsSL https://viktorbarzin.me/net-diag.sh | bash
```
Expected: every probe ✓ except possibly `Performance` (depends on momentary
RTT). Homelab section shows `Mode: HOME`, internal DNS resolves to
`10.0.20.200`, Traefik OK, HTTPS 200/301/302.

### 2. Happy path on cafe Wi-Fi
Same command. Expected: `Homelab ○ skipped` with reason
`SSID "<cafe>" ≠ "5G Tower"`. Everything else ✓.

### 3. Captive portal active
Connect to a hotspot whose portal hasn't been signed in yet. Expected:
`Captive portal ✗` with the body snippet showing the portal's HTML.
DNS/reachability often pass since portals usually DNAT all DNS to their
own resolver — those will look healthy at first glance, but the captive
verdict is the truth.

### 4. Airplane mode
Toggle airplane on, run script. Expected: `Link layer ✗ — no default
IPv4 route`, every subsequent probe `SKIP`. No upload attempt is sensible
(the `--upload` will fail with a timeout warning, which the script swallows
into a `⚠ Upload failed`).

### 5. Forced homelab probes
On any network with WireGuard / Headscale up:
```sh
curl -fsSL https://viktorbarzin.me/net-diag.sh | bash -s -- --home
```
Tests the homelab path explicitly. Useful for diagnosing "is the VPN
actually routing?"

### 6. Force-skip homelab
On home Wi-Fi, suppress homelab probes:
```sh
curl -fsSL https://viktorbarzin.me/net-diag.sh | bash -s -- --no-home
```

### 7. Upload roundtrip
```sh
curl -fsSL https://viktorbarzin.me/net-diag.sh | bash -s -- --upload
```
Expected final line:
```
Report uploaded — expires in 1month, decryption key is in the URL fragment:
   https://pb.viktorbarzin.me/?<id>#<base58-key>
```
Open the URL in a browser — PrivateBin's JS pulls the key from the
fragment (which the server never sees) and decrypts. The paste expires
after 30 days automatically.

### 8. No Python / no cryptography on laptop
If `--upload` is used without Python 3.7+ or the `cryptography` library,
the script prints a clear install hint to stderr and continues. The
terminal report is unaffected.

## Known limitations

- **macOS 14.4+ removed `airport` binary.** SSID is fetched from
  `networksetup -getairportnetwork` instead — that still works, but RSSI
  and BSSID will be blank on Sonoma+. The homelab-detection logic only
  needs SSID, so that's unaffected.
- **`pf` status** requires sudo. We don't ask for it — the probe just
  records "(requires sudo — skipped)".
- **No throughput test.** A real speedtest needs an outbound MB-class
  transfer; that's noisy and slow. We measure RTT and TLS handshake,
  which catch most "internet feels slow" cases.
- **IPv6 detection ignores link-local.** Only globally-routable addresses
  count as "has v6".
