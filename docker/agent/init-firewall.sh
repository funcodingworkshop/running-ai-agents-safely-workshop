#!/usr/bin/env bash
# Egress allowlist firewall (see docs/ai-agents-in-docker-spec.md §5.3).
#
# Default policy is DROP for all outbound traffic; only DNS, loopback, and a
# small set of allowlisted domains (resolved to an ipset) are permitted. This
# limits data exfiltration and constrains where a prompt-injected agent can
# reach. Requires --cap-add=NET_ADMIN and root.
set -euo pipefail
IFS=$'\n\t'

# Domains the agent is allowed to reach. Keep this list minimal.
ALLOWED_DOMAINS=(
  "api.anthropic.com"        # Claude Code
  "registry.npmjs.org"       # npm installs
  "github.com"               # git
  "codeload.github.com"      # git archive / go-style fetches
  "raw.githubusercontent.com"
  "objects.githubusercontent.com"
)

# Optional telemetry endpoints, off by default. Enable with ALLOW_TELEMETRY=1.
if [ "${ALLOW_TELEMETRY:-0}" = "1" ]; then
  ALLOWED_DOMAINS+=(
    "statsig.anthropic.com"
    "o1158322.ingest.sentry.io"
  )
fi

echo "[firewall] flushing existing rules"
iptables -F
iptables -X 2>/dev/null || true
ipset destroy allowed-domains 2>/dev/null || true

# Loopback (Vite<->Express talk over localhost inside the container).
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# DNS resolution (needed both to resolve the allowlist below and at runtime).
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT
iptables -A INPUT  -p tcp --sport 53 -j ACCEPT

# Allow replies to connections we initiated.
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Resolve allowlisted domains into an ipset matched by the OUTPUT rule below.
ipset create allowed-domains hash:ip family inet
for domain in "${ALLOWED_DOMAINS[@]}"; do
  ips="$(dig +short A "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)"
  if [ -z "$ips" ]; then
    echo "[firewall] WARN: could not resolve $domain" >&2
    continue
  fi
  for ip in $ips; do
    ipset add allowed-domains "$ip" 2>/dev/null || true
  done
  echo "[firewall] allow $domain -> $(echo "$ips" | tr '\n' ' ')"
done

iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Default-deny everything else.
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  DROP

echo "[firewall] configured. default OUTPUT policy = DROP; ${#ALLOWED_DOMAINS[@]} domains allowlisted."
