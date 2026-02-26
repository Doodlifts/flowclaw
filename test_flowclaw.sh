#!/bin/bash
# ============================================================
# FlowClaw — Full Agent Lifecycle Test
# ============================================================
# Exercises: sessions, messages, memory, scheduling, hooks,
#            encryption config, and global state queries.
# ============================================================

set +e  # Don't exit on individual test failures

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
ACCOUNT="0xe467b9dd11fa00df"

log()   { echo -e "${GREEN}[✓]${NC} $1"; PASS=$((PASS + 1)); }
fail()  { echo -e "${RED}[✗]${NC} $1"; FAIL=$((FAIL + 1)); }
info()  { echo -e "${CYAN}[→]${NC} $1"; }
header(){ echo -e "\n${BOLD}═══ $1 ═══${NC}\n"; }

run_tx() {
    local desc="$1"
    local file="$2"
    local args="$3"
    info "$desc"
    if [ -n "$args" ]; then
        RESULT=$(flow transactions send "$file" \
            --args-json "$args" \
            --signer emulator-account \
            --network emulator 2>&1)
    else
        RESULT=$(flow transactions send "$file" \
            --signer emulator-account \
            --network emulator 2>&1)
    fi
    if echo "$RESULT" | grep -qi "sealed\|success"; then
        log "$desc"
        return 0
    else
        fail "$desc"
        echo -e "    ${RED}$(echo "$RESULT" | grep -i "error" | head -3)${NC}"
        return 1
    fi
}

run_script() {
    local desc="$1"
    local file="$2"
    local args="$3"
    info "$desc"
    if [ -n "$args" ]; then
        RESULT=$(flow scripts execute "$file" \
            --args-json "$args" \
            --network emulator 2>&1)
    else
        RESULT=$(flow scripts execute "$file" \
            --network emulator 2>&1)
    fi
    if echo "$RESULT" | grep -qi "error"; then
        fail "$desc"
        echo -e "    ${RED}$(echo "$RESULT" | grep -i "error" | head -3)${NC}"
        return 1
    else
        log "$desc"
        echo "$RESULT" | head -20
        return 0
    fi
}

echo ""
echo -e "${BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║     FlowClaw — Full Agent Lifecycle Test      ║"
echo "  ║  Agentic AI on Flow Blockchain (Forked Mainnet)║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  Account: ${CYAN}$ACCOUNT${NC}"
echo -e "  Network: ${CYAN}Forked Mainnet Emulator${NC}"
echo ""

# ============================================================
header "1. GLOBAL STATE — Pre-test Baseline"
# ============================================================

run_script "Query global stats" \
    "cadence/scripts/get_global_stats.cdc"

run_script "Query agent info" \
    "cadence/scripts/get_agent_info.cdc" \
    "[{\"type\": \"Address\", \"value\": \"$ACCOUNT\"}]"

# ============================================================
header "2. ENCRYPTION — Configure E2E Keys"
# ============================================================

run_tx "Configure encryption (XChaCha20-Poly1305)" \
    "cadence/transactions/configure_encryption.cdc" \
    '[
        {"type": "String", "value": "fc-test-key-fingerprint-001"},
        {"type": "UInt8", "value": "0"},
        {"type": "String", "value": "FlowClaw Test Key"}
    ]'

# ============================================================
header "3. SESSIONS — Agent Conversation Management"
# ============================================================

run_tx "Create session #2 (extended context)" \
    "cadence/transactions/create_session.cdc" \
    '[{"type": "UInt64", "value": "8192"}]'

run_tx "Create session #3 (compact context)" \
    "cadence/transactions/create_session.cdc" \
    '[{"type": "UInt64", "value": "2048"}]'

# ============================================================
header "4. MESSAGES — Encrypted On-Chain Communication"
# ============================================================

