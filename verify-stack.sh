#!/bin/bash
# ============================================================
# FlowClaw — Full-Stack Verification
# ============================================================
# Verifies all components of the FlowClaw stack are working:
#   1. Flow Emulator connectivity
#   2. Cadence contracts deployed & queryable
#   3. Relay API health & encryption
#   4. LLM provider connectivity (Venice AI)
#   5. End-to-end chat round-trip
#   6. On-chain state updates
# ============================================================

set +e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}✓ $1${NC}"; ((PASS++)); }
fail() { echo -e "  ${RED}✗ $1${NC}"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}⚠ $1${NC}"; ((WARN++)); }

echo ""
echo -e "${BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║     FlowClaw — Full-Stack Verification        ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# ---- 1. Flow Emulator ----
echo -e "${CYAN}[1/6] Flow Emulator${NC}"

if curl -s http://localhost:8888/v1/blocks?height=sealed > /dev/null 2>&1; then
    pass "Emulator reachable on :8888"
else
    fail "Emulator not reachable on :8888"
fi

if curl -s http://localhost:3569 > /dev/null 2>&1; then
    pass "gRPC access node on :3569"
else
    warn "gRPC access node not reachable on :3569 (may be normal)"
fi

# ---- 2. Cadence Contracts ----
echo ""
echo -e "${CYAN}[2/6] Cadence Contracts${NC}"

CONTRACTS=(
    "AgentRegistry" "AgentSession" "InferenceOracle" "ToolRegistry"
    "AgentMemory" "AgentScheduler" "AgentLifecycleHooks" "AgentEncryption"
    "AgentExtensions" "FlowClaw"
)

# Check global stats script (exercises FlowClaw contract)
STATS=$(flow scripts execute cadence/scripts/get_global_stats.cdc --network emulator 2>/dev/null)
if [ $? -eq 0 ] && echo "$STATS" | grep -q "Result"; then
    pass "get_global_stats.cdc — contracts queryable"

    # Parse stats
    VERSION=$(echo "$STATS" | grep -oP 'version:\s*"\K[^"]+' 2>/dev/null || echo "unknown")
    AGENTS=$(echo "$STATS" | grep -oP 'totalAgents:\s*\K\d+' 2>/dev/null || echo "?")
    SESSIONS=$(echo "$STATS" | grep -oP 'totalSessions:\s*\K\d+' 2>/dev/null || echo "?")
    REQUESTS=$(echo "$STATS" | grep -oP 'totalInferenceRequests:\s*\K\d+' 2>/dev/null || echo "?")
    echo -e "    Version: $VERSION | Agents: $AGENTS | Sessions: $SESSIONS | Requests: $REQUESTS"
else
    fail "get_global_stats.cdc — contracts not queryable"
fi

# Check account status
ACCT_STATUS=$(flow scripts execute cadence/scripts/get_account_status.cdc \
    --args-json '[{"type":"Address","value":"0xe467b9dd11fa00df"}]' \
    --network emulator 2>/dev/null)
if [ $? -eq 0 ] && echo "$ACCT_STATUS" | grep -q "Result"; then
    pass "get_account_status.cdc — account initialized"
else
    warn "get_account_status.cdc — account may not be fully initialized"
fi

# ---- 3. Relay API ----
echo ""
echo -e "${CYAN}[3/6] Relay API${NC}"

