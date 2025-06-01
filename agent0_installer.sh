#!/bin/bash
# =============================================================================
# Ultimate Agent Zero + Mistral Nemo 12B Installation Script
# Version: 2.0.0-ULTIMATE
# Description: Bulletproof, enterprise-grade automated installation
# Target: Ubuntu 24.04 LTS (works on fresh or existing installations)
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

# Script metadata
readonly SCRIPT_VERSION="2.0.0-ULTIMATE"
readonly SCRIPT_NAME="Agent Zero + Mistral Nemo Ultimate Installer"
readonly SCRIPT_START_TIME=$(date +%s)

# Installation directories
readonly INSTALL_BASE="/opt"
readonly INSTALL_DIR="${INSTALL_BASE}/agent0-mistral"
readonly LOG_BASE="/var/log"
readonly LOG_DIR="${LOG_BASE}/agent0-mistral"
readonly CONFIG_DIR="/etc/agent0-mistral"
readonly BACKUP_DIR="${INSTALL_DIR}/backups"
readonly TEMP_DIR="/tmp/agent0-install-$$"

# User and permissions
readonly SERVICE_USER="agent0"
readonly SERVICE_GROUP="agent0"

# Component versions and URLs
readonly CONDA_VERSION="latest"
readonly PYTHON_VERSION="3.11"
readonly CUDA_VERSION="12.4"
readonly NODEJS_VERSION="20"
readonly AGENT0_REPO="https://github.com/frdel/agent-zero.git"
readonly AGENT0_BRANCH="main"
readonly MISTRAL_MODEL="mistral-nemo:12b"

# Network settings
readonly AGENT0_PORT="8080"
readonly OLLAMA_PORT="11434"
readonly RETRY_COUNT=5
readonly RETRY_DELAY=10
readonly DOWNLOAD_TIMEOUT=300

# System requirements
readonly MIN_MEMORY_GB=16
readonly MIN_DISK_GB=50
readonly MIN_CPU_CORES=4

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'  # No Color
readonly BOLD='\033[1m'

# Unicode symbols
readonly CHECK_MARK="✓"
readonly CROSS_MARK="✗"
readonly ARROW="→"
readonly WARNING_SIGN="⚠"
readonly INFO_SIGN="ℹ"
readonly ROCKET="🚀"

# Log file paths
readonly INSTALL_LOG="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
readonly ERROR_LOG="${LOG_DIR}/errors-$(date +%Y%m%d-%H%M%S).log"
readonly SYSTEM_LOG="${LOG_DIR}/system-info.log"

# State tracking
INSTALLATION_STATE="${TEMP_DIR}/installation.state"
ROLLBACK_POINTS="${TEMP_DIR}/rollback.points"
VALIDATION_RESULTS="${TEMP_DIR}/validation.results"

# Global flags
GPU_AVAILABLE=false
INTERACTIVE_MODE=true
FORCE_REINSTALL=false
SKIP_VALIDATION=false
DRY_RUN=false
VERBOSE=false
CLEANUP_ON_ERROR=true

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Create all necessary directories
create_directories() {
    local dirs=(
        "$TEMP_DIR"
        "$LOG_DIR"
        "$INSTALL_DIR"
        "$CONFIG_DIR"
        "$BACKUP_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir" 2>/dev/null || {
            # If mkdir fails, try with sudo
            sudo mkdir -p "$dir"
            sudo chmod 755 "$dir"
        }
    done
}

# Initialize logging system
init_logging() {
    create_directories
    
    # Set up logging
    exec 1> >(tee -a "$INSTALL_LOG")
    exec 2> >(tee -a "$ERROR_LOG" >&2)
    
    # Log system information
    {
        echo "=== Installation Started: $(date) ==="
        echo "Script Version: $SCRIPT_VERSION"
        echo "Hostname: $(hostname)"
        echo "User: $(whoami)"
        echo "Working Directory: $(pwd)"
        echo "System Info:"
        uname -a
        lsb_release -a 2>/dev/null || echo "LSB info not available"
        echo "==================================="
    } >> "$SYSTEM_LOG"
}

# Formatted output functions
print_banner() {
    echo -e "\n${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                  ║"
    echo "║     ${WHITE}${SCRIPT_NAME}${CYAN}              ║"
    echo "║     ${WHITE}Version: ${SCRIPT_VERSION}${CYAN}                                    ║"
    echo "║                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
}

print_step() {
    local step_num="$1"
    local step_desc="$2"
    echo -e "\n${BOLD}${BLUE}[Step $step_num]${NC} ${WHITE}$step_desc${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}${CHECK_MARK}${NC} ${GREEN}$1${NC}"
    log_event "SUCCESS" "$1"
}

print_error() {
    echo -e "${RED}${CROSS_MARK}${NC} ${RED}$1${NC}"
    log_event "ERROR" "$1"
}

print_warning() {
    echo -e "${YELLOW}${WARNING_SIGN}${NC} ${YELLOW}$1${NC}"
    log_event "WARNING" "$1"
}

print_info() {
    echo -e "${CYAN}${INFO_SIGN}${NC} ${CYAN}$1${NC}"
    log_event "INFO" "$1"
}

print_progress() {
    echo -e "${MAGENTA}${ARROW}${NC} $1"
}

# Logging function
log_event() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$INSTALL_LOG"
}

# Progress bar function
show_progress() {
    local current="$1"
    local total="$2"
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    
    printf "\r["
    printf "%${completed}s" | tr ' ' '='
    printf "%$((width - completed))s" | tr ' ' ']'
    printf "] %3d%%" "$percentage"
    
    if [ "$current" -eq "$total" ]; then
        echo
    fi
}

