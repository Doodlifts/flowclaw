# Architecture

FlowClaw uses a hybrid on-chain/off-chain design. The blockchain handles state, identity, permissions, and verification. A local relay handles inference, tool execution, and encryption.

## Why Hybrid?

LLM inference can't run on-chain. It requires external API calls to providers like Anthropic or OpenAI, costs real money per token, takes seconds to complete, and returns variable-length responses. None of that fits inside a blockchain transaction. But everything *around* inference — who owns the agent, what config it uses, what it said, what tools it can access, what memory it has — benefits enormously from being on-chain.

The hybrid split gives you the best of both worlds: blockchain-grade ownership and verifiability for state, with the flexibility and performance of off-chain compute for inference.

## Data Flow

```
                    YOUR MACHINE                              FLOW BLOCKCHAIN
              ┌─────────────────────┐                   ┌─────────────────────┐
              │                     │                   │                     │
  User ──────►│  Channel Adapter    │                   │                     │
  (CLI/Web/   │  (Telegram, TUI,   │                   │                     │
   Telegram)  │   Web UI)          │                   │                     │
              │       │            │                   │                     │
              │       ▼            │                   │                     │
              │  ┌────────────┐   │    Encrypted Tx   │  ┌───────────────┐  │
              │  │ Encryption │───┼───────────────────►│  │ AgentSession  │  │
              │  │  Manager   │   │                   │  │ (stores       │  │
              │  └────────────┘   │                   │  │  ciphertext)  │  │
              │       │           │                   │  └───────┬───────┘  │
              │       │           │                   │          │          │
              │       │           │    Event fires    │          ▼          │
              │       │           │◄──────────────────│  InferenceRequested │
              │       ▼           │                   │    (hash only)      │
              │  ┌────────────┐   │                   │                     │
              │  │ Decrypt    │   │                   │                     │
              │  │ history    │   │                   │                     │
              │  └────────────┘   │                   │                     │
              │       │           │                   │                     │
              │       ▼           │                   │                     │
              │  ┌────────────┐   │                   │                     │
              │  │ LLM Call   │   │                   │                     │
              │  │ (Anthropic │   │                   │                     │
              │  │  OpenAI,   │   │                   │                     │
              │  │  Ollama)   │   │                   │                     │
              │  └────────────┘   │                   │                     │
              │       │           │                   │                     │
              │       ▼           │                   │                     │
              │  ┌────────────┐   │    Encrypted Tx   │  ┌───────────────┐  │
              │  │ Encrypt    │───┼───────────────────►│  │ AgentSession  │  │
              │  │ response   │   │                   │  │ (stores       │  │
              │  └────────────┘   │                   │  │  ciphertext)  │  │
              │       │           │                   │  └───────────────┘  │
              │       ▼           │                   │                     │
              │  Display to user  │                   │                     │
              └─────────────────────┘                   └─────────────────────┘
```

## On-Chain Components

Each Flow account that runs FlowClaw gets 10 Cadence Resources stored in its private `/storage/`:

**AgentRegistry.Agent** — The core identity. Holds inference config (provider, model, API key hash, max tokens, temperature, system prompt), security policy (autonomy level, rate limits, cost caps, allowed/denied tools), and usage stats. This is the "who am I and what am I allowed to do" of your agent.

**AgentSession.SessionManager** — Manages multiple conversation sessions. Each session is its own Resource containing messages (encrypted ciphertext), pending inference requests, token counts, and a context window that auto-compacts when it gets too long.

**AgentMemory.MemoryVault** — Key-value store with tag-based indexing. The agent can store and recall memories across sessions. Content is encrypted; tags can be plaintext (for on-chain indexing) or encrypted (if you want full opacity).

**ToolRegistry.ToolCollection** — Registry of tools the agent can use (memory_store, memory_recall, shell_exec, web_fetch, flow_query, flow_transact). Also logs every tool execution for auditability.

**InferenceOracle.OracleConfig** — Controls which relay addresses are authorized to post inference results for this account. Includes deduplication tracking to prevent double-posting.

**AgentScheduler.Scheduler** — Manages recurring tasks using Flow's validator-executed scheduled transactions. Tasks self-reschedule after execution. Supports categories like memory_cleanup, health_check, data_sync, report_generation, and custom tasks.

