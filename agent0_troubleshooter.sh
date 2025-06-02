#!/bin/bash
# =============================================================================
# Agent Zero + Mistral Nemo Automatic Troubleshooter
# Version: 1.0.0
# Description: Diagnoses and fixes common issues automatically
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_VERSION="1.0.0"
readonly LOG_DIR="/var/log/agent0-mistral"
readonly INSTALL_DIR="/opt/agent0-mistral"
readonly CONFIG_DIR="/etc/agent0-mistral"
readonly TROUBLESHOOT_LOG="$LOG_DIR/troubleshoot-$(date +%Y%m%d-%H%M%S).log"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Problem tracking
declare -A PROBLEMS_FOUND
declare -A FIXES_APPLIED
TOTAL_ISSUES=0
FIXED_ISSUES=0

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    echo "[SUCCESS] $1" >> "$TROUBLESHOOT_LOG"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    echo "[ERROR] $1" >> "$TROUBLESHOOT_LOG"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    echo "[WARNING] $1" >> "$TROUBLESHOOT_LOG"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
    echo "[INFO] $1" >> "$TROUBLESHOOT_LOG"
}

print_fix() {
    echo -e "${GREEN}🔧${NC} $1"
    echo "[FIX] $1" >> "$TROUBLESHOOT_LOG"
}

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR"
    echo "=== Troubleshooting Started: $(date) ===" > "$TROUBLESHOOT_LOG"
    echo "Version: $SCRIPT_VERSION" >> "$TROUBLESHOOT_LOG"
}

# =============================================================================
# DIAGNOSTIC FUNCTIONS
# =============================================================================

# Check if running with proper privileges
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        echo "Please run: sudo $0"
        exit 1
    fi
}

# System diagnostics
diagnose_system() {
    print_header "System Diagnostics"
    
    # Check Ubuntu version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        print_info "OS: $PRETTY_NAME"
        
        if [[ "$ID" != "ubuntu" ]] || [[ "$VERSION_ID" != "24.04" ]]; then
            print_warning "This system is not Ubuntu 24.04 - some fixes may not work correctly"
        fi
    fi
    
    # Check system resources
    local memory_gb=$(free -g | awk '/^Mem:/{print $2}')
    local available_memory_gb=$(free -g | awk '/^Mem:/{print $7}')
    local disk_usage=$(df / | awk 'NR==2{print $5}' | sed 's/%//')
    local cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    print_info "Total Memory: ${memory_gb}GB (Available: ${available_memory_gb}GB)"
    print_info "Disk Usage: ${disk_usage}%"
    print_info "CPU Load: $cpu_load"
    
    # Check for issues
    if [[ $memory_gb -lt 16 ]]; then
        PROBLEMS_FOUND["low_memory"]=1
        ((TOTAL_ISSUES++))
        print_warning "Low memory detected: ${memory_gb}GB (minimum recommended: 16GB)"
    fi
    
    if [[ $available_memory_gb -lt 4 ]]; then
        PROBLEMS_FOUND["insufficient_free_memory"]=1
        ((TOTAL_ISSUES++))
        print_warning "Low available memory: ${available_memory_gb}GB"
    fi
    
    if [[ $disk_usage -gt 90 ]]; then
        PROBLEMS_FOUND["disk_full"]=1
        ((TOTAL_ISSUES++))
        print_warning "Disk usage critical: ${disk_usage}%"
    fi
}

# Service diagnostics
diagnose_services() {
    print_header "Service Diagnostics"
    
    local services=("ollama" "agent0" "docker")
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            if systemctl is-active "$service" >/dev/null 2>&1; then
                print_success "$service service is running"
            else
                PROBLEMS_FOUND["service_${service}_not_running"]=1
                ((TOTAL_ISSUES++))
                print_error "$service service is not running"
                
                # Check why it's not running
                if systemctl is-enabled "$service" >/dev/null 2>&1; then
                    print_info "$service is enabled but not running"
                else
                    PROBLEMS_FOUND["service_${service}_not_enabled"]=1
                    print_warning "$service is not enabled"
                fi
            fi
        else
            PROBLEMS_FOUND["service_${service}_not_installed"]=1
            ((TOTAL_ISSUES++))
            print_error "$service service not found"
        fi
    done
}

