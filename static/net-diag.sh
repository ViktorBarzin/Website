#!/usr/bin/env bash
# net-diag.sh — macOS network diagnostics
#
# Hosted at:  https://viktorbarzin.me/net-diag.sh
# Source:     https://github.com/ViktorBarzin/Website/blob/master/static/net-diag.sh
#
# Run (terminal-only):
#   curl -fsSL https://viktorbarzin.me/net-diag.sh | bash
#
# Run + upload report to PrivateBin (best-effort, end-to-end encrypted, 1 month TTL):
#   curl -fsSL https://viktorbarzin.me/net-diag.sh | bash -s -- --upload
#
# Other flags: --quick, --home, --no-home, --version, --help
#
# The script is read-only — it runs `ifconfig`, `dig`, `ping`, etc., never
# mutates network state. Default output stays on the laptop; --upload sends
# an AES-256-GCM-encrypted copy to pb.viktorbarzin.me whose decryption key
# lives only in the printed URL fragment.

set -u
# Don't set -e — probes are expected to fail; we want to capture and report.

VERSION="0.1.0"
HOMELAB_SSIDS="${HOMELAB_SSIDS:-5G Tower|Barzini}"
PB_BASE="${PB_BASE:-https://pb.viktorbarzin.me}"
PB_EXPIRE="${PB_EXPIRE:-1month}"

# Anchor hosts for reachability tests.
PUBLIC_PING_V4="1.1.1.1 8.8.8.8 9.9.9.9"
PUBLIC_PING_V6="2606:4700:4700::1111 2001:4860:4860::8888"
TCP_443_HOSTS="cloudflare.com github.com apple.com"
TCP_80_CAPTIVE="captive.apple.com"
HOMELAB_PROBE_HOST="viktorbarzin.me"

# Defaults
DO_UPLOAD=0
QUICK=0
FORCE_HOME=""   # "" | "yes" | "no"

# ---------------------------------------------------------------- colors / io

if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
    C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_DIM=""; C_BLD=""; C_RST=""
else
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
    C_BLU=$'\033[34m'; C_DIM=$'\033[2m'
    C_BLD=$'\033[1m'; C_RST=$'\033[0m'
fi

usage() {
    cat <<'EOF'
net-diag — macOS network diagnostics

USAGE
    curl -fsSL https://viktorbarzin.me/net-diag.sh | bash [-s -- FLAGS]

FLAGS
    --upload    Upload the full report to PrivateBin (1 month TTL, E2E-encrypted)
    --quick     Skip slow probes (traceroute, perf timing)
    --home      Force homelab-aware probes (default: only when SSID matches)
    --no-home   Skip homelab-aware probes
    --version   Print version and exit
    -h, --help  This message
EOF
}

# ---------------------------------------------------------------- arg parser

while [ $# -gt 0 ]; do
    case "$1" in
        --upload)  DO_UPLOAD=1 ;;
        --quick)   QUICK=1 ;;
        --home)    FORCE_HOME="yes" ;;
        --no-home) FORCE_HOME="no" ;;
        --version) printf 'net-diag %s\n' "$VERSION"; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) printf '%sUnknown flag: %s%s\n' "$C_RED" "$1" "$C_RST" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

# ---------------------------------------------------------------- os guard

if [ "$(uname -s)" != "Darwin" ]; then
    printf '%snet-diag is macOS-only.%s\n' "$C_RED" "$C_RST" >&2
    printf 'Detected: %s\n' "$(uname -srm)" >&2
    exit 2
fi

# ---------------------------------------------------------------- timeout helper

# Wrap a command with a hard timeout. Uses BSD `timeout` if available (newer
# macOS), `gtimeout` (Homebrew coreutils), or a Perl fallback (Perl ships
# with macOS by default).
with_timeout() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@"
    else
        perl -e 'use POSIX; alarm shift; exec @ARGV or POSIX::_exit(127)' "$secs" "$@"
    fi
}

# ---------------------------------------------------------------- report state

# Each probe sets these before run_probe() collects them.
PROBE_VERDICT=""
PROBE_REASON=""
PROBE_DETAIL=""

# Collected sections, one per probe. Stored as a packed string with a unique
# separator so bash 3.2 (macOS default) can split it later without arrays of
# arrays. Format per row:  NAME|VERDICT|REASON\nDETAIL\n\x1f
REPORT_ROWS=""
SEP_ROW=$'\x1f'   # ASCII Unit Separator

# Environment captured during probe_link, reused later.
DETECTED_IFACE=""
DETECTED_GW=""
DETECTED_SSID=""
HAS_IPV4=0
HAS_IPV6=0

# Banner
START_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
HOSTNAME_SHORT=$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || hostname)
MACOS_VER=$(sw_vers -productVersion 2>/dev/null || uname -r)

print_banner() {
    printf '%s%s━━━━━ net-diag %s ━━━━━%s\n' "$C_BLD" "$C_BLU" "$VERSION" "$C_RST"
    printf '%sStarted:%s %s   %sHost:%s %s   %smacOS:%s %s\n\n' \
        "$C_DIM" "$C_RST" "$START_TS" \
        "$C_DIM" "$C_RST" "$HOSTNAME_SHORT" \
        "$C_DIM" "$C_RST" "$MACOS_VER"
}

verdict_color() {
    case "$1" in
        PASS) printf '%s' "$C_GRN" ;;
        WARN) printf '%s' "$C_YEL" ;;
        FAIL) printf '%s' "$C_RED" ;;
        SKIP) printf '%s' "$C_DIM" ;;
        *)    printf '%s' "$C_RST" ;;
    esac
}

verdict_glyph() {
    case "$1" in
        PASS) printf '✓' ;;
        WARN) printf '⚠' ;;
        FAIL) printf '✗' ;;
        SKIP) printf '○' ;;
        *)    printf '·' ;;
    esac
}