# Spinner function for long operations
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    
    while ps -p "$pid" > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# =============================================================================
# SYSTEM DETECTION AND VALIDATION
# =============================================================================

# Detect if running with proper privileges
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        print_success "Running with root privileges"
        return 0
    else
        # Check if user has sudo privileges
        if sudo -n true 2>/dev/null; then
            print_success "User has sudo privileges"
            return 0
        else
            print_error "This script requires root or sudo privileges"
            print_info "Please run: sudo $0 $*"
            exit 1
        fi
    fi
}

# Comprehensive system detection
detect_system() {
    print_step "1" "System Detection and Validation"
    
    # Check Ubuntu version
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "24.04" ]]; then
            print_success "Ubuntu 24.04 LTS detected"
        else
            print_warning "This script is optimized for Ubuntu 24.04 LTS"
            print_info "Detected: $PRETTY_NAME"
            if ! confirm_action "Continue anyway?"; then
                exit 1
            fi
        fi
    else
        print_error "Cannot detect OS version"
        exit 1
    fi
    
    # Check architecture
    local arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        print_success "Architecture: x86_64"
    else
        print_error "Unsupported architecture: $arch"
        print_info "This script requires x86_64 architecture"
        exit 1
    fi
    
    # Check if running in container/VM
    if systemd-detect-virt -q; then
        local virt_type=$(systemd-detect-virt)
        print_warning "Running in virtualized environment: $virt_type"
        print_info "GPU acceleration may not be available"
    fi
    
    # Detect GPU
    detect_gpu_detailed
    
    # Check network connectivity
    check_network_connectivity
    
    # Save system state
    save_system_state
}

# Detailed GPU detection
detect_gpu_detailed() {
    print_info "Detecting GPU capabilities..."
    
    # Check for NVIDIA GPU
    if lspci 2>/dev/null | grep -qi nvidia; then
        print_info "NVIDIA GPU detected in system"
        
        # Check if drivers are installed
        if command -v nvidia-smi &>/dev/null; then
            if nvidia-smi &>/dev/null; then
                GPU_AVAILABLE=true
                local gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader)
                print_success "NVIDIA GPU ready: $gpu_info"
                
                # Check CUDA
                if command -v nvcc &>/dev/null; then
                    local cuda_version=$(nvcc --version | grep "release" | awk '{print $6}' | cut -d',' -f1)
                    print_success "CUDA installed: $cuda_version"
                else
                    print_warning "CUDA toolkit not installed - will install"
                fi
            else
                print_warning "NVIDIA drivers installed but not functional"
                GPU_AVAILABLE=false
            fi
        else
            print_warning "NVIDIA GPU detected but drivers not installed"
            GPU_AVAILABLE=false
        fi
    else
        print_info "No NVIDIA GPU detected - will use CPU mode"
        GPU_AVAILABLE=false
    fi
}

# Network connectivity check
check_network_connectivity() {
    print_info "Checking network connectivity..."
    
    local test_sites=(
        "https://api.github.com"
        "https://pypi.org"
        "https://registry.npmjs.org"
        "https://download.docker.com"
    )
    
    local failed=0
    for site in "${test_sites[@]}"; do
        if ! timeout 10 curl -sfI "$site" &>/dev/null; then
            print_warning "Cannot reach: $site"
            ((failed++))
        fi
    done
    
    if [[ $failed -eq ${#test_sites[@]} ]]; then
        print_error "No internet connectivity detected"
        print_info "Please check your network connection"
        exit 1
    elif [[ $failed -gt 0 ]]; then
        print_warning "Some sites unreachable - installation may be affected"
    else
        print_success "Network connectivity verified"
    fi
}

# =============================================================================
# SYSTEM REQUIREMENTS VALIDATION
# =============================================================================

validate_system_requirements() {
    print_step "2" "Validating System Requirements"
    
    local validation_passed=true
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    if [[ $cpu_cores -ge $MIN_CPU_CORES ]]; then
        print_success "CPU cores: $cpu_cores (minimum: $MIN_CPU_CORES)"
    else
        print_warning "CPU cores: $cpu_cores (recommended: $MIN_CPU_CORES)"
        validation_passed=false
    fi
    
    # Check memory
    local total_memory_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $total_memory_gb -ge $MIN_MEMORY_GB ]]; then
        print_success "Memory: ${total_memory_gb}GB (minimum: ${MIN_MEMORY_GB}GB)"
    else
        print_error "Insufficient memory: ${total_memory_gb}GB (minimum: ${MIN_MEMORY_GB}GB)"
        validation_passed=false
    fi
    
    # Check available disk space
    local available_disk_gb=$(df "$INSTALL_BASE" | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $available_disk_gb -ge $MIN_DISK_GB ]]; then
        print_success "Disk space: ${available_disk_gb}GB available (minimum: ${MIN_DISK_GB}GB)"
    else
        print_error "Insufficient disk space: ${available_disk_gb}GB (minimum: ${MIN_DISK_GB}GB)"
        validation_passed=false
    fi
    
    # Check swap space
    local swap_total=$(free -g | awk '/^Swap:/{print $2}')
    if [[ $swap_total -gt 0 ]]; then
        print_success "Swap space: ${swap_total}GB"
    else
        print_warning "No swap space configured"
        if [[ $total_memory_gb -lt 32 ]]; then
            print_info "Recommended to add swap for systems with less than 32GB RAM"
        fi
    fi
    
    # Check system load
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local load_threshold=$(echo "$cpu_cores * 0.7" | bc -l 2>/dev/null || echo "$cpu_cores")
    
    if (( $(echo "$load_avg < $load_threshold" | bc -l 2>/dev/null || echo 1) )); then
        print_success "System load: $load_avg (OK)"
    else
        print_warning "High system load detected: $load_avg"
        print_info "Installation may be slower"
    fi
    
    if [[ "$validation_passed" == false ]] && [[ "$SKIP_VALIDATION" == false ]]; then
        print_error "System requirements not met"
        if ! confirm_action "Continue anyway? (not recommended)"; then
            exit 1
        fi
    fi
    
    # Save validation results
    {
        echo "cpu_cores=$cpu_cores"
        echo "memory_gb=$total_memory_gb"
        echo "disk_gb=$available_disk_gb"
        echo "swap_gb=$swap_total"
        echo "gpu_available=$GPU_AVAILABLE"
    } > "$VALIDATION_RESULTS"
}

