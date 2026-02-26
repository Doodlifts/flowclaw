# Extensions

FlowClaw's extension system solves one of the biggest problems with traditional agent frameworks: centralization. In standard OpenClaw, if you want to add a feature, you submit a PR and wait for the maintainer to merge it. If they don't like it, disagree with your approach, or are simply busy, your feature never ships.

FlowClaw replaces this with a permissionless on-chain registry. Anyone can publish an extension. Anyone can install it. No gatekeepers.

## How It Works

The extension system has two parts:

**ExtensionRegistry** — A global resource (deployed once, accessible to everyone) that acts as a marketplace. Anyone can publish an extension here. It stores metadata: name, description, version, author, category, required entitlements, and a content hash of the extension code.

**ExtensionManager** — A per-account resource that manages which extensions you have installed. You browse the registry, install what you want, enable/disable at will. Your agent, your choice.

## Extension Categories

| Category | What it adds | Example |
|---|---|---|
| `tool` | New tools for the agent | DeFi integrations, API connectors |
| `hook` | Lifecycle interceptors | Content filters, logging, analytics |
| `memory` | Memory enhancements | Summarization, semantic search |
| `channel` | Communication adapters | Telegram bot, Discord bot |
| `security` | Security features | Rate limiting, anomaly detection |
| `analytics` | Monitoring/reporting | Usage dashboards, cost tracking |
| `integration` | External service bridges | GitHub, Slack, email |
| `custom` | Anything else | Whatever you build |

## Publishing an Extension

Anyone with a Flow account can publish:

```bash
flow transactions send transactions/publish_extension.cdc \
  --arg "String:my-sentiment-guard" \
  --arg "String:SentimentGuard" \
  --arg "String:Analyzes message sentiment before sending" \
  --arg "String:1.0.0" \
  --arg "UInt8:1" \
  --arg "String:<content-hash>" \
  --arg "[String]:[]" \
  --arg "[String]:[\"RegisterHooks\", \"TriggerHooks\"]" \
  --network emulator
```

The registry enforces:
- Unique names (no squatting — first come, first served)
- Valid content hashes
- Required entitlement declarations (so users know what permissions an extension needs before installing)

## Installing an Extension

Browse the registry, then install:

```bash
# Install by name
flow transactions send transactions/install_extension.cdc \
  --arg "String:sentiment-guard-by-0x1234" \
  --network emulator

# Uninstall
flow transactions send transactions/uninstall_extension.cdc \
  --arg "String:sentiment-guard-by-0x1234" \
  --network emulator
```

The ExtensionManager checks that all required entitlements are available before installation. If an extension requires `RegisterHooks` but your HookManager doesn't exist, installation fails with a clear error.

## Example Extensions

FlowClaw ships with three example extensions that demonstrate different patterns:

### SentimentGuard

A lifecycle hook extension that analyzes message sentiment before sending. It registers a hook on the `preMessageSend` phase and can block messages that seem hostile or confused. Demonstrates the hook + content analysis pattern.

**Category:** hook
**Required entitlements:** RegisterHooks, TriggerHooks

### FlowDeFiTools

A tool extension that adds DeFi capabilities: `swap_tokens`, `check_balance`, `get_pool_stats`, `set_price_alert`. The `swap_tokens` tool has `requiresApproval: true`, which means the agent must get user confirmation before executing it. Demonstrates the tool + approval pattern.

**Category:** tool
**Required entitlements:** ManageTools, ExecuteTools

### ConversationSummarizer

A composite extension that uses hooks, scheduling, and memory together. It registers a hook on `postInferenceComplete` to track conversation length, schedules a recurring summarization task, and stores summaries in memory. Demonstrates how extensions can combine multiple FlowClaw features.

**Category:** memory
**Required entitlements:** RegisterHooks, Schedule, Store

## Building Your Own Extension

An extension is a Cadence contract (or set of contracts) that interacts with FlowClaw's resources via entitlements. The general pattern:

1. Define what your extension does (add tools? intercept hooks? store data?)
2. Declare which entitlements it needs
3. Write the Cadence code
4. Publish to the registry with a content hash
5. Users install it and grant the required entitlements

Extensions run within Cadence's safety model — they can only access what they're granted via entitlements. A tool extension can't read your memory unless it also declares and receives `Recall` entitlement. A hook extension can't modify your tools unless it declares `ManageTools`.

## Extension vs PR: The Tradeoff

| | Traditional PR | FlowClaw Extension |
|---|---|---|
| Who decides if it ships | Maintainer | You (the publisher) |
| Who decides if it's installed | Maintainer (for everyone) | Each user individually |
| Review process | Code review by maintainers | User reviews entitlement requirements |
| Rollback | Maintainer reverts PR | User uninstalls extension |
| Risk | Maintainer vetted the code | User trusts the publisher |
| Discoverability | Listed in repo docs | Listed in on-chain registry |

The tradeoff is clear: more freedom means more responsibility. There's no maintainer vetting extensions before they're published. Users should review what entitlements an extension requests and who published it before installing. The registry stores the publisher's Flow address, so reputation can develop over time.

---

[← Encryption](encryption.md) | [Relay Setup →](relay-setup.md)