run_probe() {
    local name="$1"
    local fn="$2"

    PROBE_VERDICT="PASS"
    PROBE_REASON=""
    PROBE_DETAIL=""

    "$fn" || true

    local color glyph
    color=$(verdict_color "$PROBE_VERDICT")
    glyph=$(verdict_glyph "$PROBE_VERDICT")

    printf '%s%s %-26s%s %s\n' "$color" "$glyph" "$name" "$C_RST" \
        "${PROBE_REASON:-(no detail)}"

    REPORT_ROWS="${REPORT_ROWS}${name}|${PROBE_VERDICT}|${PROBE_REASON}
${PROBE_DETAIL}
${SEP_ROW}"
}

# Per-run tempdir for parallel-probe results. Set up in main().
RUN_TMPDIR=""

# Translate a probe name into a safe tempfile path under $RUN_TMPDIR.
_probe_tmpfile() {
    printf '%s/%s' "$RUN_TMPDIR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' _)"
}

# Fork a probe in a subshell. Globals set by probe_link (DETECTED_IFACE etc.)
# are inherited via the env. The subshell writes verdict, reason, and detail
# to a per-probe tempfile so the parent can collect them in canonical order
# after `wait`.
dispatch_probe() {
    local name="$1" fn="$2"
    local f
    f=$(_probe_tmpfile "$name")
    (
        PROBE_VERDICT="PASS"
        PROBE_REASON=""
        PROBE_DETAIL=""
        "$fn" || true
        {
            printf '%s\n' "$PROBE_VERDICT"
            printf '%s\n' "$PROBE_REASON"
            printf '%s' "$PROBE_DETAIL"
        } > "$f"
    ) &
}

# Read a dispatched probe's tempfile, print its verdict line, and append
# it to REPORT_ROWS — exactly mirroring run_probe()'s side effects, but
# sourced from disk instead of in-process state.
collect_probe() {
    local name="$1"
    local f
    f=$(_probe_tmpfile "$name")

    local verdict reason detail
    if [ ! -s "$f" ]; then
        verdict="FAIL"
        reason="probe did not finish (subshell crashed or timed out)"
        detail=""
    else
        verdict=$(sed -n 1p "$f")
        reason=$(sed -n 2p "$f")
        detail=$(sed -n '3,$p' "$f")
    fi

    local color glyph
    color=$(verdict_color "$verdict")
    glyph=$(verdict_glyph "$verdict")
    printf '%s%s %-26s%s %s\n' "$color" "$glyph" "$name" "$C_RST" \
        "${reason:-(no detail)}"

    REPORT_ROWS="${REPORT_ROWS}${name}|${verdict}|${reason}
${detail}
${SEP_ROW}"
}

# ---------------------------------------------------------------- probe: link

probe_link() {
    local route_out iface gw
    route_out=$(with_timeout 3 route -n get default 2>/dev/null || true)
    iface=$(printf '%s\n' "$route_out" | awk -F': ' '/interface:/{gsub(/^ +/,"",$2); print $2; exit}')
    gw=$(printf '%s\n' "$route_out" | awk -F': ' '/gateway:/{gsub(/^ +/,"",$2); print $2; exit}')

    DETECTED_IFACE="$iface"
    DETECTED_GW="$gw"

    if [ -z "$iface" ]; then
        PROBE_VERDICT="FAIL"
        PROBE_REASON="no default IPv4 route — link layer down or no DHCP lease"
        PROBE_DETAIL=$(printf 'route output:\n%s' "$route_out")
        return
    fi

    local ipv4 ipv6 mtu
    ipv4=$(with_timeout 3 ifconfig "$iface" 2>/dev/null | awk '/^[[:space:]]*inet /{print $2; exit}')
    ipv6=$(with_timeout 3 ifconfig "$iface" 2>/dev/null | awk '/^[[:space:]]*inet6 /{ if ($2 !~ /^fe80/) {print $2; exit} }')
    mtu=$(with_timeout 3 ifconfig "$iface" 2>/dev/null | awk '/mtu / { for (i=1;i<=NF;i++) if ($i=="mtu") print $(i+1) }' | head -1)

    [ -n "$ipv4" ] && HAS_IPV4=1
    [ -n "$ipv6" ] && HAS_IPV6=1

    # Wi-Fi info: SSID, RSSI, channel. Multiple sources because Apple keeps
    # deprecating things — try the modern path first, fall back to airport(8).
    local ssid="" bssid="" rssi="" rate="" chan=""
    if printf '%s' "$iface" | grep -qE '^en[0-9]+$'; then
        ssid=$(with_timeout 2 networksetup -getairportnetwork "$iface" 2>/dev/null \
               | awk -F': ' '/Current Wi-Fi Network/{print $2}')

        local airport_bin=/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport
        if [ -x "$airport_bin" ]; then
            local ap
            ap=$(with_timeout 3 "$airport_bin" -I 2>/dev/null || true)
            [ -z "$ssid" ] && ssid=$(printf '%s\n' "$ap" | awk -F': ' '/^[[:space:]]*SSID:/{sub(/^[[:space:]]+/,"",$2); print $2}')
            bssid=$(printf '%s\n' "$ap" | awk -F': ' '/^[[:space:]]*BSSID:/{sub(/^[[:space:]]+/,"",$2); print $2}')
            rssi=$(printf '%s\n' "$ap" | awk -F': ' '/agrCtlRSSI:/{sub(/^[[:space:]]+/,"",$2); print $2}')
            rate=$(printf '%s\n' "$ap" | awk -F': ' '/lastTxRate:/{sub(/^[[:space:]]+/,"",$2); print $2}')
            chan=$(printf '%s\n' "$ap" | awk -F': ' '/channel:/{sub(/^[[:space:]]+/,"",$2); print $2}')
        fi
    fi
    DETECTED_SSID="$ssid"

    if [ -z "$ipv4" ]; then
        PROBE_VERDICT="FAIL"
        PROBE_REASON="$iface has no IPv4 address (DHCP failed?)"
    elif [ -z "$gw" ]; then
        PROBE_VERDICT="FAIL"
        PROBE_REASON="no default gateway on $iface"
    else
        PROBE_VERDICT="PASS"
        if [ -n "$ssid" ]; then
            PROBE_REASON="$iface on \"$ssid\" — $ipv4 → $gw"
        else
            PROBE_REASON="$iface — $ipv4 → $gw"
        fi
    fi

    {
        printf '  Interface:  %s\n' "$iface"
        printf '  IPv4:       %s\n' "${ipv4:-(none)}"
        printf '  IPv6:       %s\n' "${ipv6:-(none — link-local only or disabled)}"
        printf '  Gateway:    %s\n' "${gw:-(none)}"
        printf '  MTU:        %s\n' "${mtu:-?}"
        [ -n "$ssid" ]  && printf '  SSID:       %s\n' "$ssid"
        [ -n "$bssid" ] && printf '  BSSID:      %s\n' "$bssid"
        [ -n "$rssi" ]  && printf '  RSSI:       %s dBm\n' "$rssi"
        [ -n "$rate" ]  && printf '  Link rate:  %s Mbps\n' "$rate"
        [ -n "$chan" ]  && printf '  Channel:    %s\n' "$chan"
    } > /tmp/.netdiag.$$.detail
    PROBE_DETAIL=$(cat /tmp/.netdiag.$$.detail)
    rm -f /tmp/.netdiag.$$.detail
}