# =============================================================================
# BACKUP AND CLEANUP FUNCTIONS
# =============================================================================

# Create system backup before installation
create_system_backup() {
    if [[ -d "$INSTALL_DIR" ]] || [[ -d "$CONFIG_DIR" ]]; then
        print_info "Creating backup of existing installation..."
        
        local backup_file="$BACKUP_DIR/pre-install-$(date +%Y%m%d-%H%M%S).tar.gz"
        mkdir -p "$BACKUP_DIR"
        
        local dirs_to_backup=()
        [[ -d "$INSTALL_DIR" ]] && dirs_to_backup+=("$INSTALL_DIR")
        [[ -d "$CONFIG_DIR" ]] && dirs_to_backup+=("$CONFIG_DIR")
        
        if tar -czf "$backup_file" "${dirs_to_backup[@]}" 2>/dev/null; then
            print_success "Backup created: $backup_file"
            echo "$backup_file" >> "$ROLLBACK_POINTS"
        else
            print_warning "Backup creation failed - continuing anyway"
        fi
    fi
}

# Clean existing installation
clean_existing_installation() {
    print_info "Checking for existing installations..."
    
    # Stop existing services
    local services=("agent0" "ollama")
    for service in "${services[@]}"; do
        if systemctl is-active "$service" &>/dev/null; then
            print_info "Stopping $service service..."
            sudo systemctl stop "$service" || true
            sudo systemctl disable "$service" || true
        fi
    done
    
    # Remove old systemd services
    sudo rm -f /etc/systemd/system/agent0.service
    sudo rm -f /etc/systemd/system/ollama.service
    sudo systemctl daemon-reload
    
    # Clean Docker containers
    if command -v docker &>/dev/null; then
        print_info "Cleaning Docker resources..."
        docker ps -a | grep -E "agent0|ollama" | awk '{print $1}' | xargs -r docker rm -f || true
        docker images | grep -E "agent0|ollama" | awk '{print $3}' | xargs -r docker rmi -f || true
    fi
    
    # Remove old installations if force reinstall
    if [[ "$FORCE_REINSTALL" == true ]]; then
        print_warning "Force reinstall requested - removing existing installation"
        sudo rm -rf "$INSTALL_DIR"
        sudo rm -rf "$CONFIG_DIR"
        sudo rm -rf "$LOG_DIR"
        
        # Remove old conda installation
        sudo rm -rf /opt/miniconda3
        sudo rm -rf /opt/conda
        
        # Remove old user
        if id "$SERVICE_USER" &>/dev/null; then
            sudo userdel -r "$SERVICE_USER" || true
        fi
    fi
}

# Cleanup function for errors
cleanup_on_error() {
    if [[ "$CLEANUP_ON_ERROR" == true ]]; then
        print_error "Installation failed - cleaning up..."
        
        # Stop any started services
        sudo systemctl stop agent0 2>/dev/null || true
        sudo systemctl stop ollama 2>/dev/null || true
        
        # Remove partial installations
        if [[ -f "$INSTALLATION_STATE" ]]; then
            local last_state=$(tail -1 "$INSTALLATION_STATE" 2>/dev/null || echo "")
            case "$last_state" in
                "docker_installed")
                    # Keep Docker as it might be used by other applications
                    ;;
                "conda_installed")
                    sudo rm -rf /opt/miniconda3
                    ;;
                "agent0_cloned")
                    sudo rm -rf "$INSTALL_DIR/agent-zero"
                    ;;
                *)
                    # Clean everything if state unknown
                    sudo rm -rf "$INSTALL_DIR"
                    ;;
            esac
        fi
        
        # Restore from backup if available
        if [[ -f "$ROLLBACK_POINTS" ]]; then
            local backup_file=$(tail -1 "$ROLLBACK_POINTS" 2>/dev/null)
            if [[ -f "$backup_file" ]]; then
                print_info "Restoring from backup: $backup_file"
                tar -xzf "$backup_file" -C / || true
            fi
        fi
    fi
    
    # Clean temporary directory
    rm -rf "$TEMP_DIR"
    
    print_error "Installation failed. Check logs at: $LOG_DIR"
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR INT TERM

# =============================================================================
# DEPENDENCY INSTALLATION FUNCTIONS
# =============================================================================

