#!/bin/bash
set -e

# DNS Setup Script for Traefik IngressRoutes
# Adds .local.dev entries to /etc/hosts

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

HOSTS_FILE="/etc/hosts"
MARKER_START="# BEGIN Talos Local Dev"
MARKER_END="# END Talos Local Dev"

# DNS entries to add
declare -a DNS_ENTRIES=(
    "127.0.0.1 grafana.local.dev"
    "127.0.0.1 prometheus.local.dev"
    "127.0.0.1 traefik.local.dev"
    "127.0.0.1 app.local.dev"
)

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if grep -qi microsoft /proc/version; then
            echo "wsl"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Check if running with sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}[WARN]${NC} This script requires sudo privileges to modify ${HOSTS_FILE}"
        echo -e "${BLUE}[INFO]${NC} Please run: sudo $0"
        exit 1
    fi
}

# Remove existing entries
remove_existing_entries() {
    if grep -q "$MARKER_START" "$HOSTS_FILE"; then
        echo -e "${GREEN}[INFO]${NC} Removing existing Talos Local Dev entries..."
        # Create temp file without the marked section
        sed -i.bak "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"
    fi
}

# Add DNS entries
add_dns_entries() {
    echo -e "${GREEN}[INFO]${NC} Adding DNS entries to ${HOSTS_FILE}..."

    # Add marker and entries
    {
        echo ""
        echo "$MARKER_START"
        for entry in "${DNS_ENTRIES[@]}"; do
            echo "$entry"
        done
        echo "$MARKER_END"
    } >> "$HOSTS_FILE"

    echo -e "${GREEN}[SUCCESS]${NC} DNS entries added successfully!"
}

# Verify DNS resolution
verify_dns() {
    echo -e "${GREEN}[INFO]${NC} Verifying DNS resolution..."
    local all_ok=true

    for entry in "${DNS_ENTRIES[@]}"; do
        local hostname=$(echo "$entry" | awk '{print $2}')
        if ping -c 1 -W 1 "$hostname" &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} $hostname resolves correctly"
        else
            echo -e "  ${YELLOW}✗${NC} $hostname failed to resolve (this may be normal if Traefik isn't running)"
            all_ok=false
        fi
    done

    return 0  # Don't fail on DNS verification errors
}

# Show Windows instructions
show_windows_instructions() {
    echo ""
    echo -e "${BLUE}[INFO]${NC} For Windows users:"
    echo ""
    echo "1. Open Notepad as Administrator"
    echo "2. Open: C:\\Windows\\System32\\drivers\\etc\\hosts"
    echo "3. Add these lines:"
    echo ""
    for entry in "${DNS_ENTRIES[@]}"; do
        echo "   $entry"
    done
    echo ""
    echo "4. Save the file"
    echo "5. Flush DNS cache: ipconfig /flushdns"
    echo ""
}

# Main execution
main() {
    local os=$(detect_os)

    echo -e "${GREEN}[INFO]${NC} Detected OS: $os"

    if [ "$os" == "unknown" ]; then
        echo -e "${RED}[ERROR]${NC} Unsupported operating system"
        show_windows_instructions
        exit 1
    fi

    # Check for sudo
    check_sudo

    # Remove existing entries (idempotent)
    remove_existing_entries

    # Add new entries
    add_dns_entries

    # Verify DNS resolution
    verify_dns

    # Flush DNS cache based on OS
    echo -e "${GREEN}[INFO]${NC} Flushing DNS cache..."
    case "$os" in
        "linux"|"wsl")
            # Linux/WSL might use systemd-resolved
            if command -v systemd-resolve &> /dev/null; then
                systemd-resolve --flush-caches || true
            fi
            ;;
        "macos")
            dscacheutil -flushcache
            killall -HUP mDNSResponder || true
            ;;
    esac

    echo ""
    echo -e "${GREEN}[SUCCESS]${NC} DNS setup completed!"
    echo ""
    echo "The following endpoints are now available:"
    echo "  - http://grafana.local.dev"
    echo "  - http://prometheus.local.dev"
    echo "  - http://traefik.local.dev"
    echo "  - http://app.local.dev"
    echo ""
    echo "Note: Endpoints will only work after Traefik is deployed and services are running."
}

# Handle --remove flag
if [ "$1" == "--remove" ]; then
    check_sudo
    remove_existing_entries
    echo -e "${GREEN}[SUCCESS]${NC} DNS entries removed from ${HOSTS_FILE}"
    exit 0
fi

# Run main function
main
