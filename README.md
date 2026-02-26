# FlowClaw

**An agentic AI harness on the Flow blockchain — private inference, verifiable history, permissionless extensions.**

FlowClaw reimagines [OpenClaw](https://github.com/openclaw/openclaw) as a blockchain-native system. Every agent is a Cadence Resource owned by a Flow account. Your conversations are end-to-end encrypted. Your config, memory, and session history live in your account's private storage. Nobody — not even FlowClaw's creators — can read your messages or control your agent.

```
┌──────────────────────────────────────────────────────────┐
│  Your Flow Account                                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐  │
│  │  Agent   │  │ Sessions │  │  Memory  │  │  Tools  │  │
│  │ Resource │  │ Resource │  │ Resource │  │Resource │  │
│  └──────────┘  └──────────┘  └──────────┘  └─────────┘  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐  │
│  │ Oracle   │  │Scheduler │  │Lifecycle │  │Extension│  │
│  │ Config   │  │ Resource │  │  Hooks   │  │ Manager │  │
│  └──────────┘  └──────────┘  └──────────┘  └─────────┘  │
│  ┌──────────────────────────────────────────────────────┐ │
│  │              Encryption Config                       │ │
│  │  (key fingerprint only — real key never on-chain)    │ │
│  └──────────────────────────────────────────────────────┘ │
└───────────────────────┬──────────────────────────────────┘
                        │ Events ↓        ↑ Encrypted Txs
┌───────────────────────┴──────────────────────────────────┐
│  Your Local Relay (runs on YOUR machine)                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐   │
│  │Encryption│  │   LLM    │  │    Tool Executor     │   │
│  │ Manager  │  │ Provider │  │ (memory, web, shell) │   │
│  └──────────┘  └──────────┘  └──────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

## Why FlowClaw?

| Problem with traditional agents | FlowClaw's solution |
|---|---|
| Maintainers control what gets merged | Permissionless extension system — publish without approval |
| Cron jobs are unreliable | Flow's validator-executed scheduled transactions |
| No proof your agent said what it said | Every message is hashed and stored on-chain |
| Platform can read your conversations | E2E encryption — chain only sees ciphertext |
| Agent config lives on someone else's server | Config is a Cadence Resource in YOUR account |

## Quick Start

### Prerequisites

- Python 3.11+ (with `cryptography` and `requests` libraries)
- An LLM API key (Venice AI, Anthropic, OpenAI, or Ollama for local models)
- [Flow CLI](https://developers.flow.com/tools/flow-cli) (v1.0+) — optional, used as fallback only

### 1. Clone and install

```bash
git clone https://github.com/yourorg/flowclaw.git
cd flowclaw
pip3 install requests cryptography
```

### 2. Configure

Create `.env` in the project root:

```env
FLOW_NETWORK=testnet
FLOW_ACCOUNT_ADDRESS=0x808983d30a46aee2
FLOW_PRIVATE_KEY=<your-private-key-hex>
VENICE_API_KEY=<your-venice-api-key>
```

### 3. Start the relay

```bash
cd flowclaw
python3.11 -m uvicorn relay.api:app --host 0.0.0.0 --port 8000 --reload
```

The relay auto-registers your encryption key on-chain and syncs all on-chain state at startup.

### 4. Start the frontend

```bash
cd frontend
npm install && npm run dev
```

## REST API Architecture

FlowClaw's relay communicates directly with the Flow Access REST API — no CLI subprocess calls needed. All blockchain operations use pure Python:

- **Script execution**: HTTP POST to `/v1/scripts` with base64-encoded Cadence
- **Transaction signing**: ECDSA P-256 + SHA3-256 with RLP-encoded payloads
- **Transaction submission**: HTTP POST to `/v1/transactions` with base64-encoded envelope
- **Account queries**: HTTP GET to `/v1/accounts/{addr}?expand=keys`

The `FlowRESTClient` (`relay/flow_client.py`) handles all of this, with automatic CLI fallback if needed.

### Transaction Signing Details

Flow transactions use a specific RLP encoding structure:

- **Payload**: 9 flat fields — `[script, arguments, refBlockId, gasLimit, proposalKeyAddress, proposalKeyIndex, proposalKeySequenceNumber, payer, authorizers]`
- **Envelope**: 2 nested items — `[[payload], [payloadSignatures]]`
- **Domain tag**: `FLOW-V0.0-transaction` right-padded to 32 bytes
- **Signing**: SHA3-256 hash of `domainTag + envelopeRLP`, signed with ECDSA P-256

For single-signer transactions (proposer = authorizer = payer), payload signatures are empty and only the envelope is signed.

### Import Resolution

The REST API requires fully-qualified contract imports. The relay automatically resolves three import styles from `flow.json` aliases:

1. Cadence 1.0 quoted: `import "AgentSession"` → `import AgentSession from 0x808983d30a46aee2`
2. Legacy bare: `import AgentSession` → `import AgentSession from 0x808983d30a46aee2`
3. Relative path: `import AgentSession from "../contracts/AgentSession.cdc"` → `import AgentSession from 0x808983d30a46aee2`

## How It Works

When you send a message, here's the full encrypted flow:

1. You type "What is FLOW?" in your client (CLI, web UI, Telegram)
2. Your local relay encrypts this with XChaCha20-Poly1305
3. The relay submits a `send_message` transaction with the **ciphertext** (never plaintext)
4. On-chain: the encrypted message is stored in your session, an `InferenceRequested` event fires
5. Your relay picks up the event, fetches the encrypted history, decrypts it locally
6. The relay calls your LLM provider (Anthropic, OpenAI, Ollama) with the **plaintext**
7. The LLM responds — the relay encrypts the response
8. The relay submits `complete_inference_owner` with **encrypted response**
9. On-chain: encrypted response is stored, `InferenceCompleted` event fires
10. Your relay decrypts and displays the response to you

Block explorers see ciphertext at every step. The plaintext exists only in your relay's memory during inference.

## Documentation

| Document | What it covers |
|---|---|
| [Architecture](docs/architecture.md) | Hybrid on-chain/off-chain design, data flow, storage model |
| [Encryption](docs/encryption.md) | E2E encryption, key management, what's public vs private |
| [Extensions](docs/extensions.md) | Permissionless extension system, publishing, installing |
| [Relay Setup](docs/relay-setup.md) | Configuring the relay, providers, channels, deployment |
| [Contract Reference](docs/contracts.md) | All 10 contracts — resources, entitlements, events |
| [Comparison](docs/comparison.md) | FlowClaw vs OpenClaw — honest pros and cons |
| [Mainnet Checklist](docs/mainnet-checklist.md) | Step-by-step guide for mainnet deployment |

## Contracts

FlowClaw deploys 10 Cadence contracts:

| Contract | Purpose |
|---|---|
| `AgentRegistry` | Agent creation, ownership, config, rate limiting |
| `AgentSession` | Multi-turn conversations, context windowing |
| `InferenceOracle` | Relay authorization, deduplication |
| `ToolRegistry` | Tool definitions, execution logging |
| `AgentMemory` | On-chain key-value memory with tag search |
| `AgentScheduler` | Validator-executed recurring tasks |
| `AgentLifecycleHooks` | 20-phase plugin lifecycle (port of OpenClaw PR #12082) |
| `AgentExtensions` | Permissionless extension marketplace |
| `AgentEncryption` | E2E encryption config, key rotation |
| `FlowClaw` | Main orchestrator tying everything together |

## Project Structure

```
flowclaw/
├── contracts/                    # Cadence smart contracts (10 contracts)
│   ├── AgentRegistry.cdc
│   ├── AgentSession.cdc
│   ├── InferenceOracle.cdc
│   ├── ToolRegistry.cdc
│   ├── AgentMemory.cdc
│   ├── AgentScheduler.cdc
│   ├── AgentLifecycleHooks.cdc
│   ├── AgentExtensions.cdc
│   ├── AgentEncryption.cdc
│   └── FlowClaw.cdc
├── transactions/                 # Cadence transactions (15 transactions)
│   ├── initialize_account.cdc
│   ├── send_message.cdc              # E2E encrypted
│   ├── complete_inference_owner.cdc   # E2E encrypted
│   ├── configure_encryption.cdc
│   ├── create_session.cdc
│   ├── store_memory.cdc              # E2E encrypted
│   ├── authorize_relay.cdc
│   ├── update_config.cdc
│   ├── schedule_task.cdc
│   ├── cancel_task.cdc
│   ├── register_hook.cdc
│   ├── publish_extension.cdc
│   ├── install_extension.cdc
│   └── uninstall_extension.cdc
├── scripts/                      # Read-only Cadence scripts
│   ├── get_agent_info.cdc
│   ├── get_session_history.cdc
│   ├── get_account_status.cdc
│   ├── get_global_stats.cdc
│   ├── get_scheduled_tasks.cdc
│   └── get_hooks.cdc
├── relay/                        # Off-chain Python relay
│   ├── api.py                        # FastAPI relay server
│   ├── flow_client.py                # Flow REST API client (RLP, signing, scripts, txs)
│   ├── account_manager.py            # Account creation and management
│   ├── tx_executor.py                # Transaction execution helpers
│   ├── gas_sponsor.py                # Gas sponsorship for user transactions
│   ├── test_signing.py               # Diagnostic test for transaction signing
│   └── .env.example
├── extensions/examples/          # Example extensions
│   ├── SentimentGuard.cdc
│   ├── FlowDeFiTools.cdc
│   └── ConversationSummarizer.cdc
├── docs/                         # Documentation
├── flowclaw-ui.jsx               # React frontend (tabbed UI)
└── flow.json                     # Flow project config
```

## Status

**v0.2.0-alpha** — Testnet-deployed and functional. All 11 Cadence contracts deployed on Flow testnet. Relay uses pure REST API for all blockchain operations (no CLI dependency). ECDSA P-256 transaction signing with SHA3-256 and RLP encoding. E2E encryption with XChaCha20-Poly1305. Cognitive memory engine with molecular bonding. Venice AI and Ollama provider support. React frontend with real-time on-chain chat.

**Not yet production-ready.** Needs: formal security audit, streaming support, gas optimization, multi-user support, and channel adapter implementations (Telegram, Discord).

## Contributing

FlowClaw is designed so that most contributions don't need to go through this repo at all. Extensions are published permissionlessly on-chain — no PR required. For core contract changes, PRs are welcome.

## Inspiration

FlowClaw reimagines [OpenClaw](https://github.com/openclaw/openclaw) and [ZeroClaw](https://github.com/theonlyhennygod/zeroclaw) for the blockchain era. Where those projects run agents entirely off-chain, FlowClaw anchors the agent harness on Flow and uses Cadence's resource model for ownership and privacy guarantees that no off-chain system can provide.

## License

MIT