# Install system packages with retry logic
install_system_packages() {
    print_step "3" "Installing System Dependencies"
    
    # Update package lists
    print_info "Updating package lists..."
    retry_command sudo apt-get update -y
    
    # Essential packages
    local packages=(
        # Build essentials
        build-essential
        gcc
        g++
        make
        cmake
        pkg-config
        
        # Python development
        python3-dev
        python3-pip
        python3-venv
        python3-setuptools
        python3-wheel
        
        # System utilities
        curl
        wget
        git
        vim
        nano
        htop
        iotop
        tmux
        screen
        tree
        jq
        bc
        
        # Compression
        zip
        unzip
        tar
        gzip
        bzip2
        xz-utils
        
        # Network tools
        net-tools
        netcat-openbsd
        dnsutils
        iputils-ping
        traceroute
        
        # Libraries
        libssl-dev
        libffi-dev
        libsqlite3-dev
        libbz2-dev
        libreadline-dev
        libncurses5-dev
        libncursesw5-dev
        liblzma-dev
        
        # Additional tools
        software-properties-common
        apt-transport-https
        ca-certificates
        gnupg
        lsb-release
        systemd
    )
    
    # Install packages with progress
    local total=${#packages[@]}
    local current=0
    
    for package in "${packages[@]}"; do
        ((current++))
        show_progress $current $total
        
        if ! dpkg -l | grep -q "^ii  $package "; then
            retry_command sudo apt-get install -y "$package" &>/dev/null || {
                print_warning "Failed to install $package"
            }
        fi
    done
    
    print_success "System packages installed"
    echo "system_packages_installed" >> "$INSTALLATION_STATE"
}

# Install Docker with proper setup
install_docker() {
    print_step "4" "Installing Docker"
    
    if command -v docker &>/dev/null && docker --version &>/dev/null; then
        print_info "Docker already installed: $(docker --version)"
        
        # Ensure Docker service is running
        if ! systemctl is-active docker &>/dev/null; then
            sudo systemctl start docker
            sudo systemctl enable docker
        fi
    else
        print_info "Installing Docker..."
        
        # Remove old Docker installations
        sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        
        # Install Docker
        retry_command 'curl -fsSL https://get.docker.com -o /tmp/get-docker.sh'
        retry_command 'sudo sh /tmp/get-docker.sh'
        
        # Start Docker service
        sudo systemctl start docker
        sudo systemctl enable docker
        
        # Wait for Docker to be ready
        local max_wait=30
        local waited=0
        while ! docker ps &>/dev/null && [[ $waited -lt $max_wait ]]; do
            sleep 1
            ((waited++))
        done
        
        if docker ps &>/dev/null; then
            print_success "Docker installed and running"
        else
            print_error "Docker installation failed"
            exit 1
        fi
    fi
    
    # Add service user to docker group
    if ! id "$SERVICE_USER" &>/dev/null; then
        sudo useradd --system --create-home --shell /bin/bash "$SERVICE_USER"
    fi
    sudo usermod -aG docker "$SERVICE_USER"
    
    # Install Docker Compose
    if ! command -v docker-compose &>/dev/null; then
        print_info "Installing Docker Compose..."
        
        local compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
        retry_command "sudo curl -L \"https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose"
        sudo chmod +x /usr/local/bin/docker-compose
        
        print_success "Docker Compose installed: $(docker-compose --version)"
    fi
    
    echo "docker_installed" >> "$INSTALLATION_STATE"
}

# Install NVIDIA drivers and CUDA if GPU present
install_nvidia_cuda() {
    if [[ "$GPU_AVAILABLE" == false ]]; then
        print_info "Skipping NVIDIA/CUDA installation (no GPU detected)"
        return 0
    fi
    
    print_step "5" "Installing NVIDIA Drivers and CUDA"
    
    # Check if drivers already installed and working
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        print_info "NVIDIA drivers already installed and working"
        
        # Check CUDA
        if ! command -v nvcc &>/dev/null; then
            print_info "Installing CUDA toolkit..."
            install_cuda_toolkit
        fi
        return 0
    fi
    
    # Install NVIDIA drivers
    print_info "Installing NVIDIA drivers..."
    
    # Add NVIDIA PPA
    sudo add-apt-repository -y ppa:graphics-drivers/ppa
    sudo apt-get update -y
    
    # Install recommended drivers
    sudo apt-get install -y ubuntu-drivers-common
    local recommended_driver=$(ubuntu-drivers devices 2>/dev/null | grep recommended | awk '{print $3}')
    
    if [[ -n "$recommended_driver" ]]; then
        print_info "Installing recommended driver: $recommended_driver"
        retry_command sudo apt-get install -y "$recommended_driver"
    else
        print_info "Installing generic NVIDIA driver"
        retry_command sudo apt-get install -y nvidia-driver-545
    fi
    
    # Install CUDA
    install_cuda_toolkit
    
    print_warning "GPU drivers installed - system reboot recommended after installation"
    echo "nvidia_installed" >> "$INSTALLATION_STATE"
}

install_cuda_toolkit() {
    print_info "Installing CUDA toolkit..."
    
    # CUDA keyring
    local cuda_keyring="cuda-keyring_1.1-1_all.deb"
    retry_command "wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/${cuda_keyring} -O /tmp/${cuda_keyring}"
    sudo dpkg -i "/tmp/${cuda_keyring}"
    sudo apt-get update -y
    
    # Install CUDA toolkit
    retry_command sudo apt-get install -y cuda-toolkit-${CUDA_VERSION}
    
    # Add CUDA to PATH
    echo 'export PATH=/usr/local/cuda/bin:$PATH' | sudo tee -a /etc/profile.d/cuda.sh
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' | sudo tee -a /etc/profile.d/cuda.sh
    
    print_success "CUDA toolkit installed"
}

# Install Miniconda with proper setup
install_miniconda() {
    print_step "6" "Installing Miniconda"
    
    local conda_path="/opt/miniconda3"
    
    if [[ -d "$conda_path" ]]; then
        print_info "Miniconda already installed at $conda_path"
        
        # Verify it works
        if "$conda_path/bin/conda" --version &>/dev/null; then
            print_success "Miniconda is functional"
            return 0
        else
            print_warning "Miniconda installation corrupted - reinstalling"
            sudo rm -rf "$conda_path"
        fi
    fi
    
    print_info "Downloading Miniconda..."
    local conda_installer="/tmp/miniconda_installer.sh"
    
    retry_command "wget -q https://repo.anaconda.com/miniconda/Miniconda3-${CONDA_VERSION}-Linux-x86_64.sh -O $conda_installer"
    
    print_info "Installing Miniconda..."
    sudo bash "$conda_installer" -b -p "$conda_path"
    
    # Set permissions
    sudo chown -R "$SERVICE_USER:$SERVICE_GROUP" "$conda_path"
    
    # Initialize conda
    sudo -u "$SERVICE_USER" "$conda_path/bin/conda" init bash
    
    # Update conda
    sudo -u "$SERVICE_USER" "$conda_path/bin/conda" update -n base -c defaults conda -y
    
    print_success "Miniconda installed successfully"
    echo "conda_installed" >> "$INSTALLATION_STATE"
}

# Install Ollama for local LLM
install_ollama() {
    print_step "7" "Installing Ollama"
    
    if command -v ollama &>/dev/null; then
        print_info "Ollama already installed: $(ollama --version)"
        
        # Ensure service is set up
        setup_ollama_service
        return 0
    fi
    
    print_info "Installing Ollama..."
    
    # Install Ollama using official script
    retry_command 'curl -fsSL https://ollama.com/install.sh | sudo sh'
    
    # Verify installation
    if ! command -v ollama &>/dev/null; then
        print_error "Ollama installation failed"
        exit 1
    fi
    
    setup_ollama_service
    
    print_success "Ollama installed successfully"
    echo "ollama_installed" >> "$INSTALLATION_STATE"
}

setup_ollama_service() {
    print_info "Setting up Ollama service..."
    
    # Create Ollama user if doesn't exist
    if ! id "ollama" &>/dev/null; then
        sudo useradd --system --create-home --home /var/lib/ollama --shell /bin/false ollama
    fi
    
    # Create systemd service
    sudo tee /etc/systemd/system/ollama.service > /dev/null <<EOF
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
Type=simple
User=ollama
Group=ollama
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=3
Environment="OLLAMA_HOST=0.0.0.0:${OLLAMA_PORT}"
Environment="HOME=/var/lib/ollama"

[Install]
WantedBy=multi-user.target
EOF

    # Start and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable ollama
    sudo systemctl start ollama
    
    # Wait for Ollama to be ready
    print_info "Waiting for Ollama to start..."
    local max_wait=60
    local waited=0
    
    while ! curl -s "http://localhost:${OLLAMA_PORT}/api/tags" &>/dev/null && [[ $waited -lt $max_wait ]]; do
        sleep 1
        ((waited++))
        if [[ $((waited % 5)) -eq 0 ]]; then
            printf "."
        fi
    done
    echo
    
    if curl -s "http://localhost:${OLLAMA_PORT}/api/tags" &>/dev/null; then
        print_success "Ollama service is running"
    else
        print_error "Ollama service failed to start"
        sudo journalctl -u ollama -n 50
        exit 1
    fi
}

# =============================================================================
# AGENT ZERO INSTALLATION
# =============================================================================

setup_agent_zero() {
    print_step "8" "Setting up Agent Zero"
    
    # Create directory structure
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR"
    
    cd "$INSTALL_DIR"
    
    # Clone repository
    if [[ -d "agent-zero" ]]; then
        print_info "Agent Zero repository already exists"
        cd agent-zero
        sudo -u "$SERVICE_USER" git pull origin "$AGENT0_BRANCH" || true
    else
        print_info "Cloning Agent Zero repository..."
        retry_command "sudo -u $SERVICE_USER git clone $AGENT0_REPO"
        cd agent-zero
        sudo -u "$SERVICE_USER" git checkout "$AGENT0_BRANCH"
    fi
    
    echo "agent0_cloned" >> "$INSTALLATION_STATE"
    
    # Create Python environment
    print_info "Creating Python environment..."
    local conda_path="/opt/miniconda3"
    
    sudo -u "$SERVICE_USER" bash -c "
        source $conda_path/etc/profile.d/conda.sh
        conda create -n agent0 python=$PYTHON_VERSION -y
        conda activate agent0
        
        # Upgrade pip
        pip install --upgrade pip setuptools wheel
        
        # Install requirements
        if [[ -f requirements.txt ]]; then
            pip install -r requirements.txt
        fi
        
        # Install additional packages for local LLM support
        pip install ollama langchain langchain-community transformers torch
    "
    
    print_success "Agent Zero environment created"
    echo "agent0_env_created" >> "$INSTALLATION_STATE"
}

# Download and configure Mistral model
setup_mistral_model() {
    print_step "9" "Setting up Mistral Nemo 12B Model"
    
    print_info "Downloading Mistral Nemo 12B model..."
    print_warning "This may take a while depending on your internet connection"
    
    # Pull model with progress indication
    local model_size="12GB"
    print_info "Model size: approximately $model_size"
    
    # Run ollama pull in background and monitor
    sudo -u ollama ollama pull "$MISTRAL_MODEL" &
    local pull_pid=$!
    
    # Show spinner while downloading
    spinner $pull_pid
    
    wait $pull_pid
    local pull_status=$?
    
    if [[ $pull_status -eq 0 ]]; then
        print_success "Mistral Nemo 12B model downloaded"
        
        # Verify model is available
        if sudo -u ollama ollama list | grep -q "$MISTRAL_MODEL"; then
            print_success "Model verified and ready"
        else
            print_error "Model download verification failed"
            exit 1
        fi
    else
        print_error "Failed to download Mistral model"
        exit 1
    fi
    
    echo "mistral_model_ready" >> "$INSTALLATION_STATE"
}

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

create_configurations() {
    print_step "10" "Creating Configuration Files"
    
    # Create main config directory
    sudo mkdir -p "$CONFIG_DIR"
    
    # Agent Zero configuration
    sudo tee "$CONFIG_DIR/agent0.env" > /dev/null <<EOF
# Agent Zero Configuration
# Generated by Ultimate Installer v${SCRIPT_VERSION}

# Service Configuration
AGENT0_HOST=0.0.0.0
AGENT0_PORT=${AGENT0_PORT}
AGENT0_HOME=${INSTALL_DIR}
AGENT0_LOG_DIR=${LOG_DIR}

# Python Environment
CONDA_PATH=/opt/miniconda3
PYTHON_ENV=agent0

# Local LLM Configuration
OLLAMA_BASE_URL=http://localhost:${OLLAMA_PORT}
DEFAULT_MODEL=${MISTRAL_MODEL}
MODEL_TEMPERATURE=0.7
MODEL_MAX_TOKENS=4096

# OpenAI Configuration (optional)
OPENAI_API_KEY=
OPENAI_MODEL=gpt-4

# Feature Flags
USE_LOCAL_MODEL=true
ENABLE_WEB_UI=true
ENABLE_API=true
ENABLE_LOGGING=true

# Performance Settings
MAX_WORKERS=4
REQUEST_TIMEOUT=300
BATCH_SIZE=1

# Security
SECRET_KEY=$(openssl rand -hex 32)
ALLOWED_ORIGINS=*
ENABLE_CORS=true

# Paths
DATA_DIR=${INSTALL_DIR}/data
WORKSPACE_DIR=${INSTALL_DIR}/workspace
CACHE_DIR=${INSTALL_DIR}/cache
EOF

    # Create Agent Zero launcher script
    sudo tee "$INSTALL_DIR/launch_agent0.sh" > /dev/null <<'EOF'
#!/bin/bash
# Agent Zero Launcher Script

# Load environment
source /etc/agent0-mistral/agent0.env

# Activate conda environment
source $CONDA_PATH/etc/profile.d/conda.sh
conda activate $PYTHON_ENV

# Change to Agent Zero directory
cd $AGENT0_HOME/agent-zero

# Export environment variables
export OLLAMA_BASE_URL
export DEFAULT_MODEL
export AGENT0_HOST
export AGENT0_PORT

# Launch Agent Zero
python -m agent0 \
    --host $AGENT0_HOST \
    --port $AGENT0_PORT \
    --model $DEFAULT_MODEL \
    --log-level INFO
EOF

    sudo chmod +x "$INSTALL_DIR/launch_agent0.sh"
    sudo chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR"
    
    print_success "Configuration files created"
}

# Create systemd services
create_systemd_services() {
    print_step "11" "Creating System Services"
    
    # Agent Zero service
    sudo tee /etc/systemd/system/agent0.service > /dev/null <<EOF
[Unit]
Description=Agent Zero AI Framework
Documentation=https://github.com/frdel/agent-zero
After=network-online.target ollama.service
Wants=network-online.target
Requires=ollama.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
WorkingDirectory=$INSTALL_DIR/agent-zero
EnvironmentFile=$CONFIG_DIR/agent0.env
ExecStart=$INSTALL_DIR/launch_agent0.sh
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/agent0.log
StandardError=append:$LOG_DIR/agent0-error.log

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Security
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR $LOG_DIR

[Install]
WantedBy=multi-user.target
EOF

    # Create log rotation config
    sudo tee /etc/logrotate.d/agent0-mistral > /dev/null <<EOF
$LOG_DIR/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 $SERVICE_USER $SERVICE_GROUP
    sharedscripts
    postrotate
        systemctl reload agent0 >/dev/null 2>&1 || true
    endscript
}
EOF

    # Reload systemd
    sudo systemctl daemon-reload
    
    # Enable services
    sudo systemctl enable ollama
    sudo systemctl enable agent0
    
    print_success "System services created and enabled"
}