# ---------------------------------------------------------------- probe: DNS

probe_dns() {
    if [ -z "$DETECTED_IFACE" ]; then
        PROBE_VERDICT="SKIP"
        PROBE_REASON="no interface — skipped"
        return
    fi

    local scutil_out
    scutil_out=$(with_timeout 3 scutil --dns 2>/dev/null || true)

    # Parse every nameserver from every resolver scope. macOS exposes one or
    # more "resolver #N" blocks; resolver #1 is the default scope, higher
    # numbers route per-domain (VPN-pushed, search-domain split-horizon, etc.).
    # We collect rows of "scope|domain|ip" so we can probe each entry.
    local resolvers_raw
    resolvers_raw=$(printf '%s\n' "$scutil_out" | awk '
        /^resolver #/ {
            scope = $2
            domain = ""
            next
        }
        /^[[:space:]]*domain[[:space:]]*:/ {
            domain = $3
            next
        }
        /^[[:space:]]*nameserver\[[0-9]+\][[:space:]]*:/ {
            ip = $3
            # Strip an IPv6 zone-id (e.g., fe80::1%en0) — dig handles the
            # bare address fine; keeping %zone confuses some resolver libs.
            sub(/%.*$/, "", ip)
            print scope "|" domain "|" ip
        }
    ')

    local control="cloudflare.com"
    local detail=""
    detail="${detail}  System resolvers (from scutil --dns):\n"
    if [ -z "$resolvers_raw" ]; then
        detail="${detail}    (none configured!)\n"
    fi

    # Probe each system-configured resolver directly and tag a verdict per IP.
    # Tracks how many of the resolvers in scope #1 (the default route) answered;
    # a scope-#1 outage is the actionable "DNS broken" signal — secondary scopes
    # only matter for VPN-routed names.
    local sys1_total=0 sys1_ok=0
    local OLDIFS="$IFS"
    IFS=$'\n'
    local row
    for row in $resolvers_raw; do
        IFS='|' read -r scope domain ip <<EOF
$row
EOF
        local ms
        ms=$(time_dns_query "$ip" "$control") || true
        local domain_hint=""
        [ -n "$domain" ] && [ "$domain" != "(null)" ] && domain_hint=" (domain=${domain})"
        detail="${detail}    ${scope} @${ip}${domain_hint}: $(fmt_dns_result "$ms")\n"
        if [ "$scope" = "#1" ]; then
            sys1_total=$((sys1_total + 1))
            case "$ms" in [0-9]*) sys1_ok=$((sys1_ok + 1)) ;; esac
        fi
    done
    IFS="$OLDIFS"

    # The aggregate "ask the system default and see who answers" check —
    # useful because macOS may try resolvers in an order we can't fully see.
    detail="${detail}\n  A lookup via macOS default chain (whatever scutil picks):\n"
    local sys_ms
    sys_ms=$(time_dns_query "" "$control") || true
    detail="${detail}    system: $(fmt_dns_result "$sys_ms")\n"

    # Public-resolver control: tells us whether DNS-over-UDP/53 itself works
    # past the local network, independent of the system-configured resolvers.
    detail="${detail}\n  A lookup via public anchors (control):\n"
    local public_ok=0 public_total=0
    local r
    for r in 1.1.1.1 8.8.8.8 9.9.9.9; do
        public_total=$((public_total + 1))
        local pms
        pms=$(time_dns_query "$r" "$control") || true
        detail="${detail}    @${r}: $(fmt_dns_result "$pms")\n"
        case "$pms" in [0-9]*) public_ok=$((public_ok + 1)) ;; esac
    done

    # Verdict precedence:
    #   1. Nothing answers at all (system + public)          → FAIL — no DNS path.
    #   2. System resolvers all dead, public ones OK         → FAIL — local DNS broken.
    #   3. Some scope-#1 resolvers dead, others OK           → WARN — partial outage,
    #                                                          name the bad ones.
    #   4. Public dead, system OK                            → WARN — captive / fw blocks 53.
    #   5. System resolver slow (>500ms)                     → WARN — hijack/overload.
    #   6. Everything green                                  → PASS.
    local sys_ok=0
    case "$sys_ms" in [0-9]*) sys_ok=1 ;; esac

    if [ "$public_ok" = 0 ] && [ "$sys1_ok" = 0 ] && [ "$sys_ok" = 0 ]; then
        PROBE_VERDICT="FAIL"
        PROBE_REASON="no DNS resolver answered (system + public both dead)"
    elif [ "$sys1_total" -gt 0 ] && [ "$sys1_ok" = 0 ]; then
        PROBE_VERDICT="FAIL"
        PROBE_REASON="all ${sys1_total} default-scope DNS server(s) failing; public resolvers OK — fix DHCP/local DNS"
    elif [ "$sys1_total" -gt 1 ] && [ "$sys1_ok" -lt "$sys1_total" ]; then
        # Name the failing resolvers so the user knows which one to remove/replace.
        local failing
        failing=$(printf '%s\n' "$resolvers_raw" | awk -F'|' '$1=="#1"{print $3}' | while read -r ip; do
            ms=$(time_dns_query "$ip" "$control") 2>/dev/null
            case "$ms" in [0-9]*) : ;; *) printf '%s ' "$ip" ;; esac
        done | sed 's/ $//')
        PROBE_VERDICT="WARN"
        PROBE_REASON="${sys1_ok}/${sys1_total} default resolvers answering — failing: ${failing}"
    elif [ "$public_ok" = 0 ]; then
        PROBE_VERDICT="WARN"
        PROBE_REASON="system OK but all public resolvers blocked — captive portal / UDP-53 firewall?"
    elif [ "$sys_ok" = 1 ] && [ "$sys_ms" -gt 500 ] 2>/dev/null; then
        PROBE_VERDICT="WARN"
        PROBE_REASON="system resolver slow (${sys_ms} ms) — possibly hijacked or overloaded"
    else
        PROBE_VERDICT="PASS"
        PROBE_REASON="all ${sys1_total} default + ${public_ok}/${public_total} public resolvers answering"
    fi

    PROBE_DETAIL=$(printf '%b' "$detail")
}

