#!/bin/bash
# -------------------------------------------------------
# init-firewall.sh — Outbound network allowlist
# Adopted from Anthropic's official Claude Code devcontainer.
# Runs automatically at container start via postStartCommand.
# Managed by IT. Do not modify without IT approval.
# -------------------------------------------------------
#
# WHAT THIS DOES:
#   1. Builds an IP allowlist by fetching GitHub's published IP
#      ranges and resolving each allowed domain via DNS — while
#      the container still has full network access (before any
#      iptables rules are applied).
#   2. Flushes the filter table (INPUT/OUTPUT/FORWARD chains only).
#      The NAT and mangle tables are left untouched so Docker's
#      internal DNS resolver (127.0.0.11) keeps working.
#   3. Applies a default-deny output policy, allowlisting only the
#      IPs gathered in step 1.
#   4. Verifies the firewall works before exiting.
#
# HOW TO ADD A DOMAIN (e.g. an internal agency server):
#   Add the domain name to the "for domain in ..." list below,
#   then rebuild the container (Ctrl+Shift+P → "Rebuild Container").
# -------------------------------------------------------

set -u    # Treat unset variables as errors.
          # No -e or pipefail — all errors are handled explicitly.
IFS=$'\n\t'

# Use arrays so word splitting works regardless of IFS setting.
# Plain strings like "--connect-timeout 10" won't split on spaces
# when IFS=$'\n\t' (see above), breaking curl and dig silently.
CURL_TIMEOUT=(--connect-timeout 10 --max-time 15)
DIG_TIMEOUT=(+time=5 +tries=1)

# -------------------------------------------------------
# STEP 1 — Build the IP allowlist.
# Do this BEFORE touching iptables. The container has full
# network access at startup; we use that window to resolve
# every domain we need. Once DROP policies are in place,
# any domain we missed will be unreachable.
# -------------------------------------------------------
echo "=== Building IP allowlist ==="

ipset destroy allowed-domains 2>/dev/null || true
ipset create allowed-domains hash:net

# Fetch GitHub's published IP ranges.
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -sf "${CURL_TIMEOUT[@]}" https://api.github.com/meta 2>/dev/null || true)

if [ -z "$gh_ranges" ]; then
    echo "WARNING: Could not fetch GitHub IP ranges — GitHub access may not work."
elif ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null 2>&1; then
    echo "WARNING: GitHub API response was unexpected — skipping GitHub IP ranges."
else
    echo "Processing GitHub IPs..."
    while read -r cidr; do
        if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            echo "WARNING: Skipping unexpected CIDR from GitHub meta: $cidr"
            continue
        fi
        echo "  Adding GitHub range $cidr"
        ipset add --exist allowed-domains "$cidr"
    done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)
fi

# Resolve each allowed domain and add its IPs to the allowlist.
# To add an internal agency server, add its hostname to this list.
for domain in \
    "registry.npmjs.org" \
    "api.anthropic.com" \
    "sentry.io" \
    "statsig.anthropic.com" \
    "statsig.com" \
    "marketplace.visualstudio.com" \
    "vscode.blob.core.windows.net" \
    "update.code.visualstudio.com"; do
    # -------------------------------------------------------
    # ADD YOUR INTERNAL AGENCY SERVICES ABOVE THIS LINE:
    # "api.your-agency.gov" \
    # "git.your-agency.gov" \
    # -------------------------------------------------------
    echo "Resolving $domain..."
    ips=$(dig "${DIG_TIMEOUT[@]}" +noall +answer A "$domain" 2>/dev/null | awk '$4 == "A" {print $5}' || true)
    if [ -z "$ips" ]; then
        echo "  WARNING: Could not resolve $domain — will be blocked."
        continue
    fi
    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "  WARNING: Skipping unexpected IP for $domain: $ip"
            continue
        fi
        echo "  Adding $ip for $domain"
        ipset add --exist allowed-domains "$ip"
    done < <(echo "$ips")
done

# Detect the Docker host network so VS Code can connect back to the host.
HOST_IP=$(ip route 2>/dev/null | grep default | cut -d" " -f3 || true)
if [ -z "$HOST_IP" ]; then
    echo "WARNING: Could not detect host IP — VS Code connectivity may be affected."
    HOST_NETWORK=""
else
    HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
    echo "Host network: $HOST_NETWORK"
fi

# -------------------------------------------------------
# STEP 2 — Apply iptables rules.
#
# We flush only the FILTER table (INPUT, OUTPUT, FORWARD chains).
# We deliberately do NOT flush the NAT or mangle tables.
# Docker uses NAT rules to route queries to its internal DNS
# resolver (127.0.0.11). Flushing those tables breaks DNS
# inside the container.
# -------------------------------------------------------
echo "=== Applying firewall rules ==="

iptables -F
iptables -X

# Allow loopback (localhost, and Docker's 127.0.0.11 DNS resolver).
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow DNS — UDP and TCP (some resolvers and corporate proxies use TCP).
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT
iptables -A INPUT  -p tcp --sport 53 -m state --state ESTABLISHED -j ACCEPT

# Allow SSH outbound (for git push/pull over SSH).
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT  -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT

# Allow established/related connections.
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow the Docker host network (required for VS Code's IPC connection).
if [ -n "$HOST_NETWORK" ]; then
    iptables -A INPUT  -s "$HOST_NETWORK" -j ACCEPT
    iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT
fi

# Allow outbound to all allowlisted IPs.
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Set default DROP policies.
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  DROP

# REJECT (rather than DROP) gives immediate feedback instead of a timeout.
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# -------------------------------------------------------
# STEP 3 — Verify.
# -------------------------------------------------------
echo "=== Verifying firewall ==="

if curl "${CURL_TIMEOUT[@]}" https://example.com >/dev/null 2>&1; then
    echo "WARNING: Firewall check unexpected — was able to reach https://example.com"
else
    echo "Blocked: https://example.com (expected)"
fi

if curl "${CURL_TIMEOUT[@]}" https://api.anthropic.com >/dev/null 2>&1; then
    echo "Allowed: https://api.anthropic.com (expected)"
else
    echo "WARNING: Could not reach https://api.anthropic.com — Claude Code will not work."
fi

echo "=== Firewall initialized. ==="