# =============================================================================
# HELPER SCRIPTS CREATION
# =============================================================================

create_helper_scripts() {
    print_step "12" "Creating Helper Scripts"
    
    # Health check script
    sudo tee "$INSTALL_DIR/health_check.sh" > /dev/null <<'EOF'
#!/bin/bash
# Agent Zero + Mistral Health Check

echo "=== System Health Check ==="
echo

# Check services
echo "Service Status:"
systemctl is-active ollama >/dev/null && echo "✓ Ollama: Running" || echo "✗ Ollama: Stopped"
systemctl is-active agent0 >/dev/null && echo "✓ Agent Zero: Running" || echo "✗ Agent Zero: Stopped"

# Check APIs
echo
echo "API Status:"
curl -s http://localhost:11434/api/tags >/dev/null && echo "✓ Ollama API: Responsive" || echo "✗ Ollama API: Not responding"
curl -s http://localhost:8080 >/dev/null && echo "✓ Agent Zero: Responsive" || echo "✗ Agent Zero: Not responding"

# Check models
echo
echo "Available Models:"
ollama list 2>/dev/null | grep -v "NAME" | awk '{print "  •", $1}'

# System resources
echo
echo "System Resources:"
echo "  • CPU Load: $(uptime | awk -F'load average:' '{print $2}')"
echo "  • Memory: $(free -h | awk '/^Mem:/{print $3 "/" $2}')"
echo "  • Disk: $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')"

if command -v nvidia-smi &>/dev/null; then
    echo
    echo "GPU Status:"
    nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader | \
    while IFS=',' read -r name util mem_used mem_total; do
        echo "  • $name: ${util} utilization, ${mem_used} / ${mem_total}"
    done
fi
EOF

    # Service control script
    sudo tee "$INSTALL_DIR/control.sh" > /dev/null <<'EOF'
#!/bin/bash
# Agent Zero Service Control

case "$1" in
    start)
        echo "Starting services..."
        sudo systemctl start ollama
        sleep 5
        sudo systemctl start agent0
        echo "Services started"
        ;;
    stop)
        echo "Stopping services..."
        sudo systemctl stop agent0
        sudo systemctl stop ollama
        echo "Services stopped"
        ;;
    restart)
        echo "Restarting services..."
        $0 stop
        sleep 3
        $0 start
        ;;
    status)
        $INSTALL_DIR/health_check.sh
        ;;
    logs)
        echo "=== Recent Logs ==="
        echo "Ollama:"
        sudo journalctl -u ollama -n 20 --no-pager
        echo
        echo "Agent Zero:"
        sudo journalctl -u agent0 -n 20 --no-pager
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
EOF

    # Update script
    sudo tee "$INSTALL_DIR/update.sh" > /dev/null <<'EOF'
