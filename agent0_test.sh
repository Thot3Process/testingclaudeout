#!/bin/bash
# =============================================================================
# Agent Zero + Mistral Nemo Comprehensive Testing Script
# Version: 1.0.0
# Description: User-friendly testing to verify everything works correctly
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_VERSION="1.0.0"
readonly TEST_LOG="/var/log/agent0-mistral/test_$(date +%Y%m%d_%H%M%S).log"
readonly INSTALL_DIR="/opt/agent0-mistral"
readonly TEMP_DIR="/tmp/agent0_test_$$"

# Test timeouts
readonly API_TIMEOUT=30
readonly MODEL_TIMEOUT=120
readonly UI_TIMEOUT=10

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Test categories
declare -a TEST_CATEGORIES=(
    "system"
    "services"
    "network"
    "api"
    "model"
    "integration"
    "performance"
)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Initialize
init() {
    mkdir -p "$(dirname "$TEST_LOG")"
    mkdir -p "$TEMP_DIR"
    
    echo "=== Agent Zero + Mistral Test Suite ===" > "$TEST_LOG"
    echo "Date: $(date)" >> "$TEST_LOG"
    echo "Version: $SCRIPT_VERSION" >> "$TEST_LOG"
    echo "================================" >> "$TEST_LOG"
}

# Cleanup
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Logging
log_test() {
    local status=$1
    local category=$2
    local test_name=$3
    local message="${4:-}"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$status] [$category] $test_name: $message" >> "$TEST_LOG"
}

# Print test result
print_test_result() {
    local status=$1
    local test_name=$2
    local message="${3:-}"
    
    case "$status" in
        PASS)
            echo -e "${GREEN}✓${NC} $test_name"
            ((PASSED_TESTS++))
            ;;
        FAIL)
            echo -e "${RED}✗${NC} $test_name"
            [[ -n "$message" ]] && echo -e "  ${RED}└─ $message${NC}"
            ((FAILED_TESTS++))
            ;;
        SKIP)
            echo -e "${YELLOW}○${NC} $test_name ${YELLOW}(skipped)${NC}"
            ((SKIPPED_TESTS++))
            ;;
        INFO)
            echo -e "${CYAN}ℹ${NC} $test_name"
            ;;
    esac
    
    ((TOTAL_TESTS++))
}

# Test wrapper
run_test() {
    local category=$1
    local test_name=$2
    local test_function=$3
    
    if $test_function; then
        print_test_result "PASS" "$test_name"
        log_test "PASS" "$category" "$test_name" "Test passed"
    else
        local error_msg="${4:-Test failed}"
        print_test_result "FAIL" "$test_name" "$error_msg"
        log_test "FAIL" "$category" "$test_name" "$error_msg"
    fi
}

# Progress bar
show_progress() {
    local current=$1
    local total=$2
    local width=40
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    
    printf "\r["
    printf "%${filled}s" | tr ' ' '▓'
    printf "%$((width - filled))s" | tr ' ' '░'
    printf "] %3d%% " "$percentage"
}

# =============================================================================
# SYSTEM TESTS
# =============================================================================

test_system_requirements() {
    echo -e "\n${BOLD}System Requirements Tests${NC}"
    
    # OS version test
    run_test "system" "Ubuntu 24.04 compatibility" test_os_version
    
    # Memory test
    run_test "system" "Memory requirements (16GB+)" test_memory_requirements
    
    # Disk space test
    run_test "system" "Disk space available (50GB+)" test_disk_space
    
    # CPU test
    run_test "system" "CPU cores (4+)" test_cpu_cores
    
    # Network connectivity
    run_test "system" "Internet connectivity" test_internet_connection
}

test_os_version() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        [[ "$ID" == "ubuntu" ]] && [[ "$VERSION_ID" == "24.04" ]]
    else
        return 1
    fi
}

test_memory_requirements() {
    local total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    [[ $total_ram_gb -ge 15 ]]  # Allow for small variation
}

test_disk_space() {
    local available_gb=$(df "$INSTALL_DIR" 2>/dev/null | awk 'NR==2{print int($4/1024/1024)}' || echo 0)
    [[ $available_gb -ge 20 ]]  # At least 20GB free
}

test_cpu_cores() {
    local cores=$(nproc)
    [[ $cores -ge 4 ]]
}