RELAY_STATUS=$(curl -s http://localhost:8000/status 2>/dev/null)
if [ $? -eq 0 ] && echo "$RELAY_STATUS" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    pass "Relay API reachable on :8000"

    # Parse status fields
    CONNECTED=$(echo "$RELAY_STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('connected',False))" 2>/dev/null)
    ENC_ENABLED=$(echo "$RELAY_STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('encryptionEnabled',False))" 2>/dev/null)
    PROVIDERS=$(echo "$RELAY_STATUS" | python3 -c "import sys,json; print(', '.join(json.load(sys.stdin).get('availableProviders',[])))" 2>/dev/null)
    UPTIME=$(echo "$RELAY_STATUS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('uptime',0))" 2>/dev/null)

    if [ "$CONNECTED" = "True" ]; then
        pass "Relay → Emulator connected"
    else
        fail "Relay → Emulator NOT connected"
    fi

    if [ "$ENC_ENABLED" = "True" ]; then
        pass "Encryption enabled"
    else
        warn "Encryption NOT enabled (messages will be plaintext on-chain)"
    fi

    if [ -n "$PROVIDERS" ] && [ "$PROVIDERS" != "" ]; then
        pass "LLM providers: $PROVIDERS"
    else
        fail "No LLM providers configured"
    fi

    echo -e "    Uptime: ${UPTIME}s"
else
    fail "Relay API not reachable on :8000"
fi

# ---- 4. LLM Provider ----
echo ""
echo -e "${CYAN}[4/6] LLM Provider (Venice AI)${NC}"

# Check if Venice API key is set
if grep -q "VENICE_API_KEY=." .env 2>/dev/null; then
    pass "Venice API key configured in .env"
else
    warn "Venice API key not set in .env — chat will fail"
fi

# Quick provider check via relay
if echo "$RELAY_STATUS" | grep -q "venice" 2>/dev/null; then
    pass "Venice provider registered in relay"
else
    warn "Venice provider not registered (check API key)"
fi

# ---- 5. End-to-End Chat ----
echo ""
echo -e "${CYAN}[5/6] End-to-End Chat Round-Trip${NC}"

if echo "$RELAY_STATUS" | grep -q "venice" 2>/dev/null && grep -q "VENICE_API_KEY=." .env 2>/dev/null; then
    echo -e "  Sending test message to Venice AI via relay..."

    # Create a session first
    SESSION_RESP=$(curl -s -X POST http://localhost:8000/chat/create-session \
        -H "Content-Type: application/json" \
        -d '{"maxContextMessages": 100}' 2>/dev/null)
    SESSION_ID=$(echo "$SESSION_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('sessionId',''))" 2>/dev/null)

    if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "" ]; then
        pass "Session created: $SESSION_ID"

        # Send a test message
        CHAT_RESP=$(curl -s -X POST http://localhost:8000/chat/send \
            -H "Content-Type: application/json" \
            -d "{\"sessionId\": $SESSION_ID, \"content\": \"Hello! Reply with exactly: FLOWCLAW_OK\", \"provider\": \"venice\", \"model\": \"claude-sonnet-4-6\"}" \
            --max-time 30 2>/dev/null)

        if [ $? -eq 0 ] && echo "$CHAT_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('response','')" 2>/dev/null; then
            RESPONSE=$(echo "$CHAT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('response','')[:100])" 2>/dev/null)
            TOKENS=$(echo "$CHAT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tokensUsed',0))" 2>/dev/null)
            ON_CHAIN=$(echo "$CHAT_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('onChain',False))" 2>/dev/null)

            pass "LLM response received (${TOKENS} tokens)"
            echo -e "    Response: ${RESPONSE}..."

            if [ "$ON_CHAIN" = "True" ]; then
                pass "Message posted on-chain"
            else
                warn "Message not posted on-chain (emulator may need re-init)"
            fi
        else
            fail "Chat send failed — check relay logs (.relay.log)"
        fi
    else
        fail "Session creation failed"
    fi
else
    warn "Skipping chat test — Venice AI not configured"
fi

# ---- 6. Frontend ----
echo ""
echo -e "${CYAN}[6/6] Frontend${NC}"

if curl -s http://localhost:5173 > /dev/null 2>&1; then
    pass "Frontend reachable on :5173"
else
    warn "Frontend not reachable on :5173 (may not be running)"
fi

# ---- Summary ----
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
TOTAL=$((PASS + FAIL + WARN))
echo -e "  ${GREEN}Passed: $PASS${NC}  ${RED}Failed: $FAIL${NC}  ${YELLOW}Warnings: $WARN${NC}  Total: $TOTAL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "  ${BOLD}${GREEN}FlowClaw stack is healthy!${NC}"
else
    echo -e "  ${BOLD}${RED}$FAIL check(s) failed — see above for details${NC}"
fi

echo ""
echo -e "  ${BOLD}Quick fixes:${NC}"
if [ $FAIL -gt 0 ] || [ $WARN -gt 0 ]; then
    echo "  • Emulator not running?  →  flow emulator (in separate terminal)"
    echo "  • Relay not running?     →  python3 -m uvicorn relay.api:app --port 8000"
    echo "  • No Venice key?         →  Add VENICE_API_KEY to .env"
    echo "  • Frontend not running?  →  cd frontend && npx vite --host"
    echo "  • Or just run:           →  ./start-dev.sh"
fi
echo ""

exit $FAIL
