# hackprobe

AI-assisted black-box security audit skill for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Combines 25+ CLI security tools with LLM reasoning to find vulnerabilities that scanners miss — business logic flaws, multi-step exploit chains, leaked secrets in public archives, unauthenticated payment/CRM injection, and framework-specific attack surfaces.

## What makes this different

Traditional scanners (Nuclei, Burp, ZAP) match patterns against known vulnerability signatures. hackprobe adds an AI reasoning layer that:

- **Chains findings into exploit paths** - connects leaked API keys, unauthenticated endpoints, and writable fields into real attack scenarios
- **Mines public archives** - finds leaked UUIDs, auth tokens, and PII in Wayback Machine / CommonCrawl cached responses
- **Reasons about business logic** - understands that a dev endpoint returning a real token means full account takeover, not just "endpoint exists"
- **Confirms exploits in a real browser** - uses Playwright to walk multi-step attack chains end-to-end with screenshots

| Capability | Nuclei | Burp Suite | hackprobe |
|---|---|---|---|
| Known CVE scanning | Yes | Yes | Yes (via nmap, sqlmap, dalfox) |
| Business logic reasoning | No | Manual only | Yes — AI chains findings |
| Archive mining (Wayback/CommonCrawl) | No | No | Yes — Stage 1C |
| Multi-step exploit chains | No | Manual only | Yes — Stage 6 AI |
| Browser-confirmed exploits | No | Manual | Yes — Playwright MCP |
| OSINT + tech stack fingerprinting | No | Limited | Yes — Stage 1A/1E |
| Runs inside Claude Code | No | No | Yes |

## Architecture

hackprobe runs in 6 sequential stages. Each stage spawns parallel sub-agents for maximum speed. Results are persisted to markdown files. Stage 6 is the AI orchestrator — it reads all results and reasons about business logic, chains findings, and scores by business impact.

```
Stage 1: OSINT & Recon           (6 parallel agents)
    |
Stage 2: Automated Scanning      (4 parallel agents)
    |
Stage 3: Browser Analysis        (Playwright MCP)
    |
Stage 4: Active Injection Testing (6 parallel agents)
    |
Stage 5: Deep Analysis           (5 parallel agents)
    |
Stage 6: AI Orchestrator          (reads all results, chains findings, generates report)
```

## Tool arsenal

| Tool | Purpose |
|---|---|
| nmap, naabu | Port scanning + service detection |
| sqlmap | SQL injection |
| dalfox | XSS with browser confirmation |
| ffuf, feroxbuster | Directory and parameter fuzzing |
| testssl | SSL/TLS analysis |
| subfinder, amass, dnsx | Subdomain enumeration |
| httpx | HTTP probing + tech detection |
| katana | Web crawling (headless browser) |
| gau, waybackurls | Historical URL collection from archives |
| trufflehog | Secret scanning with live API verification |
| gf, qsreplace, uro, anew | URL classification and payload injection |
| s3scanner | Cloud bucket access testing |
| interactsh-client | Out-of-band callback (blind SSRF/XSS/XXE) |
| subzy | Subdomain takeover detection |
| crlfuzz | CRLF injection scanning |
| jwt_tool | JWT attack suite (alg confusion, none alg, weak secrets) |
| arjun | Hidden HTTP parameter discovery |
| theHarvester | Passive OSINT (emails, subdomains, employee names) |
| wafw00f | WAF fingerprinting |
| Playwright MCP | Browser automation for SPA analysis and exploit confirmation |

## Setup

### 1. Install tools

```bash
bash install.sh
```

Supports macOS (Homebrew) and Linux (apt/go/pip). Requires Go 1.21+ for ProjectDiscovery tools.

The installer will verify all tools at the end and report any missing ones.

### 2. Add the skill to Claude Code

Add the skill path to your Claude Code project or global settings:

```json
{
  "skills": [
    "/path/to/hackprobe/SKILL.md"
  ]
}
```

Or place `SKILL.md` in your project's `.claude/skills/hackprobe/` directory.

### 3. Configure Playwright MCP

hackprobe uses the [Playwright MCP server](https://github.com/anthropics/mcp-playwright) for browser automation. Add it to your Claude Code MCP config:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@anthropic-ai/mcp-playwright"]
    }
  }
}
```

### 4. Run

```
/hackprobe https://target.example.com
```

hackprobe will ask for confirmation before starting active testing.

## Output

All results are written to a timestamped workspace (`/tmp/hackprobe_<timestamp>/results/`):

```
results/
  01_osint.md            # Business intelligence
  01_subdomains.md       # Subdomain enumeration
  01_urls.md             # URL collection (live + archived)
  01_infra.md            # Port scan + WAF
  01_techstack.md        # Technology fingerprint
  01_domain.md           # Domain intelligence + email security
  02_defaults.md         # Default credentials
  02_content.md          # Sensitive file discovery
  02_secrets.md          # Secret scanning (trufflehog + custom patterns)
  02_ssl_headers.md      # SSL/TLS + security headers
  03_browser.md          # Playwright browser analysis
  04_sqli.md             # SQL injection
  04_xss.md              # Cross-site scripting
  04_misc_injection.md   # SSRF, LFI, CORS, open redirect
  04_http_methods.md     # HTTP methods + request smuggling
  04_oob.md              # Out-of-band callbacks
  04_crlf.md             # CRLF injection
  04_graphql_websocket.md # GraphQL + WebSocket testing
  05_archive_pii.md      # PII in public archives
  05_api_sweep.md        # Unauthenticated API boundary testing
  05_framework.md        # Framework-specific attack surfaces
  05_cloud.md            # Cloud misconfigurations
  05_business_logic.md   # Business logic vulnerabilities
  06_playwright_confirmations.md  # Browser-confirmed exploit screenshots
  REPORT.md              # Final structured report with CVSS scoring
```

## Responsible use

hackprobe is designed for authorized security testing only. Before running:

1. Ensure you have written authorization to test the target
2. hackprobe will ask for explicit confirmation before starting
3. Use test/throwaway emails (mailinator, guerrillamail) for registration probes
4. Never submit real payment data during testing
5. Report findings through responsible disclosure channels

## License

MIT
