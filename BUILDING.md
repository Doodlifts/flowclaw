# Building on FlowClaw

FlowClaw is designed so that the most interesting work happens **outside this repo**. The 11 base contracts define a protocol — a set of resources, entitlements, events, and interfaces that anyone can compose with. You don't need permission to build on FlowClaw. You don't need a PR merged. You deploy your own contracts, publish extensions to the on-chain registry, and users decide whether to install them.

This guide covers every composability surface in the protocol.

---

## The Composability Model

FlowClaw separates **base protocol** (the 11 contracts) from **extensions** (everything built on top). The base protocol handles identity, sessions, memory, encryption, scheduling, and tools. Extensions add new capabilities by interacting with the base through Cadence's entitlement system.

Think of it like a smartphone OS. FlowClaw provides the APIs. You build the apps. There's no App Store gatekeeper.

```
┌─────────────────────────────────────────────────────────┐
│  YOUR EXTENSION                                          │
│  (deployed as your own Cadence contract)                 │
│                                                          │
│  Uses entitlements:  ManageTools, RegisterHooks, Store   │
└────────────┬─────────────────┬──────────────┬───────────┘
             │                 │              │
             ▼                 ▼              ▼
┌────────────────┐  ┌──────────────┐  ┌──────────────┐
│  ToolRegistry  │  │  Lifecycle   │  │  AgentMemory │
│  (base)        │  │  Hooks (base)│  │  (base)      │
└────────────────┘  └──────────────┘  └──────────────┘
```

An extension declares what entitlements it needs upfront. Users can see those requirements before installing. Extensions can't exceed their granted permissions — Cadence enforces this at the protocol level.

---

## 1. Publishing Extensions

The simplest way to build on FlowClaw. No contract deployment required — just a Cadence transaction.

### What You Can Publish

| Category | What it adds | Example |
|---|---|---|
| `tool` | New tools for the agent | DeFi integrations, API connectors, data pipelines |
| `hook` | Lifecycle interceptors | Content filters, logging, analytics, moderation |
| `memory` | Memory enhancements | Summarization, semantic search, vector indexing |
| `channel` | Communication adapters | Telegram bot, Discord bot, Slack integration |
| `security` | Security features | Rate limiting, anomaly detection, spending alerts |
| `analytics` | Monitoring/reporting | Usage dashboards, cost tracking, performance metrics |
| `integration` | External service bridges | GitHub, Notion, calendar sync |
| `custom` | Anything else | Whatever you build |

### Publishing a New Extension

```cadence
import "AgentExtensions"

transaction(
    name: String,
    displayName: String,
    description: String,
    version: String,
    category: UInt8,
    contentHash: String,
    dependencies: [String],
    requiredEntitlements: [String]
) {
    prepare(acct: auth(BorrowValue) &Account) {
        let registry = AgentExtensions.borrowGlobalRegistry()
        registry.publish(
            name: name,
            displayName: displayName,
            description: description,
            version: version,
            author: acct.address,
            category: AgentExtensions.ExtensionCategory(rawValue: category)!,
            contentHash: contentHash,
            dependencies: dependencies,
            requiredEntitlements: requiredEntitlements
        )
    }
}
```

The registry enforces unique names (first come, first served) and stores the publisher's Flow address for reputation tracking.

### What Users See Before Installing

```
Extension: defi-price-alerts
Author: 0x1a2b3c4d5e6f7890
Version: 1.2.0
Category: tool
Required entitlements: ManageTools, ExecuteTools, Store
Dependencies: none
Content hash: sha256:abc123...
```

Users decide whether to trust the publisher and whether the entitlements are reasonable.

---

## 2. Building Custom Tools

Tools are how agents interact with the world. FlowClaw ships with built-in tools (memory, web fetch, chain queries), but the system is designed for you to add more.

### On-Chain Tool Registration

Register tools via the `ToolRegistry` contract. Each tool has a name, description, parameters, and flags:

