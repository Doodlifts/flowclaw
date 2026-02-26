#!/bin/bash
# ============================================================
# FlowClaw — Forked Emulator Setup & Deploy
# ============================================================
# Usage:
#   ./setup.sh              # Full setup: install CLI + start emulator + deploy
#   ./setup.sh --deploy     # Deploy only (emulator already running)
#   ./setup.sh --test       # Run test transactions after deploy
#   ./setup.sh --all        # Full setup + deploy + test
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

log()   { echo -e "${GREEN}[FlowClaw]${NC} $1"; }
warn()  { echo -e "${YELLOW}[FlowClaw]${NC} $1"; }
error() { echo -e "${RED}[FlowClaw]${NC} $1"; }
info()  { echo -e "${CYAN}[FlowClaw]${NC} $1"; }

# ============================================================
# Step 1: Check/Install Flow CLI
# ============================================================
install_cli() {
    log "Checking Flow CLI..."
    if command -v flow &> /dev/null; then
        FLOW_VERSION=$(flow version 2>/dev/null | head -1)
        log "Flow CLI found: $FLOW_VERSION"
    else
        warn "Flow CLI not found. Installing..."
        sudo sh -ci "$(curl -fsSL https://raw.githubusercontent.com/onflow/flow-cli/master/install.sh)"

        if command -v flow &> /dev/null; then
            log "Flow CLI installed successfully: $(flow version | head -1)"
        else
            error "Flow CLI installation failed. Install manually:"
            error "  brew install flow-cli"
            error "  or: sudo sh -ci \"\$(curl -fsSL https://raw.githubusercontent.com/onflow/flow-cli/master/install.sh)\""
            exit 1
        fi
    fi
}

