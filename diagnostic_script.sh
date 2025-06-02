#!/bin/bash
# Diagnostic script to check what's wrong with the installation

echo "=== Agent Zero Installation Diagnostics ==="
echo "Date: $(date)"
echo

# Check system
echo "1. System Information:"
echo "   OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')"
echo "   Kernel: $(uname -r)"
echo "   Architecture: $(uname -m)"
echo

# Check user
echo "2. User Information:"
echo "   Current user: $(whoami)"
echo "   Running as root: $([[ $EUID -eq 0 ]] && echo 'Yes' || echo 'No')"
echo

# Check memory
echo "3. Memory:"
free -h
echo

# Check disk space
echo "4. Disk Space:"
df -h /
echo

# Check internet
echo "5. Internet Connection:"
ping -c 1 google.com &>/dev/null && echo "   ✓ Connected" || echo "   ✗ Not connected"
echo

# Check if installer exists
echo "6. Checking for installer:"
if [[ -f "agent0_installer.sh" ]]; then
    echo "   ✓ Found agent0_installer.sh"
    echo "   File size: $(ls -lh agent0_installer.sh | awk '{print $5}')"
    echo "   First line: $(head -1 agent0_installer.sh)"
    echo "   Executable: $([ -x agent0_installer.sh ] && echo 'Yes' || echo 'No')"
else
    echo "   ✗ agent0_installer.sh not found in current directory"
fi
echo

# Check for existing installations
echo "7. Existing installations:"
[[ -d /opt/agent0-mistral ]] && echo "   • Found /opt/agent0-mistral" || echo "   • No existing installation found"
command -v ollama &>/dev/null && echo "   • Ollama is installed" || echo "   • Ollama not installed"
command -v docker &>/dev/null && echo "   • Docker is installed" || echo "   • Docker not installed"
[[ -d /opt/miniconda3 ]] && echo "   • Miniconda found" || echo "   • Miniconda not found"
echo

# Try to download installer
echo "8. Testing download from GitHub:"
if curl -fsSL https://raw.githubusercontent.com/Thot3Process/testingclaudeout/main/agent0_installer.sh -o /tmp/test_download.sh 2>/dev/null; then
    echo "   ✓ Successfully downloaded installer"
    echo "   File size: $(ls -lh /tmp/test_download.sh | awk '{print $5}')"
    rm -f /tmp/test_download.sh
else
    echo "   ✗ Failed to download installer"
fi
echo

# Check for common issues
echo "9. Common Issues Check:"

# Check if script has Windows line endings
if [[ -f "agent0_installer.sh" ]]; then
    if file agent0_installer.sh | grep -q "CRLF"; then
        echo "   ⚠ WARNING: Script has Windows line endings (CRLF)"
        echo "   Fix with: dos2unix agent0_installer.sh"
    else
        echo "   ✓ Script has correct Unix line endings"
    fi
fi

# Check bash version
echo "   Bash version: $BASH_VERSION"

echo
echo "=== Diagnostics Complete ==="
echo
echo "To run the installer:"
echo "1. Make sure you're root: sudo su"
echo "2. Download fresh copy:"
echo "   curl -fsSL https://raw.githubusercontent.com/Thot3Process/testingclaudeout/main/agent0_installer.sh -o installer.sh"
echo "3. Make executable: chmod +x installer.sh"
echo "4. Run it: ./installer.sh"