# Simulate encrypted messages (in production, relay encrypts with XChaCha20-Poly1305)
MSG1_HASH=$(echo -n "What is the current FLOW token price?" | shasum -a 256 | cut -d' ' -f1)
run_tx "Send encrypted message to session #2" \
    "cadence/transactions/send_message.cdc" \
    "[
        {\"type\": \"UInt64\", \"value\": \"2\"},
        {\"type\": \"String\", \"value\": \"encrypted:What is the current FLOW token price?\"},
        {\"type\": \"String\", \"value\": \"random-nonce-abc123\"},
        {\"type\": \"String\", \"value\": \"$MSG1_HASH\"},
        {\"type\": \"String\", \"value\": \"fc-test-key-fingerprint-001\"},
        {\"type\": \"UInt8\", \"value\": \"0\"},
        {\"type\": \"UInt64\", \"value\": \"42\"}
    ]"

MSG2_HASH=$(echo -n "Schedule a daily portfolio check" | shasum -a 256 | cut -d' ' -f1)
run_tx "Send second message to session #2" \
    "cadence/transactions/send_message.cdc" \
    "[
        {\"type\": \"UInt64\", \"value\": \"2\"},
        {\"type\": \"String\", \"value\": \"encrypted:Schedule a daily portfolio check\"},
        {\"type\": \"String\", \"value\": \"random-nonce-def456\"},
        {\"type\": \"String\", \"value\": \"$MSG2_HASH\"},
        {\"type\": \"String\", \"value\": \"fc-test-key-fingerprint-001\"},
        {\"type\": \"UInt8\", \"value\": \"0\"},
        {\"type\": \"UInt64\", \"value\": \"35\"}
    ]"

MSG3_HASH=$(echo -n "Hello from session 3!" | shasum -a 256 | cut -d' ' -f1)
run_tx "Send message to session #3 (different session)" \
    "cadence/transactions/send_message.cdc" \
    "[
        {\"type\": \"UInt64\", \"value\": \"3\"},
        {\"type\": \"String\", \"value\": \"encrypted:Hello from session 3!\"},
        {\"type\": \"String\", \"value\": \"random-nonce-ghi789\"},
        {\"type\": \"String\", \"value\": \"$MSG3_HASH\"},
        {\"type\": \"String\", \"value\": \"fc-test-key-fingerprint-001\"},
        {\"type\": \"UInt8\", \"value\": \"0\"},
        {\"type\": \"UInt64\", \"value\": \"21\"}
    ]"

# ============================================================
header "5. MEMORY — On-Chain Agent Memory Vault"
# ============================================================

MEM1_HASH=$(echo -n "User prefers concise responses" | shasum -a 256 | cut -d' ' -f1)
run_tx "Store memory: user preference" \
    "cadence/transactions/store_memory.cdc" \
    "[
        {\"type\": \"String\", \"value\": \"user:preference:response_style\"},
        {\"type\": \"String\", \"value\": \"encrypted:User prefers concise responses\"},
        {\"type\": \"String\", \"value\": \"mem-nonce-001\"},
        {\"type\": \"String\", \"value\": \"$MEM1_HASH\"},
        {\"type\": \"String\", \"value\": \"fc-test-key-fingerprint-001\"},
        {\"type\": \"UInt8\", \"value\": \"0\"},
        {\"type\": \"UInt64\", \"value\": \"34\"},
        {\"type\": \"Array\", \"value\": [{\"type\": \"String\", \"value\": \"preference\"}, {\"type\": \"String\", \"value\": \"style\"}]},
        {\"type\": \"String\", \"value\": \"user-conversation\"}
    ]"

MEM2_HASH=$(echo -n "Portfolio: 1000 FLOW, 500 USDC" | shasum -a 256 | cut -d' ' -f1)
run_tx "Store memory: portfolio snapshot" \
    "cadence/transactions/store_memory.cdc" \
    "[
        {\"type\": \"String\", \"value\": \"agent:portfolio:snapshot\"},
        {\"type\": \"String\", \"value\": \"encrypted:Portfolio: 1000 FLOW, 500 USDC\"},
        {\"type\": \"String\", \"value\": \"mem-nonce-002\"},
        {\"type\": \"String\", \"value\": \"$MEM2_HASH\"},
        {\"type\": \"String\", \"value\": \"fc-test-key-fingerprint-001\"},
        {\"type\": \"UInt8\", \"value\": \"0\"},
        {\"type\": \"UInt64\", \"value\": \"31\"},
        {\"type\": \"Array\", \"value\": [{\"type\": \"String\", \"value\": \"portfolio\"}, {\"type\": \"String\", \"value\": \"defi\"}, {\"type\": \"String\", \"value\": \"snapshot\"}]},
        {\"type\": \"String\", \"value\": \"defi-monitor\"}
    ]"

MEM3_HASH=$(echo -n "API rate limit: 100 calls/hour for Anthropic" | shasum -a 256 | cut -d' ' -f1)
run_tx "Store memory: system knowledge" \
    "cadence/transactions/store_memory.cdc" \
    "[
        {\"type\": \"String\", \"value\": \"system:rate_limits:anthropic\"},
        {\"type\": \"String\", \"value\": \"encrypted:API rate limit: 100 calls/hour for Anthropic\"},
        {\"type\": \"String\", \"value\": \"mem-nonce-003\"},
        {\"type\": \"String\", \"value\": \"$MEM3_HASH\"},
        {\"type\": \"String\", \"value\": \"fc-test-key-fingerprint-001\"},
        {\"type\": \"UInt8\", \"value\": \"0\"},
        {\"type\": \"UInt64\", \"value\": \"45\"},
        {\"type\": \"Array\", \"value\": [{\"type\": \"String\", \"value\": \"system\"}, {\"type\": \"String\", \"value\": \"rate-limit\"}, {\"type\": \"String\", \"value\": \"anthropic\"}]},
        {\"type\": \"String\", \"value\": \"system-config\"}
    ]"

# ============================================================
header "6. SCHEDULER — On-Chain Agent Task Automation"
# ============================================================

FUTURE_TS=$(python3 -c "import time; print(f'{time.time() + 3600:.8f}')")
run_tx "Schedule task: hourly portfolio check" \
    "cadence/transactions/schedule_task.cdc" \
    "[
        {\"type\": \"String\", \"value\": \"portfolio-check\"},
        {\"type\": \"String\", \"value\": \"Check DeFi positions and rebalance if needed\"},
        {\"type\": \"UInt8\", \"value\": \"1\"},
        {\"type\": \"String\", \"value\": \"Check all DeFi positions. If any pool APY drops below 5%, recommend rebalancing.\"},
        {\"type\": \"UInt64\", \"value\": \"5\"},
        {\"type\": \"UInt8\", \"value\": \"2\"},
        {\"type\": \"UFix64\", \"value\": \"$FUTURE_TS\"},
        {\"type\": \"Bool\", \"value\": true},
        {\"type\": \"Optional\", \"value\": {\"type\": \"UFix64\", \"value\": \"3600.00000000\"}},
        {\"type\": \"Optional\", \"value\": {\"type\": \"UInt64\", \"value\": \"24\"}}
    ]"

FUTURE_TS2=$(python3 -c "import time; print(f'{time.time() + 86400:.8f}')")
run_tx "Schedule task: daily summary report" \
    "cadence/transactions/schedule_task.cdc" \
    "[
        {\"type\": \"String\", \"value\": \"daily-summary\"},
        {\"type\": \"String\", \"value\": \"Generate daily activity summary and send to owner\"},
        {\"type\": \"UInt8\", \"value\": \"0\"},
        {\"type\": \"String\", \"value\": \"Summarize all sessions, messages, memory updates, and tool executions from the past 24 hours.\"},
        {\"type\": \"UInt64\", \"value\": \"3\"},
        {\"type\": \"UInt8\", \"value\": \"1\"},
        {\"type\": \"UFix64\", \"value\": \"$FUTURE_TS2\"},
        {\"type\": \"Bool\", \"value\": true},
        {\"type\": \"Optional\", \"value\": {\"type\": \"UFix64\", \"value\": \"86400.00000000\"}},
        {\"type\": \"Optional\", \"value\": {\"type\": \"UInt64\", \"value\": \"365\"}}
    ]"

# ============================================================
header "7. LIFECYCLE HOOKS — Event Interception"
# ============================================================

HOOK_HASH=$(echo -n "check_safety_before_tool_execution" | shasum -a 256 | cut -d' ' -f1)
run_tx "Register hook: pre-tool-execution safety check" \
    "cadence/transactions/register_hook.cdc" \
    "[
        {\"type\": \"UInt8\", \"value\": \"2\"},
        {\"type\": \"UInt8\", \"value\": \"1\"},
        {\"type\": \"Bool\", \"value\": false},
        {\"type\": \"UFix64\", \"value\": \"30.00000000\"},
        {\"type\": \"UInt8\", \"value\": \"2\"},
        {\"type\": \"String\", \"value\": \"Safety check before any tool execution - validates permissions and rate limits\"},
        {\"type\": \"String\", \"value\": \"$HOOK_HASH\"}
    ]"

# ============================================================
header "8. STATE QUERIES — Verify Everything On-Chain"
# ============================================================

run_script "Query account status (full)" \
    "cadence/scripts/get_account_status.cdc" \
    "[{\"type\": \"Address\", \"value\": \"$ACCOUNT\"}]"

echo ""

run_script "Query session #2 history" \
    "cadence/scripts/get_session_history.cdc" \
    "[{\"type\": \"Address\", \"value\": \"$ACCOUNT\"}, {\"type\": \"UInt64\", \"value\": \"2\"}]"

echo ""

run_script "Query scheduled tasks" \
    "cadence/scripts/get_scheduled_tasks.cdc" \
    "[{\"type\": \"Address\", \"value\": \"$ACCOUNT\"}]"

echo ""

run_script "Query registered hooks" \
    "cadence/scripts/get_hooks.cdc" \
    "[{\"type\": \"Address\", \"value\": \"$ACCOUNT\"}]"

echo ""

run_script "Query global stats (final)" \
    "cadence/scripts/get_global_stats.cdc"

# ============================================================
header "RESULTS"
# ============================================================

TOTAL=$((PASS + FAIL))
echo -e "  ${GREEN}Passed: $PASS${NC}"
echo -e "  ${RED}Failed: $FAIL${NC}"
echo -e "  Total:  $TOTAL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}🎉 ALL TESTS PASSED — FlowClaw is fully operational!${NC}"
else
    echo -e "  ${YELLOW}${BOLD}⚠  $FAIL test(s) need attention${NC}"
fi
echo ""
