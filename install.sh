#!/bin/sh

# sing-box installer
# Usage: curl -fsSL https://lurixo.github.io/sing-box-releases/install.sh | sudo sh -s -- [--version <version>]

REPO="lurixo/sing-box-releases"
INSTALL_DIR="/usr/bin"
BINARY_NAME="sing-box"

download_version=""

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      shift
      if [ $# -eq 0 ]; then
        echo "Missing argument for --version"
        echo "Usage: $0 [--version <version>]"
        exit 1
      fi
      download_version="$1"
      shift
      ;;
    -h|--help)
      echo "sing-box installer"
      echo ""
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --version <version>  Install specific version (e.g., 1.13.0-alpha.32)"
      echo "  -h, --help           Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [--version <version>]"
      exit 1
      ;;
  esac
done

# Detect OS
os="unknown"
case "$(uname -s)" in
  Linux*)  os="linux" ;;
  Darwin*) os="darwin" ;;
  MINGW*|MSYS*|CYGWIN*) os="windows" ;;
esac

# Detect architecture
arch="unknown"
case "$(uname -m)" in
  x86_64|amd64)   arch="amd64v3" ;;
  aarch64|arm64)  arch="arm64" ;;
  armv7l)         arch="armv7" ;;
  i386|i686)      arch="386" ;;
esac

echo "Detected: ${os}-${arch}"

if [ "$os" = "unknown" ] || [ "$arch" = "unknown" ]; then
  echo "Unsupported platform: ${os}-${arch}"
  exit 1
fi

# Check root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root (use sudo)"
  exit 1
fi

# Get version if not specified
if [ -z "$download_version" ]; then
  echo "Fetching latest version..."
  
  if [ -n "$GITHUB_TOKEN" ]; then
    latest_release=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" "https://api.github.com/repos/${REPO}/releases")
  else
    latest_release=$(curl -s "https://api.github.com/repos/${REPO}/releases")
  fi
  
  download_version=$(echo "$latest_release" | grep '"tag_name"' | head -n 1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | sed 's/^v//')
  
  if [ -z "$download_version" ]; then
    echo "Failed to fetch latest version"
    exit 1
  fi
fi

echo "Version: $download_version"

# Build download URL
# Both Windows and Linux use archives now
if [ "$os" = "windows" ]; then
  filename="sing-box-${download_version}-${os}-${arch}.zip"
else
  filename="sing-box-${download_version}-${os}-${arch}.tar.gz"
fi

download_url="https://github.com/${REPO}/releases/download/v${download_version}/${filename}"

echo "Downloading $download_url"

# Download to temp file
tmp_file=$(mktemp)
tmp_dir=""

# Ensure cleanup on exit
trap 'rm -rf "$tmp_file" "$tmp_dir" 2>/dev/null' EXIT

if [ -n "$GITHUB_TOKEN" ]; then
  curl --fail -L -o "$tmp_file" -H "Authorization: token ${GITHUB_TOKEN}" "$download_url"
else
  curl --fail -L -o "$tmp_file" "$download_url"
fi

curl_exit_status=$?
if [ $curl_exit_status -ne 0 ]; then
  echo "Download failed!"
  exit $curl_exit_status
fi

# Install binary
echo "Installing to ${INSTALL_DIR}/${BINARY_NAME}..."

tmp_dir=$(mktemp -d)

if [ "$os" = "windows" ]; then
  # Extract from zip for Windows
  unzip -q "$tmp_file" -d "$tmp_dir"
  # Find sing-box.exe in extracted files
  binary_path=$(find "$tmp_dir" -name "sing-box.exe" -type f | head -n 1)
  if [ -z "$binary_path" ]; then
    echo "Failed to find sing-box.exe in archive!"
    exit 1
  fi
  mv "$binary_path" "${INSTALL_DIR}/${BINARY_NAME}.exe"
  chmod +x "${INSTALL_DIR}/${BINARY_NAME}.exe"
else
  # Extract from tar.gz for Linux/Darwin
  tar -xzf "$tmp_file" -C "$tmp_dir"
  # Find sing-box binary in extracted files
  binary_path=$(find "$tmp_dir" -name "sing-box" -type f | head -n 1)
  if [ -z "$binary_path" ]; then
    echo "Failed to find sing-box in archive!"
    exit 1
  fi
  mv "$binary_path" "${INSTALL_DIR}/${BINARY_NAME}"
  chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
fi

# Create systemd service if systemd exists
if [ -d "/etc/systemd/system" ]; then
  echo "Creating systemd service..."
  
  cat > /etc/systemd/system/sing-box.service << 'HEREDOC'
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network-online.target nss-lookup.target
Wants=network-online.target
StartLimitIntervalSec=600
StartLimitBurst=5

[Service]
StateDirectory=sing-box
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_PTRACE CAP_DAC_READ_SEARCH
ExecStart=/usr/bin/sing-box -D /var/lib/sing-box -C /etc/sing-box run
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
RestartPreventExitStatus=23
LimitNOFILE=infinity
LimitNPROC=infinity
TasksMax=infinity
LimitCORE=0
Nice=-10

[Install]
WantedBy=multi-user.target
HEREDOC

  chmod 644 /etc/systemd/system/sing-box.service
  
  if [ ! -s /etc/systemd/system/sing-box.service ]; then
    echo "Failed to create systemd service file!"
    exit 1
  fi

  mkdir -p /etc/sing-box
  mkdir -p /var/lib/sing-box
  systemctl daemon-reload 2>/dev/null || true
  echo "systemd service created. Enable with: systemctl enable sing-box"
fi

# Verify
echo ""
echo "Installation complete!"
sing-box version