```cadence
import "ToolRegistry"

transaction(
    name: String,
    description: String,
    parameters: [ToolRegistry.ToolParameter],
    requiresApproval: Bool
) {
    prepare(acct: auth(BorrowValue) &Account) {
        let collection = acct.storage.borrow<auth(ToolRegistry.ManageTools) &ToolRegistry.ToolCollection>(
            from: /storage/FlowClawToolCollection
        )!
        collection.registerTool(
            name: name,
            description: description,
            parameters: parameters,
            requiresApproval: requiresApproval,
            isBuiltIn: false
        )
    }
}
```

The `requiresApproval` flag is important — set it to `true` for tools that spend money, modify state, or have irreversible effects. The agent must get explicit user confirmation before executing these.

### Off-Chain Tool Executor

Tools registered on-chain need a corresponding executor in the relay. Extend `AgentToolExecutor` in `relay/tx_executor.py`:

```python
from tx_executor import AgentToolExecutor, ToolResult

class MyToolExecutor(AgentToolExecutor):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Register your custom tool
        self.register_tool(
            name="check_defi_price",
            description="Check the current price of a DeFi token",
            parameters={
                "token": {"type": "string", "description": "Token symbol (e.g., FLOW, USDC)"},
                "exchange": {"type": "string", "description": "Exchange name", "required": False},
            },
            handler=self._check_defi_price,
        )

    def _check_defi_price(self, token: str, exchange: str = "default") -> ToolResult:
        # Your implementation here
        price = fetch_price(token, exchange)
        return ToolResult(success=True, output=f"{token}: ${price}")
```

The LLM sees your tool's definition and can call it like any built-in tool. Results are fed back into the conversation.

---

## 3. Building Lifecycle Hooks

FlowClaw's lifecycle hook system (ported from OpenClaw PR #12082) defines 20 phases where you can intercept, modify, or block behavior:

```
gatewayPreStart → gatewayPostStart →
preProviderSelect → postProviderSelect →
preMessageSend → postMessageSend →
preInferenceRequest → postInferenceRequest →
preInferenceComplete → postInferenceComplete →
preToolExecution → postToolExecution →
preMemoryStore → postMemoryStore →
preMemoryRecall → postMemoryRecall →
preSessionCreate → postSessionCreate →
preScheduledTask → postScheduledTask
```

### Hook Configuration

Each hook has:

- **Priority** (0-255) — lower runs first
- **Fail mode** — `failOpen` (continue on error) or `failClosed` (abort on error)
- **Scope gating** — restrict to specific channels, tools, or sessions

### Example: Content Moderation Hook

```cadence
import "AgentLifecycleHooks"

transaction {
    prepare(acct: auth(BorrowValue) &Account) {
        let hookManager = acct.storage.borrow<auth(AgentLifecycleHooks.RegisterHooks) &AgentLifecycleHooks.HookManager>(
            from: /storage/FlowClawHookManager
        )!

        let config = AgentLifecycleHooks.HookConfig(
            priority: 10,           // Run early
            failMode: .failClosed,  // Block message if hook fails
            timeout: 5.0,
            maxRetries: 1,
            allowedChannels: [],    // All channels
            allowedTools: [],
            allowedSessions: []
        )

        hookManager.registerHook(
            phase: .preMessageSend,
            handler: "content-moderation-v1",
            config: config
        )
    }
}
```

The off-chain relay picks up `HookTriggered` events and runs the corresponding handler. Your handler can modify the message, log it, or return a block signal.

---

## 4. Reading FlowClaw State

Any Cadence script can read FlowClaw's public data. This lets you build dashboards, analytics, aggregators, or cross-agent composability without touching the base contracts.

### Available Read Scripts

| Script | Returns |
|---|---|
| `get_account_status.cdc` | Agent info, session count, memory count, tool count, relay status |
| `get_agent_info.cdc` | Agent name, description, version, creation date |
| `get_all_sessions.cdc` | Session list with message counts and status |
| `get_session_messages.cdc` | Messages for a session (encrypted ciphertext) |
| `get_all_memories.cdc` | Memory entries (encrypted content, plaintext tags) |
| `get_cognitive_state.cdc` | Cognitive memory state including bond graph |
| `get_molecular_cluster.cdc` | Memory cluster analysis |
| `get_all_tasks.cdc` | Scheduled tasks with execution stats |
| `get_hooks.cdc` | Registered lifecycle hooks |
| `get_installed_extensions.cdc` | Installed extensions per account |
| `get_global_stats.cdc` | Global protocol statistics |
| `get_account_keys.cdc` | Public keys on an account |

