# FlowClaw vs OpenClaw

An honest comparison. FlowClaw isn't better at everything — it makes real tradeoffs. Here's where each approach wins and where it loses.

## Where FlowClaw Wins

### True Agent Ownership

In OpenClaw, your agent is a configuration file on a server. The person running the server can read your config, modify your conversations, or shut down the service. Your agent exists at someone else's discretion.

In FlowClaw, your agent is a Cadence Resource stored in your Flow account's private storage. Cadence Resources use move semantics — they can't be copied, only moved. The only person who can access your agent is you (or someone you explicitly grant a capability to). If FlowClaw's creators disappear tomorrow, your agent still exists on-chain.

### Message Privacy

OpenClaw stores conversations in a database. The server operator can read everything. There's no encryption between you and the storage layer.

FlowClaw encrypts every message with XChaCha20-Poly1305 before it touches the blockchain. The encryption key lives on your machine. Block explorers, validators, and other accounts see ciphertext. The plaintext only exists in your relay's memory during inference.

### Reliable Scheduling

OpenClaw uses OS-level cron for scheduled tasks. If the server restarts, cron jobs can be lost. If the process crashes, scheduled tasks don't fire. This has been a persistent reliability issue.

FlowClaw uses Flow's validator-executed scheduled transactions. These are protocol-level — validators execute them as part of block production. They self-reschedule after execution. No OS dependency, no process to crash.

### Verifiable History

In OpenClaw, conversation history lives in a database. It can be edited or deleted without anyone knowing.

In FlowClaw, every message has its plaintext hash stored on-chain. If you ever need to prove what your agent said (or what you said to it), you can decrypt the message and demonstrate that its SHA-256 matches the immutable on-chain hash.

### Decentralized Extensions

OpenClaw uses a PR-based model for extensions. You write a plugin, submit a PR, and wait for the maintainer to review and merge it. If they disagree with your approach or are busy, your feature doesn't ship.

FlowClaw's extension registry is permissionless. Publish your extension on-chain. Users install what they want. No gatekeeper. The centralization risk that exists in any GitHub repo (the maintainer controls merge access) is eliminated.

### Multi-Provider Without Centralization

In OpenClaw, the server decides which providers are available. In FlowClaw, your agent's provider config is in your private storage. Switch between Anthropic, OpenAI, and Ollama by updating your on-chain config. Nobody else is involved.

## Where OpenClaw Wins

### Latency

OpenClaw: ~1-2 seconds from message to response (direct API call).

FlowClaw: ~3-5 seconds. The overhead comes from transaction submission, block finalization, event polling, and posting the response back on-chain. For a casual chat this is fine, but for applications that need sub-second responses, it's a real drawback.

### Streaming

OpenClaw supports streaming responses — tokens appear as the LLM generates them. FlowClaw currently does not. The relay waits for the complete response, encrypts it, and posts it on-chain in one transaction. Streaming would require a fundamentally different architecture (possibly off-chain streaming with periodic on-chain checkpoints).

### Setup Simplicity

OpenClaw: `npm install openclaw && openclaw start`. Done.

FlowClaw: Install Flow CLI, start an emulator, deploy 10 contracts, initialize your account, set up encryption, configure the relay, run the relay. It's a full blockchain development workflow. The learning curve is steep if you're not already in the Flow ecosystem.

### Cost

OpenClaw: Free to run (beyond API costs). No gas fees, no blockchain transactions.

FlowClaw: Every message is two transactions (send + complete). On mainnet, each transaction costs FLOW tokens for gas. At current prices this is fractions of a cent per message, but it adds up for heavy usage. On the emulator and testnet, it's free.

### Channel Ecosystem

OpenClaw has mature, production-tested adapters for Telegram, Discord, Slack, and web UIs. FlowClaw currently has a CLI mode and a React prototype. The channel adapter pattern is the same (the relay sits between the channel and the chain), but the implementations aren't built yet.

### Ecosystem and Community

OpenClaw has an existing user base, documentation, and battle-tested codebase (especially ZeroClaw with 1017 tests). FlowClaw is a proof of concept. It works, but it hasn't been stress-tested in production.

## Side-by-Side

| Feature | OpenClaw | FlowClaw |
|---|---|---|
| **Ownership** | Platform-controlled | Cadence Resource (you own it) |
| **Privacy** | Trust the server | E2E encrypted on-chain |
| **History** | Mutable database | Immutable chain + hashes |
| **Extensions** | PR-gated | Permissionless registry |
| **Scheduling** | OS cron (unreliable) | Validator-executed (protocol-level) |
| **Latency** | ~1-2s | ~3-5s |
| **Streaming** | Yes | Not yet |
| **Setup** | `npm install` | Flow CLI + emulator + relay |
| **Cost** | Free (no gas) | Gas per transaction |
| **Channels** | Telegram, Discord, Slack, Web | CLI, Web (React prototype) |
| **Providers** | 22+ (ZeroClaw) | 3 (Anthropic, OpenAI, Ollama) |
| **Memory** | SQLite + FTS5 | On-chain key-value + tag index |
| **Encryption** | ChaCha20-Poly1305 (ZeroClaw) | XChaCha20-Poly1305 (same family) |
| **Tests** | 1017 (ZeroClaw) | Structural + syntax verification |
| **Maturity** | Production-used | Proof of concept |

## User Experience Comparison

### Sending a message

**OpenClaw:** Type in Telegram → server receives plaintext → calls LLM → stores in DB → responds in Telegram. ~1-2 seconds.

**FlowClaw:** Type in client → relay encrypts → submits transaction → chain stores ciphertext → event fires → relay picks up event → decrypts history → calls LLM → encrypts response → submits transaction → chain stores ciphertext → relay decrypts → displays response. ~3-5 seconds.

The user experience feels the same once it's running — you type, you get a response. The difference is in the plumbing underneath.

### Changing your provider

**OpenClaw:** Edit config file → restart.

**FlowClaw:** Submit `update_config` transaction → relay picks up new config from next event. No restart needed.

### Adding a feature

**OpenClaw:** Write plugin → submit PR → wait for review → wait for merge → tell users to update.

**FlowClaw:** Write extension → publish on-chain → share the extension name → users install directly. No review cycle.

## When to Use Which

**Use OpenClaw if:** You want the simplest setup, need streaming, need sub-2-second latency, want the broadest channel support, or don't care about on-chain verifiability.

**Use FlowClaw if:** You want true ownership of your agent, need provable conversation history, want E2E encrypted messages, need reliable scheduling, want to publish extensions without a gatekeeper, or are already building on Flow.

**Use both:** They're not mutually exclusive. You could run OpenClaw as your primary agent and use FlowClaw to anchor a verifiable, encrypted copy of your conversation history on-chain.

---

[← Contract Reference](contracts.md) | [Back to README →](../README.md)
