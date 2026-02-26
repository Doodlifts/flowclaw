# Contract Reference

FlowClaw deploys 10 Cadence contracts. Each contract manages a specific concern and uses Cadence's entitlement system for fine-grained access control.

## AgentRegistry

**Purpose:** Agent creation, ownership, inference configuration, security policies, and rate limiting.

**Storage path:** `/storage/FlowClawAgent`

**Entitlements:**

| Entitlement | Grants |
|---|---|
| `Configure` | Change inference config, security policy |
| `Execute` | Record inference, record cost, check rate limits |
| `Admin` | Pause/unpause agent, change name |

**Key types:**

`InferenceConfig` — Holds provider (anthropic/openai/ollama), model name, API key hash (never the actual key), max tokens, temperature, and system prompt.

`SecurityPolicy` — Defines autonomy level (0=supervised, 1=semi-auto, 2=autonomous), max actions per hour, max cost per day, and allowed/denied tool lists.

`Agent` (Resource) — The core agent identity. Stores its config, security policy, usage stats (total inferences, total cost, inference count today), and active/paused state. Rate limiting is enforced on-chain — the relay can't bypass it.

**Events:** `AgentCreated`, `AgentConfigUpdated`, `AgentPaused`, `AgentResumed`

---

## AgentSession

**Purpose:** Multi-turn conversation management with context windowing and inference request tracking.

**Storage path:** `/storage/FlowClawSessionManager`

**Entitlements:**

| Entitlement | Grants |
|---|---|
| `Manage` | Create sessions, add messages, request/complete inference |
| `ReadHistory` | Read messages, get message count |

**Key types:**

`Message` — A single turn: id, role (user/assistant/system/tool), content (ciphertext after encryption), contentHash (SHA-256 of plaintext), timestamp, optional toolName and toolCallId, and tokensEstimate.

`InferenceRequest` — Tracks a pending LLM call: requestId, sessionId, agentId, owner, provider, model, messagesHash, maxTokens, temperature, status (pending/completed/failed).

`Session` (Resource) — A conversation. Stores messages, pending requests, and auto-compacts when the context window exceeds `maxContextMessages` (keeps system messages, removes oldest non-system messages).

`SessionManager` (Resource) — Collection of sessions per account. Supports creating sessions, borrowing session references, and listing session IDs.

**Events:** `SessionCreated`, `MessageAdded` (contentHash only), `SessionCompacted`, `SessionClosed`, `InferenceRequested` (hashes only), `InferenceCompleted` (hash + token count)

---

## InferenceOracle

**Purpose:** Relay authorization and deduplication. Controls which addresses can post inference results for your account.

**Storage path:** `/storage/FlowClawOracleConfig`

**Entitlements:**

| Entitlement | Grants |
|---|---|
| `ManageRelays` | Add/remove authorized relay addresses |
| `Relay` | Check authorization, mark requests as completed |

**Key types:**

`RelayAuth` — Authorized relay: address, label, authorized timestamp, isActive flag.

`OracleConfig` (Resource) — Stores authorized relays and completed request IDs. Prevents double-posting (if a request ID has already been completed, the transaction fails).

**Events:** `RelayAuthorized`, `RelayRevoked`

---

## ToolRegistry

**Purpose:** Tool definitions for LLM function calling and execution logging.

**Storage path:** `/storage/FlowClawToolCollection`

**Entitlements:**

| Entitlement | Grants |
|---|---|
| `ManageTools` | Add/remove tool definitions |
| `ExecuteTools` | Log tool executions |

**Key types:**

`ToolParameter` — A tool's input parameter: name, type, description, required flag.

`ToolDefinition` — A tool: name, description, parameters, requiresApproval flag, isBuiltIn flag.

`ToolExecution` — Log entry: toolName, agentId, sessionId, inputHash, outputHash, status, executionTimeMs, timestamp.

`ToolCollection` (Resource) — Stores tool definitions and execution log. Comes pre-loaded with 6 built-in tools: memory_store, memory_recall, shell_exec, web_fetch, flow_query, flow_transact.

**Events:** `ToolRegistered`, `ToolExecuted`, `ToolRemoved`

---

## AgentMemory

**Purpose:** On-chain key-value memory with tag-based search.

**Storage path:** `/storage/FlowClawMemoryVault`

**Entitlements:**

| Entitlement | Grants |
|---|---|
| `Store` | Store/upsert memory entries |
| `Recall` | Read by key, tag, or recent |
| `Forget` | Delete entries |

**Key types:**

`MemoryEntry` — A memory: id, key, content (ciphertext), contentHash, tags, source (which session/tool created it), timestamps (created, updated), version.

`MemoryVault` (Resource) — Key-value store with keyIndex and tagIndex for efficient lookup. Supports store (upsert), getByKey, getByTag, getRecent, deleteByKey, deleteById.

**Events:** `MemoryStored`, `MemoryUpdated`, `MemoryDeleted`

---

## AgentScheduler

**Purpose:** Reliable recurring tasks using Flow's validator-executed scheduled transactions. Replaces OpenClaw's OS-level cron.

**Storage path:** `/storage/FlowClawScheduler`

**Entitlements:**

| Entitlement | Grants |
|---|---|
| `Schedule` | Create and modify tasks |
| `Execute` | Execute and reschedule tasks |
| `Cancel` | Cancel tasks |
| `Admin` | Pause/resume all tasks |

**Key types:**

`TaskCategory` — Enum: memoryCleanup, healthCheck, dataSync, reportGeneration, sessionCompact, costMonitor, customTask.