# Time a single A-lookup. If $1 is empty, use system default; otherwise @$1.
# Print ms (integer) on success, "fail" on failure, "timeout" on timeout.
time_dns_query() {
    local resolver="$1" name="$2"
    local out rc
    if [ -n "$resolver" ]; then
        out=$(with_timeout 3 dig +tries=1 +time=2 +stats "@${resolver}" "$name" A 2>/dev/null || true)
    else
        out=$(with_timeout 3 dig +tries=1 +time=2 +stats "$name" A 2>/dev/null || true)
    fi
    rc=$?
    if [ -z "$out" ]; then
        printf 'timeout'
        return 1
    fi
    # dig prints e.g. ";; Query time: 12 msec"
    local ms
    ms=$(printf '%s\n' "$out" | awk -F'[: ]+' '/Query time/{print $4; exit}')
    if [ -z "$ms" ]; then
        printf 'fail'
        return 1
    fi
    # Check ANSWER count was non-zero.
    local ans
    ans=$(printf '%s\n' "$out" | awk -F'[, ]+' '/status: NOERROR/{ for(i=1;i<=NF;i++) if($i=="ANSWER:") print $(i+1) }')
    if [ -z "$ans" ] || [ "$ans" = "0" ]; then
        printf 'noanswer'
        return 1
    fi
    printf '%s' "$ms"
}

fmt_dns_result() {
    case "$1" in
        [0-9]*) printf '%s ms' "$1" ;;
        timeout) printf '%stimeout%s' "$C_RED" "$C_RST" ;;
        noanswer) printf '%sno answer%s' "$C_YEL" "$C_RST" ;;
        *) printf '%sfail%s' "$C_RED" "$C_RST" ;;
    esac
}

# ---------------------------------------------------------------- probe: reachability v4

probe_reach_v4() {
    if [ "$HAS_IPV4" = 0 ]; then
        PROBE_VERDICT="SKIP"; PROBE_REASON="no IPv4 — skipped"
        return
    fi

    local detail=""
    local h ok_count=0 total=0

    # 1. Gateway ping (should always succeed if link is up)
    detail="${detail}  Gateway ping (${DETECTED_GW}):\n"
    if [ -n "$DETECTED_GW" ]; then
        if ping_check 4 "$DETECTED_GW" 2; then
            detail="${detail}    ${C_GRN}reachable${C_RST}\n"
        else
            detail="${detail}    ${C_RED}unreachable${C_RST} — local link issue\n"
        fi
    else
        detail="${detail}    (no gateway)\n"
    fi

    # 2. Public IPv4 pings
    detail="${detail}\n  Public ping (IPv4):\n"
    for h in $PUBLIC_PING_V4; do
        total=$((total + 1))
        if ping_check 4 "$h" 2; then
            ok_count=$((ok_count + 1))
            detail="${detail}    ${h}: ${C_GRN}up${C_RST}\n"
        else
            detail="${detail}    ${h}: ${C_RED}timeout${C_RST}\n"
        fi
    done

    # 3. TCP 443 connectivity (sometimes ICMP is blocked but TCP works)
    detail="${detail}\n  TCP/443 handshake:\n"
    local tcp_ok=0 tcp_total=0
    for h in $TCP_443_HOSTS; do
        tcp_total=$((tcp_total + 1))
        if tcp_check "$h" 443 3; then
            tcp_ok=$((tcp_ok + 1))
            detail="${detail}    ${h}:443 ${C_GRN}OK${C_RST}\n"
        else
            detail="${detail}    ${h}:443 ${C_RED}FAIL${C_RST}\n"
        fi
    done

    if [ "$ok_count" = 0 ] && [ "$tcp_ok" = 0 ]; then
        PROBE_VERDICT="FAIL"
        PROBE_REASON="no public IPv4 reachability — internet path broken"
    elif [ "$ok_count" = 0 ] && [ "$tcp_ok" -gt 0 ]; then
        PROBE_VERDICT="WARN"
        PROBE_REASON="ICMP blocked but TCP/443 works (${tcp_ok}/${tcp_total} hosts)"
    elif [ "$ok_count" -lt "$total" ] || [ "$tcp_ok" -lt "$tcp_total" ]; then
        PROBE_VERDICT="WARN"
        PROBE_REASON="partial reachability — ping ${ok_count}/${total}, TCP ${tcp_ok}/${tcp_total}"
    else
        PROBE_VERDICT="PASS"
        PROBE_REASON="full IPv4 reachability — ping ${ok_count}/${total}, TCP ${tcp_ok}/${tcp_total}"
    fi
    PROBE_DETAIL=$(printf '%b' "$detail")
}