### Example: Building an Agent Directory

```cadence
import "FlowClaw"
import "AgentRegistry"

access(all) fun main(addresses: [Address]): [{String: AnyStruct}] {
    let results: [{String: AnyStruct}] = []

    for addr in addresses {
        if let status = FlowClaw.getAccountStatus(addr) {
            results.append({
                "address": addr,
                "agentName": status.agentInfo?.name ?? "Unknown",
                "sessionCount": status.sessionCount,
                "memoryCount": status.memoryCount,
                "toolCount": status.toolCount
            })
        }
    }

    return results
}
```

### Example: Cross-Agent Memory Search

```cadence
import "AgentMemory"

access(all) fun main(address: Address, tag: String): [AgentMemory.MemoryEntry] {
    let vault = getAccount(address).capabilities.borrow<&AgentMemory.MemoryVault>(
        /public/FlowClawMemoryVault
    )
    if vault == nil { return [] }
    return vault!.getByTag(tag: tag)
}
```

Note: memory content is encrypted. You get ciphertext, content hashes, and plaintext tags. Decryption requires the account owner's encryption key.

---

## 5. Integrating FlowClaw Agents into Your dApp

### Scenario: Your dApp Creates an Agent for Each User

If you're building a dApp on Flow and want each user to have an AI agent, you can have your dApp call FlowClaw's setup transaction:

```cadence
import "FlowClaw"

// Run this once per user account
transaction {
    prepare(acct: auth(SaveValue) &Account) {
        FlowClaw.initializeAccount(acct)
    }
}
```