# ============================================================
# Step 2: Generate emulator key and inject into flow.json
# ============================================================
setup_keys() {
    # Check if flow.json has a valid key (not placeholder, not all-zeros)
    CURRENT_KEY=$(python3 -c "
import json
with open('$PROJECT_DIR/flow.json') as f:
    data = json.load(f)
key = data.get('accounts', {}).get('emulator-account', {}).get('key', '')
if isinstance(key, str) and len(key) == 64 and key != 'EMULATOR_KEY_PLACEHOLDER' and key.strip('0') != '':
    print(key)
else:
    print('')
" 2>/dev/null || echo "")

    if [ -n "$CURRENT_KEY" ]; then
        log "Emulator account key already configured in flow.json."
        PRIVATE_KEY_HEX="$CURRENT_KEY"
    else
        log "Generating emulator account key..."

        # Generate a valid ECDSA P-256 private key using openssl (always available on macOS).
        # This avoids needing `flow keys generate` which validates flow.json.
        PRIVATE_KEY_HEX=$(python3 -c "
import subprocess, re

# Use openssl to generate an EC private key on P-256 (prime256v1)
pem = subprocess.check_output(['openssl', 'ecparam', '-name', 'prime256v1', '-genkey', '-noout'], stderr=subprocess.DEVNULL)
# Extract the hex representation of the private key
der = subprocess.check_output(['openssl', 'ec', '-text', '-noout'], input=pem, stderr=subprocess.DEVNULL)
# Parse the hex bytes from the 'priv:' section
text = der.decode()
in_priv = False
hex_bytes = []
for line in text.split('\n'):
    stripped = line.strip()
    if stripped.startswith('priv:'):
        in_priv = True
        continue
    if in_priv:
        if stripped.startswith('pub:') or stripped.startswith('ASN1') or stripped.startswith('NIST'):
            break
        hex_bytes.append(stripped.replace(':', ''))
raw = ''.join(hex_bytes)
# P-256 private key is 32 bytes = 64 hex chars, may have leading 00 byte
if len(raw) > 64:
    raw = raw[-64:]
print(raw)
" 2>&1)

        if [ -z "$PRIVATE_KEY_HEX" ] || [ ${#PRIVATE_KEY_HEX} -ne 64 ]; then
            error "Failed to generate key via openssl+python3."
            error "Output: $PRIVATE_KEY_HEX"
            error ""
            error "Manual fix: run in a separate terminal:"
            error "  cd /tmp && flow keys generate"
            error "  Copy the Private Key hex into ~/flowclaw/flow.json"
            exit 1
        fi

        log "Private key generated: ${PRIVATE_KEY_HEX:0:8}...${PRIVATE_KEY_HEX: -8}"

        # Inject the hex key into flow.json
        python3 -c "
import json
with open('$PROJECT_DIR/flow.json', 'r') as f:
    data = json.load(f)
data['accounts']['emulator-account']['key'] = '$PRIVATE_KEY_HEX'
with open('$PROJECT_DIR/flow.json', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" || {
            error "Failed to update flow.json with generated key."
            error "Manually set the key in flow.json: $PRIVATE_KEY_HEX"
            exit 1
        }

        log "Key injected into flow.json successfully."
    fi

    # Export for use by start_emulator
    export PRIVATE_KEY_HEX
}

# ============================================================
# Step 3: Start forked emulator
# ============================================================
start_emulator() {
    log "Checking if emulator is already running..."
    if curl -s http://localhost:8888/v1/blocks?height=sealed > /dev/null 2>&1; then
        log "Emulator already running on port 8888."
        return 0
    fi

    log "Starting Flow emulator (forked from testnet)..."
    info "This gives you real testnet state locally — real contracts, real accounts."
    info "Emulator will run in the background. Logs: $PROJECT_DIR/emulator.log"

    # Start forked emulator in background
    # --fork testnet gives us real testnet state to test against
    # --service-priv-key passes the generated hex key
    nohup flow emulator --fork testnet \
        --service-priv-key "$PRIVATE_KEY_HEX" \
        --verbose \
        > "$PROJECT_DIR/emulator.log" 2>&1 &

    EMULATOR_PID=$!
    echo "$EMULATOR_PID" > "$PROJECT_DIR/.emulator.pid"

    # Wait for emulator to be ready
    log "Waiting for emulator to start..."
    for i in $(seq 1 30); do
        if curl -s http://localhost:8888/v1/blocks?height=sealed > /dev/null 2>&1; then
            log "Emulator started (PID: $EMULATOR_PID)"
            return 0
        fi
        sleep 1
    done

    error "Emulator failed to start within 30 seconds."
    error "Check logs: tail -50 $PROJECT_DIR/emulator.log"

    # If forked mode failed, try standard emulator
    warn "Trying standard emulator (without fork)..."
    kill $EMULATOR_PID 2>/dev/null || true

    nohup flow emulator \
        --service-priv-key "$PRIVATE_KEY_HEX" \
        --verbose \
        > "$PROJECT_DIR/emulator.log" 2>&1 &

    EMULATOR_PID=$!
    echo "$EMULATOR_PID" > "$PROJECT_DIR/.emulator.pid"

    for i in $(seq 1 20); do
        if curl -s http://localhost:8888/v1/blocks?height=sealed > /dev/null 2>&1; then
            log "Standard emulator started (PID: $EMULATOR_PID)"
            warn "Running without fork — using clean emulator state."
            return 0
        fi
        sleep 1
    done

    error "Emulator failed to start. Check: tail -50 $PROJECT_DIR/emulator.log"
    exit 1
}

# ============================================================
# Step 4: Deploy all contracts
# ============================================================
deploy_contracts() {
    log "Deploying FlowClaw contracts to emulator..."
    info "Contracts deploy in dependency order (AgentRegistry first, FlowClaw last)"
    echo ""

    flow project deploy --network emulator --update 2>&1 | while IFS= read -r line; do
        if echo "$line" | grep -q "deployed"; then
            log "  $line"
        elif echo "$line" | grep -q "error\|Error\|ERROR"; then
            error "  $line"
        else
            info "  $line"
        fi
    done

    DEPLOY_EXIT=${PIPESTATUS[0]}

    if [ $DEPLOY_EXIT -eq 0 ]; then
        echo ""
        log "All 10 contracts deployed successfully!"
        log "  AgentRegistry, AgentSession, InferenceOracle, ToolRegistry,"
        log "  AgentMemory, AgentScheduler, AgentLifecycleHooks, AgentEncryption,"
        log "  AgentExtensions, FlowClaw"
    else
        echo ""
        error "Deployment failed. Check errors above."
        error "Common fixes:"
        error "  - Ensure emulator is running: curl http://localhost:8888/v1/blocks?height=sealed"
        error "  - Check contract syntax: flow cadence lint cadence/contracts/*.cdc"
        exit 1
    fi
}

# ============================================================
# Step 5: Run test transactions
# ============================================================
run_tests() {
    # Disable set -e for tests so individual failures don't kill the script
    set +e

    log "Running FlowClaw integration tests..."
    echo ""

    # Test 1: Initialize account (requires 11 args via --args-json)
    info "Test 1: Initialize FlowClaw account..."
    RESULT=$(flow transactions send cadence/transactions/initialize_account.cdc \
        --args-json '[
            {"type": "String", "value": "FlowClaw-Test-Agent"},
            {"type": "String", "value": "Integration test agent for FlowClaw"},
            {"type": "String", "value": "anthropic"},
            {"type": "String", "value": "claude-sonnet-4-5-20250929"},
            {"type": "String", "value": "test-api-key-hash-placeholder"},
            {"type": "UInt64", "value": "4096"},
            {"type": "UFix64", "value": "0.70000000"},
            {"type": "String", "value": "You are a helpful AI assistant running on the Flow blockchain."},
            {"type": "UInt8", "value": "1"},
            {"type": "UInt64", "value": "100"},
            {"type": "UFix64", "value": "10.00000000"}
        ]' \
        --signer emulator-account \
        --network emulator 2>&1)
    if echo "$RESULT" | grep -qi "sealed\|success"; then
        log "  ✓ Account initialized"
    else
        warn "  ✗ Account init failed (may already be initialized)"
        echo "    $RESULT" | tail -5
    fi

    # Test 2: Query account status
    info "Test 2: Query account status..."
    RESULT=$(flow scripts execute cadence/scripts/get_account_status.cdc \
        --args-json '[{"type": "Address", "value": "0xe467b9dd11fa00df"}]' \
        --network emulator 2>&1)
    if echo "$RESULT" | grep -qi "error"; then
        warn "  ✗ Account status query failed"
        echo "    $RESULT" | tail -3
    else
        log "  ✓ Account status retrieved"
        echo "$RESULT" | head -10
    fi

    # Test 3: Create a session
    info "Test 3: Create agent session..."
    RESULT=$(flow transactions send cadence/transactions/create_session.cdc \
        --args-json '[
            {"type": "String", "value": "test-system-prompt"},
            {"type": "String", "value": "anthropic"},
            {"type": "String", "value": "claude-sonnet-4-5-20250929"},
            {"type": "UInt64", "value": "4096"}
        ]' \
        --signer emulator-account \
        --network emulator 2>&1)
    if echo "$RESULT" | grep -qi "sealed\|success"; then
        log "  ✓ Session created"
    else
        warn "  ✗ Session creation failed"
        echo "    $RESULT" | tail -5
    fi

    # Test 4: Send a message (plaintext for testing)
    info "Test 4: Send a test message..."
    MSG_HASH=$(echo -n 'Hello FlowClaw!' | shasum -a 256 | cut -d' ' -f1)
    RESULT=$(flow transactions send cadence/transactions/send_message.cdc \
        --args-json "[
            {\"type\": \"UInt64\", \"value\": \"1\"},
            {\"type\": \"String\", \"value\": \"Hello FlowClaw!\"},
            {\"type\": \"String\", \"value\": \"$MSG_HASH\"}
        ]" \
        --signer emulator-account \
        --network emulator 2>&1)
    if echo "$RESULT" | grep -qi "sealed\|success"; then
        log "  ✓ Message sent"
    else
        warn "  ✗ Message send failed"
        echo "    $RESULT" | tail -5
    fi

    # Test 5: Query session history
    info "Test 5: Query session history..."
    RESULT=$(flow scripts execute cadence/scripts/get_session_history.cdc \
        --args-json '[{"type": "Address", "value": "0xe467b9dd11fa00df"}, {"type": "UInt64", "value": "1"}]' \
        --network emulator 2>&1)
    if echo "$RESULT" | grep -qi "error"; then
        warn "  ✗ Session history query failed"
        echo "    $RESULT" | tail -3
    else
        log "  ✓ Session history retrieved"
    fi

    # Test 6: Get global stats
    info "Test 6: Query global stats..."
    RESULT=$(flow scripts execute cadence/scripts/get_global_stats.cdc \
        --network emulator 2>&1)
    if echo "$RESULT" | grep -qi "error"; then
        warn "  ✗ Global stats query failed"
    else
        log "  ✓ Global stats retrieved"
    fi

    echo ""
    log "Integration tests complete!"

    # Re-enable strict mode
    set -e
}

# ============================================================
# Step 6: Stop emulator helper
# ============================================================
stop_emulator() {
    if [ -f "$PROJECT_DIR/.emulator.pid" ]; then
        PID=$(cat "$PROJECT_DIR/.emulator.pid")
        if kill -0 "$PID" 2>/dev/null; then
            log "Stopping emulator (PID: $PID)..."
            kill "$PID"
            rm "$PROJECT_DIR/.emulator.pid"
            log "Emulator stopped."
        fi
    else
        warn "No emulator PID file found."
    fi
}

# ============================================================
# Main
# ============================================================
echo ""
echo "  ╔═══════════════════════════════════════╗"
echo "  ║       FlowClaw — Emulator Setup       ║"
echo "  ║     Agentic AI on Flow Blockchain      ║"
echo "  ╚═══════════════════════════════════════╝"
echo ""

case "${1:-}" in
    --deploy)
        deploy_contracts
        ;;
    --test)
        run_tests
        ;;
    --stop)
        stop_emulator
        ;;
    --all)
        install_cli
        setup_keys
        start_emulator
        deploy_contracts
        run_tests
        ;;
    *)
        install_cli
        setup_keys
        start_emulator
        deploy_contracts
        log ""
        log "Ready! Run './setup.sh --test' to run integration tests."
        log "Run './setup.sh --stop' to stop the emulator."
        ;;
esac