`RecurrenceRule` — Interval in seconds, max occurrences (0 = unlimited), end time (0.0 = never).

`ScheduledTask` — Full task: id, name, category, config (action, target, parameters), recurrence, execution stats (count, last/next execution, consecutive failures).

`Scheduler` (Resource) — Manages up to 50 tasks per account. Enforces minimum 60-second intervals. Tasks self-reschedule after execution. Includes presets: `everyMinute()`, `everyHour()`, `everyDay()`, `everyWeek()`.

**Events:** `TaskScheduled`, `TaskExecuted`, `TaskCancelled`, `TaskFailed`, `TaskRescheduled`

---

## AgentLifecycleHooks

**Purpose:** Port of OpenClaw PR #12082's Plugin Lifecycle Interception Hook Architecture to Cadence. Allows extensions to intercept and modify behavior at 20 different lifecycle phases.

**Storage path:** `/storage/FlowClawHookManager`

**Entitlements:**

| Entitlement | Grants |
|---|---|
| `RegisterHooks` | Register and unregister hooks |
| `TriggerHooks` | Fire hooks at lifecycle phases |
| `ReadOnly` | List registered hooks |
| `Modify` | Modify hook configs |
| `Intercept` | Override hook results |

**Key types:**

`LifecyclePhase` — 20 enum values covering the full agent lifecycle: gatewayPreStart, gatewayPostStart, preProviderSelect, postProviderSelect, preMessageSend, postMessageSend, preInferenceRequest, postInferenceRequest, preInferenceComplete, postInferenceComplete, preToolExecution, postToolExecution, preMemoryStore, postMemoryStore, preMemoryRecall, postMemoryRecall, preSessionCreate, postSessionCreate, preScheduledTask, postScheduledTask.

`FailMode` — failOpen (continue on hook error) or failClosed (abort on hook error).

`HookConfig` — Priority (lower = runs first), failMode, timeout, maxRetries, scope gating (allowedChannels, allowedTools, allowedSessions).

`HookManager` (Resource) — Manages hooks per account. Priority-sorted execution. Scope-based gating so hooks only fire for specific channels, tools, or sessions.

**Events:** `HookRegistered`, `HookTriggered`, `HookCompleted`, `HookFailed`, `HookUnregistered`

---

## AgentExtensions

**Purpose:** Permissionless extension marketplace. Anyone can publish; anyone can install.

**Storage path:** `/storage/FlowClawExtensionManager` (per-account), global `ExtensionRegistry`

**Entitlements:**

| Entitlement | Grants |
|---|---|
| `Install` | Install/uninstall/enable/disable extensions |
| `Publish` | Publish extensions to the global registry |
| `Configure` | Modify extension settings |

**Key types:**

`ExtensionCategory` — 8 enum values: tool, hook, memory, channel, security, analytics, integration, custom.

`ExtensionMetadata` — Name, displayName, description, version, author, category, contentHash, requiredEntitlements, dependencies, homepage, publishedAt.

`InstalledExtension` — Wraps metadata with installedAt, isEnabled, and per-account settings.

`ExtensionManager` (Resource) — Per-account. Install, uninstall, enable, disable, configure.

`ExtensionRegistry` (Resource) — Global marketplace. Publish, search, list by category. Enforces unique names.

**Events:** `ExtensionPublished`, `ExtensionInstalled`, `ExtensionUninstalled`, `ExtensionEnabled`, `ExtensionDisabled`

---

## AgentEncryption

**Purpose:** End-to-end encryption configuration, key fingerprint management, and key rotation.

**Storage path:** `/storage/FlowClawEncryption`

**Entitlements:**

| Entitlement | Grants |
|---|---|
| `ManageKeys` | Configure/rotate encryption keys |
| `Encrypt` | Record encryption operations |
| `Verify` | Verify payloads against registered keys |

**Key types:**

`Algorithm` — xchacha20poly1305 or aes256gcm.

`KeyInfo` — fingerprint, algorithm, label, registeredAt, isActive. The actual key is NEVER stored on-chain.

`EncryptedPayload` — ciphertext, nonce, plaintextHash, keyFingerprint, algorithm, plaintextLength. This struct replaces plaintext in all transactions.

`EncryptionConfig` (Resource) — Stores registered key fingerprints (current + history for rotation), encryption/verification counters. The `verifyPayload` method checks that a payload was encrypted with a recognized key.

**Events:** `EncryptionKeyConfigured`, `EncryptionKeyRotated`, `EncryptedMessageStored`

---

## FlowClaw

**Purpose:** Main orchestrator. Ties all contracts together and provides the high-level API.

**Storage path:** `/storage/FlowClawStack`

**Entitlements:**

| Entitlement | Grants |
|---|---|
| `Owner` | Full control |
| `Operate` | Send messages, complete inference, store/recall memory |

**Key types:**

`AgentStack` (Resource) — The orchestrator. Methods: `sendMessage` (add user message + request inference), `completeInference` (add LLM response + verify relay authorization + dedup), `processToolResult` (add tool output to session), `storeMemory`, `recallMemory`, `recallMemoryByTag`.

`AccountStatus` — Public view: owner, agentInfo, sessionCount, memoryCount, toolCount, isRelayConfigured.

**Events:** `AccountInitialized`, `AgentLoopStarted`, `AgentLoopCompleted`, `UserMessageSent` (hash only), `AgentResponseReceived` (hash only)

**Version:** `0.1.0-alpha`

---

[← Relay Setup](relay-setup.md) | [Comparison →](comparison.md)