This creates all 12 resources in the user's account. From there, your dApp's relay (or FlowClaw's shared relay) handles inference.

### Scenario: Your Contract Reads Agent State

Your contract can import FlowClaw contracts and read agent state:

```cadence
import "AgentRegistry"
import "AgentSession"

access(all) contract MyDApp {
    access(all) fun getAgentSessionCount(address: Address): Int {
        let manager = getAccount(address).capabilities.borrow<&AgentSession.SessionManager>(
            /public/FlowClawSessionManager
        )
        return manager?.getSessionCount() ?? 0
    }
}
```

### Scenario: Event-Driven Integration

FlowClaw emits events for every significant action. Your off-chain service can subscribe to these:

| Event | Use Case |
|---|---|
| `InferenceRequested` | Trigger your own processing pipeline |
| `InferenceCompleted` | Update your dashboard with response stats |
| `MemoryStored` | Index memories in your own search system |
| `ExtensionPublished` | Auto-discover new extensions |
| `TaskExecuted` | Monitor scheduled task health |
| `HookTriggered` | Analytics on hook execution patterns |

Events only expose metadata (hashes, IDs, addresses) — never plaintext content.

---

## 6. Running Your Own Relay

The relay is the off-chain component that handles inference, encryption, and tool execution. You can run your own instead of using the shared relay at flowclaw.app.

### Why Run Your Own Relay

- **Full control** — your keys, your providers, your infrastructure
- **Custom tools** — add tools specific to your use case
- **Custom hooks** — implement hook handlers for your extensions
- **Custom providers** — integrate LLM providers not in the default set
- **Privacy** — plaintext never leaves your infrastructure

### Setup

```bash
git clone https://github.com/Doodlifts/flowclaw.git
cd flowclaw

# Install dependencies
pip3 install -r relay/requirements.txt

# Configure
cp .env.example .env
# Set FLOW_NETWORK, FLOW_ACCOUNT_ADDRESS, FLOW_PRIVATE_KEY

# Start
python3.11 -m uvicorn relay.api:app --host 0.0.0.0 --port 8000
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for full configuration.

### Relay API Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/status` | GET | Health check, provider list, encryption status |
| `/encrypt` | POST | Encrypt content (for multi-party signed transactions) |
| `/transaction/build` | POST | Build unsigned transaction for multi-party signing |
| `/transaction/submit` | POST | Submit user-signed transaction with sponsor envelope |
| `/chat/send` | POST | Send message and get LLM response |
| `/chat/create-session` | POST | Create a new conversation session |
| `/sessions` | GET | List sessions |
| `/session/{id}/messages` | GET | Get session messages |
| `/memory` | GET | List memory entries |
| `/memory/store` | POST | Store encrypted memory on-chain |
| `/agents` | GET | List agents |
| `/agents/create` | POST | Create a new agent |
| `/tasks` | GET | List scheduled tasks |
| `/hooks` | GET | List lifecycle hooks |
| `/account/providers` | GET/POST | Manage BYOK LLM providers |
| `/account/providers/{name}/models` | GET | List available models for a provider |
| `/account/create` | POST | Create a new passkey-authenticated account |
| `/account/authenticate` | POST | Authenticate with passkey |

---

## 7. Contract Addresses

All FlowClaw contracts are deployed from a single account on each network:

| Network | Address | Explorer |
|---|---|---|
| **Mainnet** | `0x91d0a5b7c9832a8b` | [FlowDiver](https://flowdiver.io/account/0x91d0a5b7c9832a8b) |
| **Testnet** | `0x808983d30a46aee2` | [Testnet FlowDiver](https://testnet.flowdiver.io/account/0x808983d30a46aee2) |

Import any FlowClaw contract in your Cadence code:

```cadence
import AgentRegistry from 0x91d0a5b7c9832a8b
import AgentSession from 0x91d0a5b7c9832a8b
import AgentMemory from 0x91d0a5b7c9832a8b
// ... etc
```

Or use Cadence 1.0 quoted imports with `flow.json` aliases:

```cadence
import "AgentRegistry"
import "AgentSession"
```

---

## 8. Example Extensions

FlowClaw ships with three example extensions in `extensions/examples/`:

### SentimentGuard

A lifecycle hook that analyzes message sentiment before sending. Registers on `preMessageSend` with `failClosed` mode — can block hostile or confused messages.

**Pattern demonstrated:** hook + content analysis

### FlowDeFiTools

Adds DeFi tools: `swap_tokens`, `check_balance`, `get_pool_stats`, `set_price_alert`. The `swap_tokens` tool has `requiresApproval: true` so the agent must get user confirmation first.

**Pattern demonstrated:** tool + approval gating

### ConversationSummarizer

A composite extension using hooks, scheduling, and memory together. Hooks into `postInferenceComplete` to track conversation length, schedules recurring summarization, stores summaries in memory.

**Pattern demonstrated:** multi-system composition

---

## 9. Security Considerations for Extension Developers

- **Declare minimum entitlements.** Only request what you need. Users are more likely to install extensions with narrow permissions.
- **Use `requiresApproval: true` for irreversible actions.** Token transfers, deletions, external API calls that modify state.
- **Don't store secrets in extension metadata.** Content hashes and descriptions are public on-chain.
- **Test on testnet first.** FlowClaw testnet (`0x808983d30a46aee2`) mirrors mainnet functionality.
- **Version your extensions.** Users track versions and can pin to specific releases.
- **Document your entitlement usage.** Explain WHY you need each entitlement, not just that you need it.

---

## 10. Roadmap for Composability

Upcoming features that expand what you can build:

- **Hybrid Custody integration** — parent wallets can manage child agent accounts, enabling DAOs and organizations to run fleets of agents
- **Cross-agent messaging** — agents can send encrypted messages to other agents' sessions
- **Extension marketplace UI** — browse, search, and install extensions from the web app
- **Webhook adapters** — subscribe to FlowClaw events via HTTP webhooks
- **Channel adapters** — Telegram, Discord, Slack, and email channel integrations
- **Streaming inference** — SSE/WebSocket support for real-time token streaming

---

Questions? Open an issue on [GitHub](https://github.com/Doodlifts/flowclaw) or reach out on Flow's developer community channels.
