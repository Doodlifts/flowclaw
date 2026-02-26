#!/bin/bash
# ============================================================
# FlowClaw — Local Development Stack
# ============================================================
# Starts: Flow Emulator + Relay API + React Frontend
# ============================================================

set +e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PIDS=()

cleanup() {
    echo ""
    echo -e "${CYAN}Shutting down FlowClaw...${NC}"
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    # Also kill any child processes
    pkill -f "uvicorn relay.api:app" 2>/dev/null
    pkill -f "vite" 2>/dev/null
    echo -e "${GREEN}Done.${NC}"
    exit 0
}
trap cleanup INT TERM

echo ""
echo -e "${BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║       FlowClaw — Local Development Stack      ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# ---- Check prerequisites ----
check() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}ERROR: $1 not found. Please install it first.${NC}"
        exit 1
    fi
}
check flow
check python3
check node
check npm

# ---- Check .env ----
if [ ! -f ".env" ]; then
    echo -e "${RED}ERROR: .env file not found. Copy .env.example and configure it.${NC}"
    exit 1
fi

# Check Venice API key
if ! grep -q "VENICE_API_KEY=." .env 2>/dev/null; then
    echo -e "${RED}WARNING: VENICE_API_KEY not set in .env${NC}"
    echo -e "  Get your key at: https://venice.ai/settings/api"
    echo -e "  Then add it to .env: VENICE_API_KEY=your-key-here"
    echo ""
fi

# ---- Step 1: Check emulator ----
echo -e "${CYAN}[1/3] Checking Flow Emulator...${NC}"
if curl -s http://localhost:8888/v1/blocks?height=sealed > /dev/null 2>&1; then
    echo -e "${GREEN}  Emulator already running on :8888${NC}"
else
    echo -e "  Starting emulator..."

    # Read the private key from flow.json for the emulator
    PRIV_KEY=$(python3 -c "
import json
with open('flow.json') as f:
    data = json.load(f)
key = data.get('accounts',{}).get('emulator-account',{}).get('key','')
print(key)
" 2>/dev/null)

    if [ -z "$PRIV_KEY" ] || [ "$PRIV_KEY" = "None" ]; then
        echo -e "${RED}  Could not read private key from flow.json${NC}"
        exit 1
    fi

    flow emulator --service-priv-key "$PRIV_KEY" --service-sig-algo "ECDSA_P256" > emulator.log 2>&1 &
    PIDS+=($!)

    # Wait for emulator to start
    for i in {1..15}; do
        if curl -s http://localhost:8888/v1/blocks?height=sealed > /dev/null 2>&1; then
            echo -e "${GREEN}  Emulator started on :8888${NC}"
            break
        fi
        sleep 1
    done

    if ! curl -s http://localhost:8888/v1/blocks?height=sealed > /dev/null 2>&1; then
        echo -e "${RED}  Emulator failed to start. Check emulator.log${NC}"
        exit 1
    fi

    # Deploy contracts
    echo -e "  Deploying contracts..."
    flow project deploy --network emulator > /dev/null 2>&1
    echo -e "${GREEN}  Contracts deployed${NC}"
fi

# ---- Step 2: Start Relay API ----
echo -e "${CYAN}[2/3] Starting Relay API...${NC}"

# Install Python deps if needed
if ! python3 -c "import fastapi" 2>/dev/null; then
    echo -e "  Installing Python dependencies..."
    pip3 install -r relay/requirements.txt --break-system-packages -q 2>/dev/null || \
    pip3 install -r relay/requirements.txt -q 2>/dev/null
fi

# Start the API server
cd "$SCRIPT_DIR"
python3 -m uvicorn relay.api:app --host 0.0.0.0 --port 8000 --log-level info > .relay.log 2>&1 &
RELAY_PID=$!
PIDS+=($RELAY_PID)

# Wait for API to be ready
for i in {1..10}; do
    if curl -s http://localhost:8000/status > /dev/null 2>&1; then
        echo -e "${GREEN}  Relay API running on http://localhost:8000${NC}"
        break
    fi
    sleep 1
done

if ! curl -s http://localhost:8000/status > /dev/null 2>&1; then
    echo -e "${RED}  Relay API failed to start. Check .relay.log${NC}"
    echo "  Last 5 lines:"
    tail -5 .relay.log 2>/dev/null
    cleanup
fi

# ---- Step 3: Start Frontend ----
echo -e "${CYAN}[3/3] Starting Frontend...${NC}"

cd "$SCRIPT_DIR/frontend"

if [ ! -d "node_modules" ]; then
    echo -e "  Installing npm dependencies..."
    npm install --silent 2>/dev/null
fi

npx vite --host > "$SCRIPT_DIR/.frontend.log" 2>&1 &
FRONTEND_PID=$!
PIDS+=($FRONTEND_PID)

# Wait for Vite to be ready
for i in {1..15}; do
    if curl -s http://localhost:5173 > /dev/null 2>&1; then
        break
    fi
    sleep 1
done

cd "$SCRIPT_DIR"

echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║         FlowClaw is ready!                    ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "  ${BOLD}Frontend:${NC}   ${CYAN}http://localhost:5173${NC}"
echo -e "  ${BOLD}Relay API:${NC}  ${CYAN}http://localhost:8000${NC}"
echo -e "  ${BOLD}Emulator:${NC}   ${CYAN}http://localhost:8888${NC}"
echo ""
echo -e "  ${BOLD}LLM:${NC}        Venice AI (claude-sonnet-4-6)"
echo -e "  ${BOLD}Account:${NC}    0xe467b9dd11fa00df"
echo -e "  ${BOLD}Network:${NC}    Forked Mainnet Emulator"
echo ""
echo -e "  Press ${BOLD}Ctrl+C${NC} to stop all services"
echo ""

# Keep running until Ctrl+C
wait