ping_check() {
    local family="$1" host="$2" timeout_s="$3"
    local cmd=ping
    [ "$family" = 6 ] && cmd=ping6
    # macOS ping: -c count, -W is per-packet timeout in ms, -t total deadline in s.
    with_timeout "$((timeout_s + 1))" "$cmd" -c 1 -W "$((timeout_s * 1000))" -t "$timeout_s" "$host" >/dev/null 2>&1
}

tcp_check() {
    local host="$1" port="$2" timeout_s="$3"
    with_timeout "$((timeout_s + 1))" nc -z -G "$timeout_s" "$host" "$port" >/dev/null 2>&1
}

# ---------------------------------------------------------------- probe: IPv6

probe_v6() {
    if [ "$HAS_IPV6" = 0 ]; then
        PROBE_VERDICT="SKIP"
        PROBE_REASON="no global IPv6 address — disabled or not advertised"
        return
    fi

    local detail=""
    local h ok_count=0 total=0
    detail="${detail}  Public ping (IPv6):\n"
    for h in $PUBLIC_PING_V6; do
        total=$((total + 1))
        if ping_check 6 "$h" 2; then
            ok_count=$((ok_count + 1))
            detail="${detail}    ${h}: ${C_GRN}up${C_RST}\n"
        else
            detail="${detail}    ${h}: ${C_RED}timeout${C_RST}\n"
        fi
    done

    # Test that AAAA-resolved name actually opens a TCP/443 connection — the
    # classic "v6 routes look fine but actually black-holed" silent failure.
    detail="${detail}\n  TCP/443 over v6:\n"
    local v6_ok=0
    for h in cloudflare.com google.com; do
        if with_timeout 5 curl -fsSL -6 --connect-timeout 3 -o /dev/null "https://${h}" 2>/dev/null; then
            v6_ok=$((v6_ok + 1))
            detail="${detail}    ${h}: ${C_GRN}OK${C_RST}\n"
        else
            detail="${detail}    ${h}: ${C_RED}FAIL${C_RST}\n"
        fi
    done

    if [ "$ok_count" = 0 ] && [ "$v6_ok" = 0 ]; then
        PROBE_VERDICT="FAIL"
        PROBE_REASON="IPv6 advertised but black-holed — apps will silently hang on AAAA"
    elif [ "$v6_ok" = 0 ]; then
        PROBE_VERDICT="WARN"
        PROBE_REASON="ICMPv6 OK but TCP fails — partial v6 reach"
    else
        PROBE_VERDICT="PASS"
        PROBE_REASON="v6 ping ${ok_count}/${total}, TCP/443 ${v6_ok}/2"
    fi
    PROBE_DETAIL=$(printf '%b' "$detail")
}

# ---------------------------------------------------------------- probe: captive portal

probe_captive() {
    if [ "$HAS_IPV4" = 0 ]; then
        PROBE_VERDICT="SKIP"; PROBE_REASON="no IPv4 — skipped"
        return
    fi

    local body http_status
    body=$(with_timeout 5 curl -sS --max-time 4 -o - -w 'HTTPSTATUS:%{http_code}' \
        "http://${TCP_80_CAPTIVE}/hotspot-detect.html" 2>/dev/null || true)
    http_status=$(printf '%s\n' "$body" | sed -n 's/.*HTTPSTATUS:\([0-9]*\).*/\1/p' | tail -1)
    body=$(printf '%s\n' "$body" | sed 's/HTTPSTATUS:[0-9]*$//')

    # Apple's canonical response is exactly "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>\n"
    if [ "$http_status" = "200" ] && printf '%s' "$body" | grep -q '<BODY>Success</BODY>'; then
        PROBE_VERDICT="PASS"
        PROBE_REASON="no captive portal (Apple probe returned canonical Success)"
        PROBE_DETAIL="  Endpoint:  http://${TCP_80_CAPTIVE}/hotspot-detect.html"$'\n'"  Status:    200 + canonical body"
    elif [ -z "$http_status" ]; then
        PROBE_VERDICT="WARN"
        PROBE_REASON="captive probe timed out — may be on portal or upstream blocked"
        PROBE_DETAIL="  Endpoint:  http://${TCP_80_CAPTIVE}/hotspot-detect.html"$'\n'"  Status:    (no response)"
    else
        PROBE_VERDICT="FAIL"
        PROBE_REASON="captive portal intercepting traffic (HTTP ${http_status}, body diverged)"
        local snip
        snip=$(printf '%s' "$body" | head -c 200 | tr -d '\r\n' )
        PROBE_DETAIL=$(printf '  Endpoint:  http://%s/hotspot-detect.html\n  Status:    %s\n  Body[200]: %s' \
            "$TCP_80_CAPTIVE" "$http_status" "$snip")
    fi
}

# ---------------------------------------------------------------- probe: path