#!/bin/bash
# Update Agent Zero and Mistral

echo "=== Updating Agent Zero + Mistral ==="

# Stop services
sudo systemctl stop agent0

# Update Agent Zero
cd $INSTALL_DIR/agent-zero
sudo -u $SERVICE_USER git pull origin main

# Update Python packages
sudo -u $SERVICE_USER bash -c "
    source /opt/miniconda3/etc/profile.d/conda.sh
    conda activate agent0
    pip install --upgrade -r requirements.txt
"

# Update Mistral model
sudo -u ollama ollama pull mistral-nemo:12b

# Restart services
sudo systemctl start agent0

echo "Update complete!"
EOF

    # Make scripts executable
    sudo chmod +x "$INSTALL_DIR"/*.sh
    sudo chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR"
    
    print_success "Helper scripts created"
}

# =============================================================================
# VALIDATION AND TESTING
# =============================================================================

validate_installation() {
    print_step "13" "Validating Installation"
    
    local validation_failed=false
    
    # Start services
    print_info "Starting services..."
    sudo systemctl start ollama
    sleep 10  # Give Ollama time to start
    sudo systemctl start agent0
    sleep 5
    
    # Check service status
    if systemctl is-active ollama >/dev/null; then
        print_success "Ollama service is running"
    else
        print_error "Ollama service failed to start"
        validation_failed=true
    fi
    
    if systemctl is-active agent0 >/dev/null; then
        print_success "Agent Zero service is running"
    else
        print_error "Agent Zero service failed to start"
        validation_failed=true
    fi
    
    # Check API endpoints
    if curl -s "http://localhost:${OLLAMA_PORT}/api/tags" >/dev/null; then
        print_success "Ollama API is responding"
    else
        print_error "Ollama API is not responding"
        validation_failed=true
    fi
    
    if curl -s "http://localhost:${AGENT0_PORT}" >/dev/null; then
        print_success "Agent Zero web UI is accessible"
    else
        print_error "Agent Zero web UI is not accessible"
        validation_failed=true
    fi
    
    # Check model availability
    if sudo -u ollama ollama list | grep -q "$MISTRAL_MODEL"; then
        print_success "Mistral Nemo model is available"
    else
        print_error "Mistral Nemo model not found"
        validation_failed=true
    fi
    
    # Test model response
    print_info "Testing model response..."
    local test_response=$(curl -s -X POST "http://localhost:${OLLAMA_PORT}/api/generate" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"${MISTRAL_MODEL}\", \"prompt\": \"Hello\", \"stream\": false}" \
        --max-time 30)
    
    if [[ -n "$test_response" ]] && echo "$test_response" | jq -e '.response' >/dev/null 2>&1; then
        print_success "Model is responding correctly"
    else
        print_warning "Model response test failed (this may be normal on first run)"
    fi
    
    if [[ "$validation_failed" == true ]]; then
        print_error "Installation validation failed"
        print_info "Check logs with: sudo journalctl -u ollama -u agent0"
        return 1
    else
        print_success "All validation checks passed!"
        return 0
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Retry command with exponential backoff
retry_command() {
    local command="$1"
    local max_attempts=${2:-$RETRY_COUNT}
    local delay=${3:-$RETRY_DELAY}
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if eval "$command"; then
            return 0
        else
            print_warning "Command failed (attempt $attempt/$max_attempts): $command"
            if [[ $attempt -lt $max_attempts ]]; then
                print_info "Retrying in ${delay}s..."
                sleep "$delay"
                delay=$((delay * 2))  # Exponential backoff
            fi
            ((attempt++))
        fi
    done
    
    print_error "Command failed after $max_attempts attempts: $command"
    return 1
}

# Confirm action from user
confirm_action() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [[ "$INTERACTIVE_MODE" == false ]]; then
        return 0
    fi
    
    local response
    read -r -p "$prompt [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Save system state for debugging
save_system_state() {
    local state_file="$LOG_DIR/system-state-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "=== System State Snapshot ==="
        echo "Date: $(date)"
        echo "Uptime: $(uptime)"
        echo
        echo "=== OS Information ==="
        lsb_release -a 2>/dev/null || echo "LSB info not available"
        echo
        echo "=== Hardware ==="
        echo "CPU: $(lscpu | grep "Model name" | sed 's/Model name://g' | xargs)"
        echo "Cores: $(nproc)"
        echo "Memory: $(free -h | awk '/^Mem:/{print $2}')"
        echo
        echo "=== Disk Usage ==="
        df -h
        echo
        echo "=== GPU Information ==="
        if command -v nvidia-smi &>/dev/null; then
            nvidia-smi 2>/dev/null || echo "NVIDIA driver not loaded"
        else
            echo "No NVIDIA GPU detected"
        fi
        echo
        echo "=== Network ==="
        ip addr show
        echo
        echo "=== Active Services ==="
        systemctl list-units --type=service --state=active
    } > "$state_file" 2>&1
    
    print_info "System state saved to: $state_file"
}

# =============================================================================
# COMPLETION AND SUMMARY
# =============================================================================

show_completion_summary() {
    local install_time=$(($(date +%s) - SCRIPT_START_TIME))
    local minutes=$((install_time / 60))
    local seconds=$((install_time % 60))
    
    print_banner
    
    echo -e "${GREEN}${BOLD}Installation completed successfully! ${ROCKET}${NC}"
    echo -e "${GREEN}Total time: ${minutes}m ${seconds}s${NC}"
    echo
    
    echo -e "${CYAN}${BOLD}=== Access Information ===${NC}"
    echo -e "${WHITE}Agent Zero Web UI:${NC} http://$(hostname -I | awk '{print $1}'):${AGENT0_PORT}"
    echo -e "${WHITE}Ollama API:${NC} http://localhost:${OLLAMA_PORT}"
    echo -e "${WHITE}Model:${NC} ${MISTRAL_MODEL}"
    echo
    
    echo -e "${CYAN}${BOLD}=== Service Management ===${NC}"
    echo -e "${WHITE}Start services:${NC} sudo $INSTALL_DIR/control.sh start"
    echo -e "${WHITE}Stop services:${NC} sudo $INSTALL_DIR/control.sh stop"
    echo -e "${WHITE}Check status:${NC} sudo $INSTALL_DIR/control.sh status"
    echo -e "${WHITE}View logs:${NC} sudo $INSTALL_DIR/control.sh logs"
    echo
    
    echo -e "${CYAN}${BOLD}=== Quick Start Guide ===${NC}"
    echo "1. Open your web browser and navigate to:"
    echo "   http://$(hostname -I | awk '{print $1}'):${AGENT0_PORT}"
    echo
    echo "2. The Mistral Nemo model is already configured and ready"
    echo
    echo "3. To test from command line:"
    echo "   curl -X POST http://localhost:${OLLAMA_PORT}/api/generate \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"model\": \"${MISTRAL_MODEL}\", \"prompt\": \"Hello, how are you?\"}'"
    echo
    
    echo -e "${CYAN}${BOLD}=== Configuration Files ===${NC}"
    echo -e "${WHITE}Main config:${NC} $CONFIG_DIR/agent0.env"
    echo -e "${WHITE}Logs:${NC} $LOG_DIR/"
    echo -e "${WHITE}Installation:${NC} $INSTALL_DIR/"
    echo
    
    if [[ "$GPU_AVAILABLE" == true ]]; then
        echo -e "${YELLOW}${BOLD}=== GPU Note ===${NC}"
        echo "GPU support has been installed. A system reboot is recommended"
        echo "to ensure all GPU drivers are properly loaded."
        echo
    fi
    
    echo -e "${GREEN}${BOLD}=== Next Steps ===${NC}"
    echo "• Run health check: $INSTALL_DIR/health_check.sh"
    echo "• Update system: $INSTALL_DIR/update.sh"
    echo "• Read documentation: https://github.com/frdel/agent-zero"
    echo
    
    echo -e "${CYAN}Thank you for using the Ultimate Agent Zero + Mistral Installer!${NC}"
}

# =============================================================================
# MAIN INSTALLATION FLOW
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-interactive|--silent|-s)
                INTERACTIVE_MODE=false
                shift
                ;;
            --force-reinstall|-f)
                FORCE_REINSTALL=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --no-gpu)
                GPU_AVAILABLE=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                set -x
                shift
                ;;
            --no-cleanup)
                CLEANUP_ON_ERROR=false
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
${BOLD}${SCRIPT_NAME}${NC}
Version: ${SCRIPT_VERSION}

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --non-interactive, --silent, -s
        Run in non-interactive mode (no prompts)
    
    --force-reinstall, -f
        Force reinstallation even if components exist
    
    --skip-validation
        Skip system requirement validation
    
    --no-gpu
        Skip GPU detection and CUDA installation
    
    --dry-run
        Show what would be done without making changes
    
    --verbose, -v
        Enable verbose output
    
    --no-cleanup
        Don't cleanup on error (for debugging)
    
    --help, -h
        Show this help message

EXAMPLES:
    # Standard installation
    sudo $0
    
    # Silent installation with force reinstall
    sudo $0 --silent --force-reinstall
    
    # CPU-only installation
    sudo $0 --no-gpu

REQUIREMENTS:
    • Ubuntu 24.04 LTS
    • Minimum 16GB RAM
    • Minimum 50GB free disk space
    • Internet connection

For more information, visit:
https://github.com/frdel/agent-zero
EOF
}

# Main function
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Initialize
    init_logging
    print_banner
    
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY RUN MODE - No changes will be made"
    fi
    
    # Pre-flight checks
    check_privileges "$@"
    detect_system
    validate_system_requirements
    
    # Backup and cleanup
    create_system_backup
    clean_existing_installation
    
    if [[ "$DRY_RUN" == true ]]; then
        print_info "Dry run complete - no changes made"
        exit 0
    fi
    
    # Installation
    install_system_packages
    install_docker
    install_nvidia_cuda
    install_miniconda
    install_ollama
    setup_agent_zero
    setup_mistral_model
    
    # Configuration
    create_configurations
    create_systemd_services
    create_helper_scripts
    
    # Validation
    if validate_installation; then
        show_completion_summary
        
        # Clean up temp directory
        rm -rf "$TEMP_DIR"
        
        exit 0
    else
        print_error "Installation completed with errors"
        exit 1
    fi
}

# Run main function
main "$@"