**AgentLifecycleHooks.HookManager** — Port of OpenClaw PR #12082's Plugin Lifecycle Interception Hook Architecture. Defines 20 lifecycle phases (from gatewayPreStart through postScheduledTask) with priority-sorted execution, fail-open/fail-closed modes, and scope-based gating.

**AgentExtensions.ExtensionManager** — Per-account extension management. Install, uninstall, enable, disable extensions from the global registry. Tracks which extensions are active and their configuration.

**AgentEncryption.EncryptionConfig** — Stores encryption key fingerprints (never the actual key), supports key rotation with history so old messages can still be decrypted, and tracks encryption/verification stats.

**FlowClaw.AgentStack** — The orchestrator that coordinates between all the other resources. Provides the high-level API: `sendMessage`, `completeInference`, `processToolResult`, `storeMemory`, `recallMemory`.

## Off-Chain Components

**Inference Relay** (`flowclaw_relay.py`) — A Python process that runs on your machine. It polls the Flow Access Node for `InferenceRequested` events, decrypts the message history, calls the configured LLM provider, encrypts the response, and posts it back on-chain. Each relay instance serves exactly one Flow account.

**Encryption Manager** — Handles XChaCha20-Poly1305 encryption and decryption. The 256-bit key is generated locally and stored at `~/.flowclaw/encryption.key`. Supports PyNaCl (preferred), the `cryptography` library (fallback), and a development-only XOR placeholder.

**Tool Executor** — Runs tool calls in a sandboxed environment. Dangerous commands (rm -rf, sudo, etc.) are denied. Tool results are fed back into the LLM for multi-turn agentic loops (up to 10 turns).

**LLM Providers** — Pluggable provider abstraction supporting Anthropic Claude, OpenAI GPT, and Ollama (local models). Each provider normalizes the response format so the relay doesn't care which one you're using.

## Storage Model

Cadence's storage model is central to FlowClaw's privacy design:

```
Flow Account 0x1234
├── /storage/              ← PRIVATE (only account owner + capabilities)
│   ├── FlowClawAgent          Agent config, security policy
│   ├── FlowClawSessionManager Sessions with encrypted messages
│   ├── FlowClawMemoryVault    Encrypted memories
│   ├── FlowClawToolCollection Tool definitions, exec logs
│   ├── FlowClawOracleConfig   Authorized relays
│   ├── FlowClawScheduler      Recurring tasks
│   ├── FlowClawHookManager    Lifecycle hooks
│   ├── FlowClawExtensionMgr   Installed extensions
│   ├── FlowClawEncryption     Key fingerprints
│   └── FlowClawStack          Orchestrator
│
└── /public/               ← READABLE BY ANYONE
    └── FlowClawAgentInfo       Name, description, version (opt-in)
```

The `/storage/` path is private by default. Other accounts cannot read it. The only way to grant access is via Cadence capabilities, which are explicit, revocable, and entitlement-scoped.

## Event Model

Events are publicly visible on-chain. FlowClaw's events are designed to expose only metadata, never content:

| Event | What's visible | What's NOT visible |
|---|---|---|
| `InferenceRequested` | requestId, sessionId, agentId, owner, provider, model, **contentHash** | Message content |
| `InferenceCompleted` | requestId, sessionId, **responseHash**, tokensUsed | Response content |
| `MessageAdded` | sessionId, role, **contentHash** | Message content |
| `MemoryStored` | memoryId, key | Memory content |
| `SessionCreated` | sessionId, agentId, owner | Session contents |

Hashes allow verification (you can prove what was said) without revealing the content.

## Transaction Argument Visibility

This is the privacy challenge FlowClaw solves with encryption. Transaction arguments are publicly visible in Flow's transaction data. Before encryption, if you sent `content: "What is FLOW?"`, anyone could read that on a block explorer. After encryption, the same transaction carries `ciphertext: "x7Fk9mQ2a8..."` — meaningless without the encryption key that lives on your machine.

See [Encryption](encryption.md) for the full details.

---

[← Back to README](../README.md) | [Encryption →](encryption.md)