probe_path() {
    if [ "$QUICK" = 1 ]; then
        PROBE_VERDICT="SKIP"; PROBE_REASON="--quick mode"
        return
    fi
    if [ "$HAS_IPV4" = 0 ]; then
        PROBE_VERDICT="SKIP"; PROBE_REASON="no IPv4 — skipped"
        return
    fi

    local target=1.1.1.1
    local out
    out=$(with_timeout 12 traceroute -n -q 1 -w 2 -m 12 "$target" 2>&1 || true)

    if [ -z "$out" ]; then
        PROBE_VERDICT="WARN"
        PROBE_REASON="traceroute produced no output"
        PROBE_DETAIL=""
        return
    fi

    # Count hops and look for full asterisk hops (likely blackholes).
    local hops asterisk_hops final_reached
    hops=$(printf '%s\n' "$out" | grep -cE '^[[:space:]]*[0-9]+')
    asterisk_hops=$(printf '%s\n' "$out" | awk '/^[[:space:]]*[0-9]+/ && /\* \* \*/' | wc -l | tr -d ' ')
    final_reached=$(printf '%s\n' "$out" | tail -1 | grep -E "^[[:space:]]*[0-9]+.*${target}" | wc -l | tr -d ' ')

    if [ "$final_reached" = "1" ]; then
        PROBE_VERDICT="PASS"
        PROBE_REASON="reached ${target} in ${hops} hops"
    elif [ "$asterisk_hops" -gt 3 ]; then
        PROBE_VERDICT="WARN"
        PROBE_REASON="${asterisk_hops} silent hops out of ${hops} — ICMP rate-limit common, but check"
    else
        PROBE_VERDICT="WARN"
        PROBE_REASON="${target} not reached within ${hops} hops"
    fi
    PROBE_DETAIL=$(printf '  Target: %s\n%s' "$target" "$out")
}

# ---------------------------------------------------------------- probe: perf