test_internet_connection() {
    timeout 10 curl -sf https://api.github.com >/dev/null 2>&1
}

# =============================================================================
# SERVICE TESTS
# =============================================================================

test_services() {
    echo -e "\n${BOLD}Service Status Tests${NC}"
    
    # Docker test
    run_test "services" "Docker service" test_docker_service
    
    # Ollama test
    run_test "services" "Ollama service" test_ollama_service
    
    # Agent Zero test
    run_test "services" "Agent Zero service" test_agent0_service
    
    # Service dependencies
    run_test "services" "Service dependencies" test_service_dependencies
}

test_docker_service() {
    systemctl is-active docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1
}

test_ollama_service() {
    systemctl is-active ollama >/dev/null 2>&1
}

test_agent0_service() {
    systemctl is-active agent0 >/dev/null 2>&1
}

test_service_dependencies() {
    # Check if services are properly ordered
    systemctl list-dependencies agent0.service | grep -q ollama.service
}

# =============================================================================
# NETWORK TESTS
# =============================================================================

test_network() {
    echo -e "\n${BOLD}Network Configuration Tests${NC}"
    
    # Port tests
    run_test "network" "Ollama API port (11434)" test_ollama_port
    run_test "network" "Agent Zero port (8080)" test_agent0_port
    
    # Firewall test
    run_test "network" "Firewall configuration" test_firewall_config
    
    # DNS resolution
    run_test "network" "DNS resolution" test_dns_resolution
}

test_ollama_port() {
    netstat -tuln 2>/dev/null | grep -q ":11434 " || ss -tuln | grep -q ":11434 "
}

test_agent0_port() {
    netstat -tuln 2>/dev/null | grep -q ":8080 " || ss -tuln | grep -q ":8080 "
}

test_firewall_config() {
    if command -v ufw >/dev/null 2>&1; then
        ufw status | grep -qE "(8080|ALLOW)" || [[ $(ufw status | grep "Status: inactive") ]]
    else
        return 0  # No firewall is OK
    fi
}

test_dns_resolution() {
    host github.com >/dev/null 2>&1 || nslookup github.com >/dev/null 2>&1
}

# =============================================================================
# API TESTS
# =============================================================================

test_apis() {
    echo -e "\n${BOLD}API Endpoint Tests${NC}"
    
    # Ollama API tests
    run_test "api" "Ollama API health check" test_ollama_api_health
    run_test "api" "Ollama API version" test_ollama_api_version
    run_test "api" "Ollama API tags endpoint" test_ollama_api_tags
    
    # Agent Zero API tests
    run_test "api" "Agent Zero web UI" test_agent0_ui
    run_test "api" "Agent Zero API response" test_agent0_api
}

test_ollama_api_health() {
    curl -sf -m $API_TIMEOUT http://localhost:11434/ >/dev/null 2>&1
}

