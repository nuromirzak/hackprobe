#!/bin/bash
# hackprobe - Install all required security tools
# Supports macOS (Homebrew) and Linux (apt/go/pip/cargo)

set -e

echo "=== hackprobe tool installer ==="
echo ""

OS="$(uname -s)"

# ── System packages (platform-specific, non-overlapping) ─────────────────────

if [[ "$OS" == "Darwin" ]]; then
  command -v brew >/dev/null 2>&1 || { echo "Install Homebrew first: https://brew.sh"; exit 1; }

  echo "[1/5] Installing Homebrew packages..."
  # Only tools that are NOT installed via Go below
  brew install nmap sqlmap testssl feroxbuster trufflehog amass 2>/dev/null || true
  echo "  Done"

elif [[ "$OS" == "Linux" ]]; then
  echo "[1/5] Installing system packages..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq nmap testssl.sh sqlmap whois dnsutils 2>/dev/null || true

  # trufflehog - binary install on Linux
  if ! command -v trufflehog >/dev/null 2>&1; then
    echo "  Installing trufflehog..."
    curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sudo sh -s -- -b /usr/local/bin 2>/dev/null || true
  fi

  # feroxbuster - cargo on Linux
  if command -v cargo >/dev/null 2>&1; then
    echo "  Installing feroxbuster via cargo..."
    cargo install feroxbuster 2>/dev/null || true
  else
    echo "  Skipping feroxbuster (install Rust from https://rustup.rs/)"
  fi

  # amass via Go
  echo "  Installing amass via Go..."
  go install github.com/owasp-amass/amass/v4/...@master 2>/dev/null || true

  echo "  Done"
else
  echo "Unsupported OS: $OS"
  echo "hackprobe supports macOS and Linux."
  exit 1
fi

# ── Go tools (cross-platform, canonical source for all Go-based tools) ───────

echo "[2/5] Installing Go tools..."
command -v go >/dev/null 2>&1 || { echo "  Go not found. Install Go 1.21+ from https://go.dev/dl/"; exit 1; }

# ProjectDiscovery tools
go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest 2>/dev/null || true
go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest 2>/dev/null || true
go install github.com/projectdiscovery/httpx/cmd/httpx@latest 2>/dev/null || true
go install github.com/projectdiscovery/katana/cmd/katana@latest 2>/dev/null || true
go install github.com/projectdiscovery/naabu/v2/cmd/naabu@latest 2>/dev/null || true
go install github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest 2>/dev/null || true

# URL collection and processing
go install github.com/lc/gau/v2/cmd/gau@latest 2>/dev/null || true
go install github.com/tomnomnom/waybackurls@latest 2>/dev/null || true
go install github.com/tomnomnom/gf@latest 2>/dev/null || true
go install github.com/tomnomnom/qsreplace@latest 2>/dev/null || true
go install github.com/tomnomnom/anew@latest 2>/dev/null || true

# Scanners
go install github.com/hahwul/dalfox/v2@latest 2>/dev/null || true
go install github.com/ffuf/ffuf/v2@latest 2>/dev/null || true
go install github.com/PentestPad/subzy@latest 2>/dev/null || true
go install github.com/dwisiswant0/crlfuzz/cmd/crlfuzz@latest 2>/dev/null || true

echo "  Done"

# ── Python tools (cross-platform) ────────────────────────────────────────────

echo "[3/5] Installing Python packages..."
command -v python3 >/dev/null 2>&1 || { echo "  Python3 not found"; exit 1; }
pip3 install --user uro s3scanner wafw00f theHarvester arjun jwt-tool 2>/dev/null || true
echo "  Done"

# ── gf patterns ──────────────────────────────────────────────────────────────

echo "[4/5] Installing gf patterns..."
GF_DIR="$HOME/.gf"
mkdir -p "$GF_DIR"
if [ ! -f "$GF_DIR/sqli.json" ]; then
  git clone --quiet https://github.com/1ndianl33t/Gf-Patterns.git /tmp/gf-patterns 2>/dev/null || true
  cp /tmp/gf-patterns/*.json "$GF_DIR/" 2>/dev/null || true
  rm -rf /tmp/gf-patterns
fi
echo "  Done"

# ── Verify ───────────────────────────────────────────────────────────────────

echo "[5/5] Verifying installations..."
echo ""

TOOLS="nmap sqlmap dalfox ffuf feroxbuster testssl subfinder amass dnsx httpx katana gau waybackurls trufflehog naabu gf qsreplace anew uro s3scanner wafw00f theHarvester arjun interactsh-client subzy crlfuzz"
MISSING=""
FOUND=0
TOTAL=0

for tool in $TOOLS; do
  TOTAL=$((TOTAL + 1))
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  ok  $tool"
    FOUND=$((FOUND + 1))
  else
    echo "  MISSING  $tool"
    MISSING="$MISSING $tool"
  fi
done

# jwt_tool check (pip package name differs from import)
TOTAL=$((TOTAL + 1))
if pip3 show jwt-tool >/dev/null 2>&1; then
  echo "  ok  jwt_tool"
  FOUND=$((FOUND + 1))
else
  echo "  MISSING  jwt_tool"
  MISSING="$MISSING jwt_tool"
fi

echo ""
echo "=== $FOUND/$TOTAL tools installed ==="
if [ -n "$MISSING" ]; then
  echo "Missing:$MISSING"
fi
