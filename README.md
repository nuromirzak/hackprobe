# hackprobe

Black-box security audit as a [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill. Orchestrates 25+ security tools with LLM reasoning to find business logic vulnerabilities that scanners miss.

## Quick start

```bash
# 1. Install tools (one-time)
bash install.sh

# 2. Run
claude /hackprobe https://your-target.com
```

That's it. The skill runs a 6-stage audit and writes a structured report to `results/REPORT.md`.

## Setup

**Requirements:** macOS or Linux, Go 1.21+, Python 3

### Install tools

```bash
bash install.sh
```

Installs nmap, sqlmap, trufflehog, subfinder, and 20+ other tools via Homebrew (macOS) or apt/go/pip (Linux).

### Add the skill

**Option A** - copy into your project:
```bash
cp SKILL.md .claude/skills/hackprobe/SKILL.md
```

**Option B** - reference directly:
```json
{
  "skills": ["/path/to/hackprobe/SKILL.md"]
}
```

### Add Playwright MCP (optional, for browser testing)

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

## What it does

6 stages, each running parallel agents:

1. **Recon** - subdomains, URLs, ports, tech stack, OSINT, DNS
2. **Scanning** - secrets in JS, sensitive files, SSL, default credentials
3. **Browser** - Playwright extracts client-side data, tests forms, navigates SPAs
4. **Injection** - SQLi, XSS, SSRF, CORS, IDOR, CRLF
5. **Deep analysis** - framework exploits, archive mining, GraphQL, cloud storage, API boundaries
6. **AI Orchestrator** - reads all results, chains findings into exploit paths, generates report with CVSS scores

The AI Orchestrator is the key. Stages 1-5 run standard tools. Stage 6 reasons about relationships between findings - connecting a leaked API key to an unvalidated billing endpoint to a subscription bypass. No scanner can express that check.

## Responsible use

This skill is for authorized security testing only.

- Only test targets you own or have written permission to test
- The skill asks for confirmation before every audit
- Use throwaway emails for registration probes
- Never submit real payment data
- Report findings through responsible disclosure

## License

MIT