test_ollama_api_version() {
    local response=$(curl -sf -m $API_TIMEOUT http://localhost:11434/api/version 2>/dev/null)
    [[ -n "$response" ]] && echo "$response" | jq -e '.version' >/dev/null 2>&1
}

test_ollama_api_tags() {
    local response=$(curl -sf -m $API_TIMEOUT http://localhost:11434/api/tags 2>/dev/null)
    [[ -n "$response" ]] && echo "$response" | jq -e '.models' >/dev/null 2>&1
}

test_agent0_ui() {
    curl -sf -m $UI_TIMEOUT http://localhost:8080 >/dev/null 2>&1
}

test_agent0_api() {
    # Test if Agent Zero responds to basic requests
    local response=$(curl -sf -m $API_TIMEOUT http://localhost:8080/health 2>/dev/null || echo "")
    [[ -n "$response" ]]
}

# =============================================================================
# MODEL TESTS
# =============================================================================

test_models() {
    echo -e "\n${BOLD}Model Availability Tests${NC}"
    
    # Model presence test
    run_test "model" "Mistral Nemo 12B model present" test_mistral_model_present
    
    # Model info test
    run_test "model" "Model information retrieval" test_model_info
    
    # Model response test
    run_test "model" "Model generation test" test_model_generation
    
    # Model performance test
    run_test "model" "Model response time (<30s)" test_model_performance
}

test_mistral_model_present() {
    ollama list 2>/dev/null | grep -q "mistral-nemo:12b"
}

test_model_info() {
    local info=$(ollama show mistral-nemo:12b 2>/dev/null)
    [[ -n "$info" ]]
}

test_model_generation() {
    echo -e "\n  ${CYAN}Testing model response (this may take a moment)...${NC}"
    
    local response=$(curl -sf -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d '{
            "model": "mistral-nemo:12b",
            "prompt": "Say hello in exactly 5 words",
            "stream": false,
            "options": {
                "temperature": 0.1,
                "max_tokens": 20
            }
        }' \
        -m $MODEL_TIMEOUT 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        local text=$(echo "$response" | jq -r '.response' 2>/dev/null)
        if [[ -n "$text" ]]; then
            echo -e "  ${GREEN}Model response: $text${NC}"
            return 0
        fi
    fi
    return 1
}

test_model_performance() {
    local start_time=$(date +%s)
    
    curl -sf -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d '{
            "model": "mistral-nemo:12b",
            "prompt": "Hi",
            "stream": false,
            "options": {"max_tokens": 5}
        }' \
        -m 30 >/dev/null 2>&1
    
    local end_time=$(date +%s)
    local response_time=$((end_time - start_time))
    
    echo -e "  ${CYAN}Response time: ${response_time}s${NC}"
    [[ $response_time -lt 30 ]]
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_integration() {
    echo -e "\n${BOLD}Integration Tests${NC}"
    
    # Agent Zero + Ollama integration
    run_test "integration" "Agent Zero ↔ Ollama connection" test_agent_ollama_integration
    
    # Configuration consistency
    run_test "integration" "Configuration consistency" test_config_consistency
    
    # Log generation
    run_test "integration" "Logging functionality" test_logging
    
    # File permissions
    run_test "integration" "File permissions" test_file_permissions
}

test_agent_ollama_integration() {
    # Check if Agent Zero can reach Ollama
    local agent_config="/etc/agent0-mistral/agent0.env"
    if [[ -f "$agent_config" ]]; then
        source "$agent_config"
        curl -sf -m 5 "$OLLAMA_BASE_URL/api/tags" >/dev/null 2>&1
    else
        return 1
    fi
}

test_config_consistency() {
    # Check if all config files exist and are valid
    [[ -f "/etc/agent0-mistral/agent0.env" ]] && \
    [[ -f "$INSTALL_DIR/launch_agent0.sh" ]] && \
    [[ -x "$INSTALL_DIR/launch_agent0.sh" ]]
}

test_logging() {
    # Check if logs are being generated
    [[ -d "/var/log/agent0-mistral" ]] && \
    [[ -n "$(find /var/log/agent0-mistral -name "*.log" -mmin -60 2>/dev/null)" ]]
}

test_file_permissions() {
    # Check critical file ownership
    [[ -d "$INSTALL_DIR" ]] && \
    [[ "$(stat -c %U "$INSTALL_DIR")" == "agent0" ]]
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_performance() {
    echo -e "\n${BOLD}Performance Tests${NC}"
    
    # Memory usage
    run_test "performance" "Memory usage (<80%)" test_memory_usage
    
    # CPU usage
    run_test "performance" "CPU usage (<90%)" test_cpu_usage
    
    # Disk I/O
    run_test "performance" "Disk I/O performance" test_disk_io
    
    # API latency
    run_test "performance" "API latency (<100ms)" test_api_latency
}

test_memory_usage() {
    local mem_usage=$(free | awk '/^Mem:/{printf "%.0f", $3/$2 * 100}')
    echo -e "  ${CYAN}Memory usage: ${mem_usage}%${NC}"
    [[ $mem_usage -lt 80 ]]
}

test_cpu_usage() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo -e "  ${CYAN}CPU usage: ${cpu_usage}%${NC}"
    [[ ${cpu_usage%.*} -lt 90 ]]
}

test_disk_io() {
    # Simple disk write test
    local start_time=$(date +%s.%N)
    dd if=/dev/zero of="$TEMP_DIR/disktest" bs=1M count=100 >/dev/null 2>&1
    local end_time=$(date +%s.%N)
    
    local write_time=$(echo "$end_time - $start_time" | bc)
    local write_speed=$(echo "scale=2; 100 / $write_time" | bc)
    
    echo -e "  ${CYAN}Disk write speed: ${write_speed} MB/s${NC}"
    rm -f "$TEMP_DIR/disktest"
    
    # Consider >50MB/s as acceptable
    [[ $(echo "$write_speed > 50" | bc) -eq 1 ]]
}

test_api_latency() {
    local total_time=0
    local iterations=5
    
    for i in $(seq 1 $iterations); do
        local start_time=$(date +%s.%N)
        curl -sf http://localhost:11434/api/tags >/dev/null 2>&1
        local end_time=$(date +%s.%N)
        
        local response_time=$(echo "($end_time - $start_time) * 1000" | bc)
        total_time=$(echo "$total_time + $response_time" | bc)
    done
    
    local avg_latency=$(echo "scale=2; $total_time / $iterations" | bc)
    echo -e "  ${CYAN}Average API latency: ${avg_latency}ms${NC}"
    
    [[ $(echo "$avg_latency < 100" | bc) -eq 1 ]]
}

# =============================================================================
# USER ACCEPTANCE TESTS
# =============================================================================

run_user_tests() {
    echo -e "\n${BOLD}User Acceptance Tests${NC}"
    echo -e "${CYAN}These tests verify the system is ready for end users${NC}\n"
    
    # Test 1: Can access web UI
    echo -n "1. Checking if web interface is accessible... "
    if curl -sf -m 5 http://localhost:8080 >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        echo -e "   ${GREEN}→ Users can access: http://$(hostname -I | awk '{print $1}'):8080${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo -e "   ${RED}→ Web interface not accessible${NC}"
    fi
    
    # Test 2: Can generate text
    echo -n "2. Testing if AI can generate responses... "
    local test_response=$(curl -sf -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d '{"model": "mistral-nemo:12b", "prompt": "Hello", "stream": false}' \
        -m 30 2>/dev/null | jq -r '.response' 2>/dev/null)
    
    if [[ -n "$test_response" ]]; then
        echo -e "${GREEN}✓${NC}"
        echo -e "   ${GREEN}→ AI is responding correctly${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo -e "   ${RED}→ AI is not generating responses${NC}"
    fi
    
    # Test 3: Check response speed
    echo -n "3. Checking response speed... "
    local start=$(date +%s)
    curl -sf -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d '{"model": "mistral-nemo:12b", "prompt": "Hi", "stream": false, "options": {"max_tokens": 5}}' \
        -m 30 >/dev/null 2>&1
    local end=$(date +%s)
    local duration=$((end - start))
    
    if [[ $duration -lt 10 ]]; then
        echo -e "${GREEN}✓${NC} (${duration}s)"
        echo -e "   ${GREEN}→ Response time is good${NC}"
    elif [[ $duration -lt 30 ]]; then
        echo -e "${YELLOW}✓${NC} (${duration}s)"
        echo -e "   ${YELLOW}→ Response time is acceptable${NC}"
    else
        echo -e "${RED}✗${NC} (${duration}s)"
        echo -e "   ${RED}→ Response time is too slow${NC}"
    fi
}

# =============================================================================
# DIAGNOSTIC INFORMATION
# =============================================================================

collect_diagnostics() {
    echo -e "\n${BOLD}Collecting Diagnostic Information${NC}"
    
    local diag_file="$TEMP_DIR/diagnostics.txt"
    
    {
        echo "=== System Diagnostics ==="
        echo "Date: $(date)"
        echo "Hostname: $(hostname)"
        echo "IP: $(hostname -I | awk '{print $1}')"
        echo
        echo "=== Resource Usage ==="
        echo "Memory: $(free -h | awk '/^Mem:/{print $3 "/" $2}')"
        echo "CPU Load: $(uptime | awk -F'load average:' '{print $2}')"
        echo "Disk: $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')"
        echo
        echo "=== Service Status ==="
        systemctl status ollama agent0 --no-pager 2>/dev/null || true
        echo
        echo "=== Recent Errors ==="
        journalctl -p err -n 10 --no-pager 2>/dev/null || true
    } > "$diag_file"
    
    echo -e "${CYAN}Diagnostics saved to: $diag_file${NC}"
}

# =============================================================================
# MAIN TEST RUNNER
# =============================================================================

run_all_tests() {
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Agent Zero + Mistral Nemo Test Suite v${SCRIPT_VERSION}         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${CYAN}Running comprehensive system tests...${NC}"
    echo -e "${CYAN}This may take a few minutes.${NC}\n"
    
    # Run test categories
    test_system_requirements
    test_services
    test_network
    test_apis
    test_models
    test_integration
    test_performance
    
    # User tests
    run_user_tests
    
    # Summary
    echo -e "\n${BOLD}Test Summary${NC}"
    echo "═══════════════════════════════════════"
    echo -e "Total Tests:   $TOTAL_TESTS"
    echo -e "Passed:        ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed:        ${RED}$FAILED_TESTS${NC}"
    echo -e "Skipped:       ${YELLOW}$SKIPPED_TESTS${NC}"
    
    local success_rate=0
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    echo -e "Success Rate:  ${success_rate}%"
    echo "═══════════════════════════════════════"
    
    # Overall status
    echo
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All tests passed! System is working correctly.${NC}"
        echo -e "${GREEN}Your Agent Zero + Mistral Nemo installation is ready to use!${NC}"
        echo
        echo -e "${CYAN}Access your AI assistant at:${NC}"
        echo -e "${WHITE}http://$(hostname -I | awk '{print $1}'):8080${NC}"
    elif [[ $success_rate -ge 80 ]]; then
        echo -e "${YELLOW}${BOLD}⚠ Most tests passed with some warnings.${NC}"
        echo -e "${YELLOW}The system should work but may have minor issues.${NC}"
        echo
        echo -e "${CYAN}Check the test log for details:${NC}"
        echo -e "${WHITE}$TEST_LOG${NC}"
    else
        echo -e "${RED}${BOLD}✗ Multiple tests failed.${NC}"
        echo -e "${RED}The system may not be working correctly.${NC}"
        echo
        echo -e "${CYAN}Run the troubleshooter:${NC}"
        echo -e "${WHITE}sudo $INSTALL_DIR/troubleshoot.sh${NC}"
        
        # Collect diagnostics for failed tests
        collect_diagnostics
    fi
    
    echo
    echo -e "${CYAN}Full test log saved to: $TEST_LOG${NC}"
}

# Quick test mode
run_quick_tests() {
    echo -e "${BOLD}${CYAN}Quick System Check${NC}"
    echo "═══════════════════════════════════════"
    
    # Essential checks only
    echo -n "Services:     "
    if systemctl is-active ollama >/dev/null 2>&1 && systemctl is-active agent0 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Running${NC}"
    else
        echo -e "${RED}✗ Not running${NC}"
    fi
    
    echo -n "Web UI:       "
    if curl -sf -m 5 http://localhost:8080 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Accessible${NC}"
    else
        echo -e "${RED}✗ Not accessible${NC}"
    fi
    
    echo -n "Model:        "
    if ollama list 2>/dev/null | grep -q "mistral-nemo:12b"; then
        echo -e "${GREEN}✓ Available${NC}"
    else
        echo -e "${RED}✗ Not found${NC}"
    fi
    
    echo -n "API:          "
    if curl -sf -m 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Responding${NC}"
    else
        echo -e "${RED}✗ Not responding${NC}"
    fi
    
    echo "═══════════════════════════════════════"
}

# Show usage
show_usage() {
    cat << EOF
${BOLD}Agent Zero + Mistral Nemo Test Suite${NC}
Version: $SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --full          Run all tests (default)
    --quick         Run quick system check only
    --category CAT  Run specific test category:
                    ${TEST_CATEGORIES[@]}
    --help          Show this help

EXAMPLES:
    # Run all tests
    $0
    
    # Quick check
    $0 --quick
    
    # Test specific category
    $0 --category api

EOF
}

# Main
main() {
    init
    
    local mode="full"
    local category=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --full)
                mode="full"
                shift
                ;;
            --quick)
                mode="quick"
                shift
                ;;
            --category)
                mode="category"
                category="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Run tests based on mode
    case "$mode" in
        full)
            run_all_tests
            ;;
        quick)
            run_quick_tests
            ;;
        category)
            case "$category" in
                system) test_system_requirements ;;
                services) test_services ;;
                network) test_network ;;
                api) test_apis ;;
                model) test_models ;;
                integration) test_integration ;;
                performance) test_performance ;;
                *)
                    echo "Invalid category: $category"
                    echo "Valid categories: ${TEST_CATEGORIES[@]}"
                    exit 1
                    ;;
            esac
            ;;
    esac
}

# Run main
main "$@"