# Network diagnostics
diagnose_network() {
    print_header "Network Diagnostics"
    
    # Check ports
    local ports=("8080:agent0" "11434:ollama")
    
    for port_info in "${ports[@]}"; do
        IFS=':' read -r port name <<< "$port_info"
        
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            print_success "Port $port ($name) is listening"
        else
            PROBLEMS_FOUND["port_${port}_not_listening"]=1
            ((TOTAL_ISSUES++))
            print_error "Port $port ($name) is not listening"
        fi
    done
    
    # Check API endpoints
    if curl -s -f -m 5 "http://localhost:11434/api/tags" >/dev/null 2>&1; then
        print_success "Ollama API is responsive"
    else
        PROBLEMS_FOUND["ollama_api_not_responding"]=1
        ((TOTAL_ISSUES++))
        print_error "Ollama API is not responding"
    fi
    
    if curl -s -f -m 5 "http://localhost:8080" >/dev/null 2>&1; then
        print_success "Agent Zero web UI is accessible"
    else
        PROBLEMS_FOUND["agent0_ui_not_accessible"]=1
        ((TOTAL_ISSUES++))
        print_error "Agent Zero web UI is not accessible"
    fi
}

# File system diagnostics
diagnose_filesystem() {
    print_header "File System Diagnostics"
    
    # Check critical directories
    local dirs=(
        "$INSTALL_DIR:agent0:agent0"
        "$CONFIG_DIR:root:root"
        "$LOG_DIR:agent0:agent0"
        "/var/lib/ollama:ollama:ollama"
    )
    
    for dir_info in "${dirs[@]}"; do
        IFS=':' read -r dir owner group <<< "$dir_info"
        
        if [[ -d "$dir" ]]; then
            print_success "Directory exists: $dir"
            
            # Check ownership
            local actual_owner=$(stat -c '%U:%G' "$dir" 2>/dev/null || echo "unknown:unknown")
            if [[ "$actual_owner" != "$owner:$group" ]]; then
                PROBLEMS_FOUND["wrong_ownership_${dir//\//_}"]=1
                ((TOTAL_ISSUES++))
                print_warning "Incorrect ownership on $dir (expected: $owner:$group, actual: $actual_owner)"
            fi
        else
            PROBLEMS_FOUND["missing_directory_${dir//\//_}"]=1
            ((TOTAL_ISSUES++))
            print_error "Directory missing: $dir"
        fi
    done
    
    # Check critical files
    local files=(
        "$CONFIG_DIR/agent0.env"
        "$INSTALL_DIR/launch_agent0.sh"
        "/etc/systemd/system/ollama.service"
        "/etc/systemd/system/agent0.service"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            print_success "File exists: $file"
        else
            PROBLEMS_FOUND["missing_file_${file//\//_}"]=1
            ((TOTAL_ISSUES++))
            print_error "File missing: $file"
        fi
    done
}

# Model diagnostics
diagnose_models() {
    print_header "Model Diagnostics"
    
    if command -v ollama >/dev/null 2>&1; then
        local models=$(ollama list 2>/dev/null | grep -v "NAME" || echo "")
        
        if [[ -n "$models" ]]; then
            print_success "Models found:"
            echo "$models" | while read -r line; do
                echo "  • $line"
            done
            
            # Check for Mistral Nemo
            if echo "$models" | grep -q "mistral-nemo:12b"; then
                print_success "Mistral Nemo 12B model is available"
            else
                PROBLEMS_FOUND["mistral_model_missing"]=1
                ((TOTAL_ISSUES++))
                print_error "Mistral Nemo 12B model not found"
            fi
        else
            PROBLEMS_FOUND["no_models_available"]=1
            ((TOTAL_ISSUES++))
            print_error "No models available"
        fi
    else
        PROBLEMS_FOUND["ollama_not_installed"]=1
        ((TOTAL_ISSUES++))
        print_error "Ollama command not found"
    fi
}

# GPU diagnostics
diagnose_gpu() {
    print_header "GPU Diagnostics"
    
    if lspci 2>/dev/null | grep -qi nvidia; then
        print_info "NVIDIA GPU detected"
        
        if command -v nvidia-smi >/dev/null 2>&1; then
            if nvidia-smi >/dev/null 2>&1; then
                print_success "NVIDIA drivers are functional"
                nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
            else
                PROBLEMS_FOUND["nvidia_driver_error"]=1
                ((TOTAL_ISSUES++))
                print_error "NVIDIA drivers installed but not working"
            fi
        else
            PROBLEMS_FOUND["nvidia_driver_missing"]=1
            ((TOTAL_ISSUES++))
            print_warning "NVIDIA GPU detected but drivers not installed"
        fi
    else
        print_info "No NVIDIA GPU detected - CPU mode"
    fi
}

# =============================================================================
# FIX FUNCTIONS
# =============================================================================

# Fix memory issues
fix_memory_issues() {
    if [[ -n "${PROBLEMS_FOUND[insufficient_free_memory]:-}" ]]; then
        print_fix "Attempting to free memory..."
        
        # Clear system caches
        sync
        echo 3 > /proc/sys/vm/drop_caches
        
        # Restart heavy services
        systemctl restart ollama agent0 2>/dev/null || true
        
        ((FIXED_ISSUES++))
        print_success "Memory cleanup completed"
    fi
    
    if [[ -n "${PROBLEMS_FOUND[low_memory]:-}" ]]; then
        print_warning "System has low total memory. Consider adding swap space:"
        echo "  sudo fallocate -l 16G /swapfile"
        echo "  sudo chmod 600 /swapfile"
        echo "  sudo mkswap /swapfile"
        echo "  sudo swapon /swapfile"
    fi
}

# Fix disk space issues
fix_disk_issues() {
    if [[ -n "${PROBLEMS_FOUND[disk_full]:-}" ]]; then
        print_fix "Attempting to free disk space..."
        
        # Clean package cache
        apt-get clean
        apt-get autoremove -y
        
        # Clean old logs
        journalctl --vacuum-time=7d
        find "$LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
        
        # Clean Docker if available
        if command -v docker >/dev/null 2>&1; then
            docker system prune -af --volumes 2>/dev/null || true
        fi
        
        ((FIXED_ISSUES++))
        print_success "Disk cleanup completed"
    fi
}

# Fix service issues
fix_service_issues() {
    local services=("docker" "ollama" "agent0")
    
    for service in "${services[@]}"; do
        # Fix not installed
        if [[ -n "${PROBLEMS_FOUND[service_${service}_not_installed]:-}" ]]; then
            print_fix "Service $service not installed - please run the installer"
            continue
        fi
        
        # Fix not enabled
        if [[ -n "${PROBLEMS_FOUND[service_${service}_not_enabled]:-}" ]]; then
            print_fix "Enabling $service service..."
            systemctl enable "$service"
            ((FIXED_ISSUES++))
        fi
        
        # Fix not running
        if [[ -n "${PROBLEMS_FOUND[service_${service}_not_running]:-}" ]]; then
            print_fix "Starting $service service..."
            
            # Special handling for dependencies
            if [[ "$service" == "agent0" ]]; then
                systemctl start ollama 2>/dev/null || true
                sleep 5
            fi
            
            if systemctl start "$service"; then
                ((FIXED_ISSUES++))
                print_success "$service service started"
            else
                print_error "Failed to start $service service"
                print_info "Checking logs..."
                journalctl -u "$service" -n 20 --no-pager
            fi
        fi
    done
}

# Fix file system issues
fix_filesystem_issues() {
    # Fix missing directories
    for key in "${!PROBLEMS_FOUND[@]}"; do
        if [[ $key == missing_directory_* ]]; then
            local dir=${key#missing_directory_}
            dir=${dir//_/\/}
            
            print_fix "Creating missing directory: $dir"
            mkdir -p "$dir"
            
            # Set correct ownership based on directory
            case "$dir" in
                */agent0-mistral*)
                    chown -R agent0:agent0 "$dir"
                    ;;
                */ollama*)
                    chown -R ollama:ollama "$dir"
                    ;;
            esac
            
            ((FIXED_ISSUES++))
        fi
    done
    
    # Fix wrong ownership
    for key in "${!PROBLEMS_FOUND[@]}"; do
        if [[ $key == wrong_ownership_* ]]; then
            local dir=${key#wrong_ownership_}
            dir=${dir//_/\/}
            
            print_fix "Fixing ownership on: $dir"
            
            case "$dir" in
                */agent0-mistral*|*/log/agent0*)
                    chown -R agent0:agent0 "$dir"
                    ;;
                */ollama*)
                    chown -R ollama:ollama "$dir"
                    ;;
            esac
            
            ((FIXED_ISSUES++))
        fi
    done
}

# Fix model issues
fix_model_issues() {
    if [[ -n "${PROBLEMS_FOUND[mistral_model_missing]:-}" ]] || [[ -n "${PROBLEMS_FOUND[no_models_available]:-}" ]]; then
        print_fix "Downloading Mistral Nemo 12B model..."
        
        # Ensure Ollama is running
        if ! systemctl is-active ollama >/dev/null 2>&1; then
            systemctl start ollama
            sleep 10
        fi
        
        # Download model
        if sudo -u ollama ollama pull mistral-nemo:12b; then
            ((FIXED_ISSUES++))
            print_success "Mistral Nemo model downloaded"
        else
            print_error "Failed to download model"
            print_info "Try manually: sudo -u ollama ollama pull mistral-nemo:12b"
        fi
    fi
}

# Fix configuration issues
fix_configuration_issues() {
    # Regenerate missing config files
    if [[ -n "${PROBLEMS_FOUND[missing_file__etc_agent0-mistral_agent0.env]:-}" ]]; then
        print_fix "Regenerating agent0.env configuration..."
        
        mkdir -p "$CONFIG_DIR"
        cat > "$CONFIG_DIR/agent0.env" <<EOF
# Agent Zero Configuration (Regenerated)
AGENT0_HOST=0.0.0.0
AGENT0_PORT=8080
AGENT0_HOME=$INSTALL_DIR
AGENT0_LOG_DIR=$LOG_DIR
CONDA_PATH=/opt/miniconda3
PYTHON_ENV=agent0
OLLAMA_BASE_URL=http://localhost:11434
DEFAULT_MODEL=mistral-nemo:12b
USE_LOCAL_MODEL=true
SECRET_KEY=$(openssl rand -hex 32)
EOF
        
        ((FIXED_ISSUES++))
        print_success "Configuration file regenerated"
    fi
    
    # Fix launch script
    if [[ -n "${PROBLEMS_FOUND[missing_file__opt_agent0-mistral_launch_agent0.sh]:-}" ]]; then
        print_fix "Regenerating launch script..."
        
        cat > "$INSTALL_DIR/launch_agent0.sh" <<'EOF'
#!/bin/bash
source /etc/agent0-mistral/agent0.env
source $CONDA_PATH/etc/profile.d/conda.sh
conda activate $PYTHON_ENV
cd $AGENT0_HOME/agent-zero
python -m agent0 --host $AGENT0_HOST --port $AGENT0_PORT
EOF
        
        chmod +x "$INSTALL_DIR/launch_agent0.sh"
        chown agent0:agent0 "$INSTALL_DIR/launch_agent0.sh"
        
        ((FIXED_ISSUES++))
        print_success "Launch script regenerated"
    fi
}

# =============================================================================
# ADVANCED FIXES
# =============================================================================

# Reset and reinstall component
reset_component() {
    local component=$1
    
    print_header "Resetting $component"
    
    case "$component" in
        ollama)
            print_info "Stopping and resetting Ollama..."
            systemctl stop ollama 2>/dev/null || true
            
            # Backup models
            if [[ -d /var/lib/ollama/models ]]; then
                print_info "Backing up models..."
                cp -r /var/lib/ollama/models /tmp/ollama-models-backup
            fi
            
            # Reinstall
            curl -fsSL https://ollama.com/install.sh | sh
            
            # Restore models
            if [[ -d /tmp/ollama-models-backup ]]; then
                print_info "Restoring models..."
                cp -r /tmp/ollama-models-backup/* /var/lib/ollama/models/
                rm -rf /tmp/ollama-models-backup
            fi
            
            systemctl start ollama
            ;;
            
        agent0)
            print_info "Resetting Agent Zero..."
            systemctl stop agent0 2>/dev/null || true
            
            # Update from git
            cd "$INSTALL_DIR/agent-zero" 2>/dev/null || {
                print_error "Agent Zero directory not found"
                return 1
            }
            
            sudo -u agent0 git reset --hard
            sudo -u agent0 git pull origin main
            
            # Reinstall dependencies
            sudo -u agent0 bash -c "
                source /opt/miniconda3/etc/profile.d/conda.sh
                conda activate agent0
                pip install --upgrade -r requirements.txt
            "
            
            systemctl start agent0
            ;;
            
        *)
            print_error "Unknown component: $component"
            return 1
            ;;
    esac
    
    print_success "$component reset completed"
}

# =============================================================================
# INTERACTIVE FIXES
# =============================================================================

interactive_fix_menu() {
    print_header "Interactive Fix Menu"
    
    echo "Select an option:"
    echo "1) Restart all services"
    echo "2) Reset Ollama"
    echo "3) Reset Agent Zero"
    echo "4) Download missing models"
    echo "5) Fix permissions"
    echo "6) Clear all logs"
    echo "7) Full system check"
    echo "8) Exit"
    
    read -r -p "Enter choice [1-8]: " choice
    
    case $choice in
        1)
            print_info "Restarting all services..."
            systemctl restart docker ollama agent0
            print_success "Services restarted"
            ;;
        2)
            reset_component ollama
            ;;
        3)
            reset_component agent0
            ;;
        4)
            fix_model_issues
            ;;
        5)
            fix_filesystem_issues
            ;;
        6)
            print_info "Clearing logs..."
            journalctl --vacuum-time=1d
            find "$LOG_DIR" -name "*.log" -mtime +1 -delete
            print_success "Logs cleared"
            ;;
        7)
            run_full_diagnostic
            ;;
        8)
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac
}

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

run_full_diagnostic() {
    print_header "Running Full System Diagnostic"
    
    # Reset counters
    PROBLEMS_FOUND=()
    TOTAL_ISSUES=0
    FIXED_ISSUES=0
    
    # Run all diagnostics
    diagnose_system
    diagnose_services
    diagnose_network
    diagnose_filesystem
    diagnose_models
    diagnose_gpu
}

apply_automatic_fixes() {
    print_header "Applying Automatic Fixes"
    
    if [[ $TOTAL_ISSUES -eq 0 ]]; then
        print_success "No issues found - system is healthy!"
        return 0
    fi
    
    print_info "Found $TOTAL_ISSUES issues. Attempting automatic fixes..."
    
    # Apply fixes in order of importance
    fix_memory_issues
    fix_disk_issues
    fix_filesystem_issues
    fix_configuration_issues
    fix_service_issues
    fix_model_issues
    
    # Summary
    print_header "Fix Summary"
    print_info "Total issues found: $TOTAL_ISSUES"
    print_info "Issues fixed: $FIXED_ISSUES"
    
    if [[ $FIXED_ISSUES -eq $TOTAL_ISSUES ]]; then
        print_success "All issues resolved!"
    else
        local remaining=$((TOTAL_ISSUES - FIXED_ISSUES))
        print_warning "$remaining issues could not be fixed automatically"
        print_info "Run with --interactive for more options"
    fi
}

# Generate report
generate_report() {
    local report_file="$LOG_DIR/diagnostic-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "=== Agent Zero + Mistral Diagnostic Report ==="
        echo "Generated: $(date)"
        echo "Version: $SCRIPT_VERSION"
        echo ""
        echo "=== System Information ==="
        uname -a
        lsb_release -a 2>/dev/null || echo "LSB info not available"
        echo ""
        echo "=== Service Status ==="
        systemctl status ollama agent0 docker --no-pager 2>/dev/null || true
        echo ""
        echo "=== Recent Errors ==="
        journalctl -p err -n 50 --no-pager
        echo ""
        echo "=== Disk Usage ==="
        df -h
        echo ""
        echo "=== Memory Usage ==="
        free -h
        echo ""
        echo "=== Network Ports ==="
        netstat -tlnp 2>/dev/null || ss -tlnp
        echo ""
        echo "=== Docker Status ==="
        docker ps -a 2>/dev/null || echo "Docker not available"
        echo ""
        echo "=== GPU Status ==="
        nvidia-smi 2>/dev/null || echo "No GPU available"
    } > "$report_file"
    
    print_success "Diagnostic report saved to: $report_file"
}

# Show usage
show_usage() {
    cat << EOF
Agent Zero + Mistral Nemo Troubleshooter
Version: $SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --auto          Run automatic diagnostics and fixes (default)
    --interactive   Interactive troubleshooting mode
    --diagnose      Only run diagnostics (no fixes)
    --report        Generate detailed diagnostic report
    --fix-services  Fix service issues only
    --fix-models    Fix model issues only
    --reset [component]  Reset specific component (ollama|agent0)
    --help          Show this help message

EXAMPLES:
    # Run automatic diagnostics and fixes
    sudo $0
    
    # Interactive mode
    sudo $0 --interactive
    
    # Only diagnose without fixing
    sudo $0 --diagnose
    
    # Reset Ollama
    sudo $0 --reset ollama

EOF
}

# Main function
main() {
    init_logging
    check_privileges
    
    # Default mode
    local mode="auto"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto)
                mode="auto"
                shift
                ;;
            --interactive|-i)
                mode="interactive"
                shift
                ;;
            --diagnose|-d)
                mode="diagnose"
                shift
                ;;
            --report|-r)
                mode="report"
                shift
                ;;
            --fix-services)
                mode="fix-services"
                shift
                ;;
            --fix-models)
                mode="fix-models"
                shift
                ;;
            --reset)
                mode="reset"
                shift
                component="${1:-}"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Banner
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Agent Zero + Mistral Nemo Troubleshooter v$SCRIPT_VERSION     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Execute based on mode
    case $mode in
        auto)
            run_full_diagnostic
            apply_automatic_fixes
            ;;
        interactive)
            while true; do
                interactive_fix_menu
            done
            ;;
        diagnose)
            run_full_diagnostic
            print_info "Diagnostic complete. Found $TOTAL_ISSUES issues."
            ;;
        report)
            run_full_diagnostic
            generate_report
            ;;
        fix-services)
            diagnose_services
            fix_service_issues
            ;;
        fix-models)
            diagnose_models
            fix_model_issues
            ;;
        reset)
            if [[ -z "$component" ]]; then
                print_error "Component name required for reset"
                exit 1
            fi
            reset_component "$component"
            ;;
    esac
    
    print_info "Troubleshooting log saved to: $TROUBLESHOOT_LOG"
}

# Run main
main "$@"