probe_perf() {
    if [ "$QUICK" = 1 ]; then
        PROBE_VERDICT="SKIP"; PROBE_REASON="--quick mode"
        return
    fi
    if [ "$HAS_IPV4" = 0 ]; then
        PROBE_VERDICT="SKIP"; PROBE_REASON="no IPv4 — skipped"
        return
    fi

    # 5-packet ping for jitter/loss; 1-byte HTTPS RTT to estimate TLS RTT.
    local pingstats
    pingstats=$(with_timeout 8 ping -c 5 -i 0.5 -W 1500 1.1.1.1 2>/dev/null | tail -2)
    local loss avg
    loss=$(printf '%s\n' "$pingstats" | awk -F'[ ,]+' '/packet loss/{ for(i=1;i<=NF;i++) if($i ~ /%/) print $i; exit }')
    avg=$(printf '%s\n' "$pingstats" | awk -F'[ /]+' '/round-trip/{print $7}')

    local curlt
    curlt=$(with_timeout 6 curl -sS -o /dev/null -w 'dns=%{time_namelookup} conn=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total}' \
        --max-time 5 https://cloudflare.com 2>/dev/null || true)

    if [ -z "$avg" ] && [ -z "$curlt" ]; then
        PROBE_VERDICT="FAIL"
        PROBE_REASON="no perf samples completed"
    elif [ -n "$avg" ]; then
        PROBE_VERDICT="PASS"
        PROBE_REASON="avg RTT ${avg} ms, loss ${loss:-?}"
    else
        PROBE_VERDICT="WARN"
        PROBE_REASON="ICMP blocked; HTTPS handshake measured"
    fi
    PROBE_DETAIL=$(printf '  ICMP (1.1.1.1, 5 pkt):\n%s\n  HTTPS handshake (cloudflare.com): %s' \
        "$pingstats" "${curlt:-(no output)}")
}

# ---------------------------------------------------------------- probe: homelab

probe_homelab() {
    local on_home=0
    local matched_ssid=""
    if [ "$FORCE_HOME" = "yes" ]; then
        on_home=1
        matched_ssid="(forced via --home)"
    elif [ "$FORCE_HOME" = "no" ]; then
        on_home=0
    else
        # HOMELAB_SSIDS is a pipe-delimited list of SSIDs that all count as
        # "I'm at one of Viktor's homes" (London + Sofia). Match any.
        local OLDIFS="$IFS"
        IFS='|'
        local s
        for s in $HOMELAB_SSIDS; do
            if [ "$DETECTED_SSID" = "$s" ]; then
                on_home=1
                matched_ssid="$s"
                break
            fi
        done
        IFS="$OLDIFS"
    fi

    if [ "$on_home" = 0 ]; then
        PROBE_VERDICT="SKIP"
        if [ -n "$DETECTED_SSID" ]; then
            PROBE_REASON="SSID \"$DETECTED_SSID\" not in homelab list (${HOMELAB_SSIDS}) — skipped"
        else
            PROBE_REASON="not on Wi-Fi — homelab probes skipped"
        fi
        return
    fi

    local detail=""
    detail="${detail}  Mode: ${C_BLD}HOME${C_RST} (matched: ${matched_ssid})\n\n"

    # 1. Internal DNS should resolve viktorbarzin.me to 10.0.20.200 (Traefik LB).
    local internal_ip
    internal_ip=$(with_timeout 3 dig +short +tries=1 +time=2 "${HOMELAB_PROBE_HOST}" A 2>/dev/null | head -1)
    detail="${detail}  Internal DNS for ${HOMELAB_PROBE_HOST}: ${internal_ip:-(none)}\n"

    # 2. Reachability of internal Traefik (10.0.20.200) on 443.
    local traefik_ok="✗"
    if tcp_check 10.0.20.200 443 3; then traefik_ok="${C_GRN}OK${C_RST}"; else traefik_ok="${C_RED}FAIL${C_RST}"; fi
    detail="${detail}  Traefik internal LB (10.0.20.200:443): ${traefik_ok}\n"

    # 3. HTTPS to viktorbarzin.me (covers TLS, ingress chain, end-to-end).
    local ext_status
    ext_status=$(with_timeout 6 curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
        "https://${HOMELAB_PROBE_HOST}/" 2>/dev/null || echo "fail")
    detail="${detail}  HTTPS https://${HOMELAB_PROBE_HOST}/: ${ext_status}\n"

    # 4. Cloudflare path probe (we should also reach the public CF-fronted edge).
    local cf_status
    cf_status=$(with_timeout 6 curl -sS -o /dev/null -w '%{http_code}' --max-time 5 --resolve "${HOMELAB_PROBE_HOST}:443:104.16.0.1" \
        "https://${HOMELAB_PROBE_HOST}/" 2>/dev/null || echo "fail")
    detail="${detail}  HTTPS via Cloudflare edge (104.16.0.1): ${cf_status}\n"

    # Verdict.
    if [ -z "$internal_ip" ]; then
        PROBE_VERDICT="FAIL"
        PROBE_REASON="internal DNS lookup failed for ${HOMELAB_PROBE_HOST}"
    elif [ "$traefik_ok" != "${C_GRN}OK${C_RST}" ]; then
        PROBE_VERDICT="FAIL"
        PROBE_REASON="Traefik LB unreachable — homelab L3 path broken"
    elif [ "$ext_status" != "200" ] && [ "$ext_status" != "301" ] && [ "$ext_status" != "302" ]; then
        PROBE_VERDICT="WARN"
        PROBE_REASON="reached LB but HTTPS to ${HOMELAB_PROBE_HOST} returned ${ext_status}"
    else
        PROBE_VERDICT="PASS"
        PROBE_REASON="homelab reachable end-to-end (internal + CF edge)"
    fi
    PROBE_DETAIL=$(printf '%b' "$detail")
}

# ---------------------------------------------------------------- probe: system

probe_system() {
    local detail=""

    # VPN / Tailscale / Headscale
    local tailscale_state=""
    if command -v tailscale >/dev/null 2>&1; then
        tailscale_state=$(with_timeout 3 tailscale status --json 2>/dev/null | grep -E '"BackendState"' | head -1 || true)
    fi
    detail="${detail}  Tailscale/Headscale: ${tailscale_state:-not installed or not running}\n"

    # macOS pf (packet filter) state
    local pf_state
    pf_state=$(with_timeout 2 sudo -n pfctl -s info 2>/dev/null | head -1 || true)
    if [ -z "$pf_state" ]; then
        pf_state="(requires sudo — skipped)"
    fi
    detail="${detail}  pf:                  ${pf_state}\n"

    # Proxy environment variables
    local proxies=""
    local v
    for v in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY no_proxy ALL_PROXY; do
        if [ -n "${!v:-}" ]; then
            proxies="${proxies}\n    ${v}=${!v}"
        fi
    done
    if [ -n "$proxies" ]; then
        detail="${detail}  Proxy env vars set:${proxies}\n"
    else
        detail="${detail}  Proxy env vars:      (none)\n"
    fi

    # System DNS settings via networksetup (catches manual overrides)
    if [ -n "$DETECTED_IFACE" ]; then
        local ns_dns
        ns_dns=$(with_timeout 2 networksetup -getdnsservers "$(networksetup_service_for_iface "$DETECTED_IFACE")" 2>/dev/null \
                  | tr '\n' ',' | sed 's/,$//')
        detail="${detail}  Manual DNS overrides: ${ns_dns:-(none)}\n"
    fi

    PROBE_VERDICT="PASS"
    PROBE_REASON="captured (advisory — no failures here are fatal)"
    PROBE_DETAIL=$(printf '%b' "$detail")
}

# Translate en0/en1 to the human service name macOS uses ("Wi-Fi", "Ethernet", etc.)
networksetup_service_for_iface() {
    local iface="$1"
    networksetup -listallhardwareports 2>/dev/null | awk -v want="$iface" '
        /^Hardware Port:/{port=substr($0, 16)}
        /^Device:/{ if ($2 == want) { print port; exit } }
    '
}

# ---------------------------------------------------------------- summary

print_summary() {
    printf '\n%s%sSummary%s\n' "$C_BLD" "$C_BLU" "$C_RST"
    printf '%s\n' "─────────────────────────────────────────────────────────────"

    # Iterate REPORT_ROWS by splitting on SEP_ROW.
    local OLD_IFS="$IFS"
    IFS="$SEP_ROW"
    local row
    for row in $REPORT_ROWS; do
        [ -z "$row" ] && continue
        local first_line name verdict
        first_line=$(printf '%s\n' "$row" | head -1)
        name=$(printf '%s' "$first_line" | awk -F'|' '{print $1}')
        verdict=$(printf '%s' "$first_line" | awk -F'|' '{print $2}')

        local color glyph
        color=$(verdict_color "$verdict")
        glyph=$(verdict_glyph "$verdict")
        printf '  %s%s %-7s%s  %s\n' "$color" "$glyph" "$verdict" "$C_RST" "$name"
    done
    IFS="$OLD_IFS"
}

print_detail_sections() {
    printf '\n%s%sDetail%s\n' "$C_BLD" "$C_BLU" "$C_RST"
    printf '%s\n' "─────────────────────────────────────────────────────────────"

    local OLD_IFS="$IFS"
    IFS="$SEP_ROW"
    local row
    for row in $REPORT_ROWS; do
        [ -z "$row" ] && continue
        local name verdict
        name=$(printf '%s\n' "$row" | head -1 | awk -F'|' '{print $1}')
        verdict=$(printf '%s\n' "$row" | head -1 | awk -F'|' '{print $2}')
        local body
        body=$(printf '%s\n' "$row" | sed '1d')

        printf '\n%s%s [%s]%s\n' "$C_BLD" "$name" "$verdict" "$C_RST"
        printf '%s\n' "$body"
    done
    IFS="$OLD_IFS"
}

# ---------------------------------------------------------------- upload (PrivateBin v2)

# Generate a plain-text report (no ANSI colors) suitable for upload.
build_plaintext_report() {
    NO_COLOR=1 print_summary 2>&1 | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g'
    NO_COLOR=1 print_detail_sections 2>&1 | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g'
}

upload_to_privatebin() {
    local py
    for py in python3 python; do
        if command -v "$py" >/dev/null 2>&1; then
            if "$py" -c 'import sys; sys.exit(0 if sys.version_info >= (3,7) else 1)' 2>/dev/null; then
                break
            fi
        fi
        py=""
    done

    if [ -z "$py" ]; then
        printf '\n%s⚠ Upload skipped:%s Python 3.7+ not found.\n' "$C_YEL" "$C_RST" >&2
        printf '   Install with:  xcode-select --install\n' >&2
        return 1
    fi

    if ! "$py" -c 'from cryptography.hazmat.primitives.ciphers.aead import AESGCM' 2>/dev/null; then
        printf '\n%s⚠ Upload skipped:%s Python `cryptography` library missing.\n' "$C_YEL" "$C_RST" >&2
        printf '   Install with:  %s -m pip install --user cryptography\n' "$py" >&2
        return 1
    fi

    # Inline Python helper. Reads the plaintext report on stdin, takes PB base
    # URL and expiration as argv; prints the final paste URL (with key in the
    # fragment) on stdout. We use -c "$PY_HELPER" rather than a stdin heredoc
    # so the helper can read the report from stdin without conflict.
    local PY_HELPER
    PY_HELPER='
import sys, os, json, secrets, hashlib, zlib, urllib.request, urllib.error
from base64 import b64encode

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:
    print("cryptography library missing", file=sys.stderr)
    sys.exit(2)

B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
def b58encode(b):
    n = int.from_bytes(b, "big")
    out = ""
    while n > 0:
        n, r = divmod(n, 58)
        out = B58[r] + out
    for byte in b:
        if byte == 0:
            out = "1" + out
        else:
            break
    return out

def main():
    pb_base = sys.argv[1].rstrip("/")
    expire = sys.argv[2] if len(sys.argv) > 2 else "1month"
    content = sys.stdin.read()

    master = secrets.token_bytes(32)
    salt   = secrets.token_bytes(8)
    iv     = secrets.token_bytes(16)
    iterations = 100000

    aes_key = hashlib.pbkdf2_hmac("sha256", master, salt, iterations, dklen=32)

    pt_json = json.dumps({"paste": content}, separators=(",", ":")).encode()
    # PrivateBin v2 expects RAW DEFLATE (RFC 1951, no zlib header/trailer):
    # the bundled WASM zlib uses NO_ZLIB_HEADER=-1 in its deflate context.
    # zlib.compress() emits the wrapper, so use compressobj with wbits=-MAX_WBITS.
    co = zlib.compressobj(level=zlib.Z_DEFAULT_COMPRESSION, wbits=-zlib.MAX_WBITS)
    pt_compressed = co.compress(pt_json) + co.flush()

    adata = [
        [
            b64encode(iv).decode(),
            b64encode(salt).decode(),
            iterations,
            256,
            128,
            "aes",
            "gcm",
            "zlib",
        ],
        "plaintext",
        0,
        0,
    ]
    aad = json.dumps(adata, separators=(",", ":")).encode()

    aesgcm = AESGCM(aes_key)
    ct_and_tag = aesgcm.encrypt(iv, pt_compressed, aad)

    payload = {
        "v": 2,
        "adata": adata,
        "ct": b64encode(ct_and_tag).decode(),
        "meta": {"expire": expire},
    }
    req = urllib.request.Request(
        pb_base + "/",
        data=json.dumps(payload).encode(),
        method="POST",
        headers={
            "X-Requested-With": "JSONHttpRequest",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        msg = ""
        try:
            msg = e.read().decode()[:300]
        except Exception:
            pass
        print("upload failed: HTTP " + str(e.code) + " " + msg, file=sys.stderr)
        sys.exit(3)
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        print("upload failed: " + str(e), file=sys.stderr)
        sys.exit(3)

    if body.get("status") != 0:
        print("PrivateBin error: " + str(body.get("message", "unknown")), file=sys.stderr)
        sys.exit(4)

    paste_id = body["id"]
    key_b58 = b58encode(master)
    print(pb_base + "/?" + paste_id + "#" + key_b58)

main()
'
    local url
    url=$(build_plaintext_report | "$py" -c "$PY_HELPER" "$PB_BASE" "$PB_EXPIRE")
    local rc=$?

    if [ "$rc" -ne 0 ] || [ -z "$url" ]; then
        printf '\n%s⚠ Upload failed%s (exit %s) — the report is still in your terminal above.\n' \
            "$C_YEL" "$C_RST" "$rc" >&2
        return 1
    fi

    printf '\n%s%sReport uploaded%s — expires in %s, decryption key is in the URL fragment:\n' \
        "$C_BLD" "$C_GRN" "$C_RST" "$PB_EXPIRE"
    printf '   %s\n' "$url"
}

# ---------------------------------------------------------------- main

print_banner

# Set up a per-run tempdir for the parallel probes. macOS mktemp wants the
# template at the end and requires the X's at the tail of the suffix.
RUN_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/netdiag.XXXXXX") || {
    printf '%snet-diag: mktemp failed%s\n' "$C_RED" "$C_RST" >&2
    exit 3
}
trap 'rm -rf "$RUN_TMPDIR"' EXIT INT TERM

# probe_link runs sequentially first — every other probe depends on the
# DETECTED_IFACE / DETECTED_SSID / HAS_IPV4 / HAS_IPV6 globals it sets,
# and a subshell can't write them back.
run_probe "Link layer" probe_link

# Fork the remaining 8 probes in parallel. Each writes its result to a
# tempfile; we collect them in the canonical order below so the report is
# deterministic regardless of finish order.
printf '%sRunning 8 probes in parallel…%s\n' "$C_DIM" "$C_RST"
dispatch_probe "DNS"                 probe_dns
dispatch_probe "Captive portal"      probe_captive
dispatch_probe "Reachability (IPv4)" probe_reach_v4
dispatch_probe "IPv6"                probe_v6
dispatch_probe "Path (traceroute)"   probe_path
dispatch_probe "Performance"         probe_perf
dispatch_probe "Homelab"             probe_homelab
dispatch_probe "System hints"        probe_system
wait

collect_probe "DNS"
collect_probe "Captive portal"
collect_probe "Reachability (IPv4)"
collect_probe "IPv6"
collect_probe "Path (traceroute)"
collect_probe "Performance"
collect_probe "Homelab"
collect_probe "System hints"

print_summary
print_detail_sections

if [ "$DO_UPLOAD" = 1 ]; then
    upload_to_privatebin || true
fi
