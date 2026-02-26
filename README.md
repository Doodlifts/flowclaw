# FlowClaw

**An agentic AI harness on the Flow blockchain — private inference, verifiable history, permissionless extensions.**

FlowClaw reimagines [OpenClaw](https://github.com/openclaw/openclaw) as a blockchain-native system. Every agent is a Cadence Resource owned by a Flow account. Your conversations are end-to-end encrypted. Your config, memory, and session history live in your account's private storage. Nobody — not even FlowClaw's creators — can read your messages or control your agent.

## Get Started

Visit [flowclaw.app](https://flowclaw.app) to start chatting with your own on-chain agent. No wallet needed — FlowClaw creates a Flow account for you using passkey authentication (Face ID, Touch ID, or security key). Your agent is ready in seconds.

What happens when you sign up:

1. You authenticate with a passkey (biometric or security key)
2. FlowClaw creates a Flow account with your passkey as the signing key
3. An AI agent is deployed as a Cadence Resource in your account
4. Gas fees are sponsored — you don't need FLOW tokens to get started
5. Every conversation is E2E encrypted before touching the chain

Once you're in, you can chat with your agent, ask it to check your FLOW balance, send tokens, execute on-chain transactions, and more — all from the web UI.

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
│  │ Manager  │  │ Provider │  │ (memory, web, chain) │   │
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

## How It Works

When you send a message, here's the full encrypted flow:

1. You type a message in the web UI
2. Your relay encrypts it with XChaCha20-Poly1305
3. The relay submits a `send_message` transaction with the **ciphertext** (never plaintext)
4. On-chain: the encrypted message is stored in your session, an `InferenceRequested` event fires
5. Your relay picks up the event, fetches the encrypted history, decrypts it locally
6. The relay calls your LLM provider (Venice AI, Anthropic, OpenAI, Ollama) with the **plaintext**
7. The LLM responds — the relay encrypts the response
8. The relay submits `complete_inference_owner` with the **encrypted response**
9. On-chain: encrypted response is stored, `InferenceCompleted` event fires
10. Your relay decrypts and displays the response

Block explorers see ciphertext at every step. The plaintext exists only in your relay's memory during inference.

## Agent Capabilities

Your agent can do more than chat. It has on-chain tools:

- **Check balances** — query any Flow account's FLOW balance
- **Send tokens** — transfer FLOW to any address (with configurable safety limits)
- **Execute transactions** — run custom Cadence transactions on-chain
- **Web fetch** — pull data from external APIs and websites
- **Spawn sub-agents** — create child agents for parallel tasks
- **Cognitive memory** — store and recall information with molecular bonding

All agent actions are rate-limited and subject to your security policy.

## Contracts

FlowClaw deploys 11 Cadence contracts on Flow testnet (`0x808983d30a46aee2`):

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
| `CognitiveMemory` | Molecular memory bonding and dream cycles |
| `FlowClaw` | Main orchestrator tying everything together |

---

## For Developers

### Prerequisites

- Python 3.11+ (with `cryptography` and `requests`)
- Node.js 20+ (for the frontend)
- An LLM API key (Venice AI, Anthropic, OpenAI, or Ollama for local)

### Clone and install

```bash
git clone https://github.com/Doodlifts/flowclaw.git
cd flowclaw
pip3 install -r relay/requirements.txt
```

### Configure

```bash
cp .env.example .env
# Edit .env with your values
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for all environment variables.

### Start the relay

```bash
python3.11 -m uvicorn relay.api:app --host 0.0.0.0 --port 8000 --reload
```

The relay auto-registers your encryption key on-chain and syncs all on-chain state at startup.

### Start the frontend

```bash
cd frontend
npm install && npm run dev
```

### Docker

```bash
docker compose up --build
```

### REST API Architecture

The relay communicates directly with the Flow Access REST API — no CLI dependency. All blockchain operations use pure Python:

- **Script execution**: HTTP POST to `/v1/scripts` with base64-encoded Cadence
- **Transaction signing**: ECDSA P-256 + SHA3-256 with RLP-encoded payloads
- **Transaction submission**: HTTP POST to `/v1/transactions` with base64-encoded envelope
- **Account queries**: HTTP GET to `/v1/accounts/{addr}?expand=keys`

The `FlowRESTClient` (`relay/flow_client.py`) handles all of this.

#### Transaction Signing

Flow transactions use a specific RLP encoding structure:

- **Payload**: 9 flat fields — `[script, arguments, refBlockId, gasLimit, proposalKeyAddress, proposalKeyIndex, proposalKeySequenceNumber, payer, authorizers]`
- **Envelope**: 2 nested items — `[[payload], [payloadSignatures]]`
- **Domain tag**: `FLOW-V0.0-transaction` right-padded to 32 bytes
- **Signing**: SHA3-256 hash of `domainTag + envelopeRLP`, signed with ECDSA P-256

For single-signer transactions (proposer = authorizer = payer), payload signatures are empty and only the envelope is signed.

#### Import Resolution

The REST API requires fully-qualified contract imports. The relay automatically resolves three import styles from `flow.json` aliases:

1. Cadence 1.0 quoted: `import "AgentSession"` → `import AgentSession from 0x808983d30a46aee2`
2. Legacy bare: `import AgentSession` → `import AgentSession from 0x808983d30a46aee2`
3. Relative path: `import AgentSession from "../contracts/AgentSession.cdc"` → resolved from aliases

### Project Structure

```
flowclaw/
├── cadence/
│   ├── contracts/               # 11 Cadence smart contracts
│   ├── transactions/            # 20+ Cadence transactions
│   └── scripts/                 # Read-only Cadence scripts
├── relay/                       # Python relay server
│   ├── api.py                   # FastAPI relay (2500+ lines)
│   ├── flow_client.py           # Flow REST API client (signing, RLP, scripts, txs)
│   ├── cognitive_memory.py      # Molecular memory engine
│   ├── account_manager.py       # Passkey account creation
│   ├── tx_executor.py           # Agent tool execution
│   ├── gas_sponsor.py           # Gas sponsorship for users
│   ├── flowclaw_relay.py        # Core relay config, encryption, LLM providers
│   └── requirements.txt         # Pinned Python dependencies
├── frontend/                    # React + Tailwind web UI
│   └── src/
│       ├── App.jsx              # Main app with session management
│       ├── AgentCanvas.jsx      # Chat canvas
│       ├── flow-config.js       # FCL network configuration
│       └── api.js               # Relay API client
├── extensions/examples/         # Example Cadence extensions
├── docs/                        # Additional documentation
├── .github/workflows/ci.yml     # GitHub Actions CI
├── Dockerfile                   # Multi-stage production build
├── docker-compose.yml           # Full stack orchestration
├── flow.json                    # Flow project config (testnet + mainnet)
├── DEPLOYMENT.md                # Deployment guide
└── SECURITY.md                  # Security model documentation
```

## Documentation

| Document | What it covers |
|---|---|
| [Deployment Guide](DEPLOYMENT.md) | Local dev, Docker, testnet, and mainnet deployment |
| [Security Model](SECURITY.md) | Encryption, key management, safety limits, trust model |
| [Architecture](docs/architecture.md) | Hybrid on-chain/off-chain design, data flow, storage model |
| [Encryption](docs/encryption.md) | E2E encryption, key management, what's public vs private |
| [Extensions](docs/extensions.md) | Permissionless extension system, publishing, installing |
| [Relay Setup](docs/relay-setup.md) | Configuring the relay, providers, channels |
| [Contract Reference](docs/contracts.md) | All 11 contracts — resources, entitlements, events |
| [Mainnet Checklist](docs/mainnet-checklist.md) | Step-by-step guide for mainnet deployment |

## Status

**v0.2.0-alpha** — Testnet-deployed and functional.

All 11 Cadence contracts deployed on Flow testnet. Pure REST API relay with ECDSA P-256 transaction signing. E2E encryption with XChaCha20-Poly1305. Cognitive memory with molecular bonding. Agent on-chain transaction capabilities. React frontend with passkey authentication. Venice AI and Ollama provider support.

**Not yet production-ready.** Needs: formal security audit, streaming support, gas optimization, multi-user support, and channel adapters (Telegram, Discord).

## Contributing

FlowClaw is designed so that most contributions don't need to go through this repo at all. Extensions are published permissionlessly on-chain — no PR required. For core contract changes, PRs are welcome.

## Inspiration

FlowClaw reimagines [OpenClaw](https://github.com/openclaw/openclaw) and [ZeroClaw](https://github.com/theonlyhennygod/zeroclaw) for the blockchain era. Where those projects run agents entirely off-chain, FlowClaw anchors the agent harness on Flow and uses Cadence's resource model for ownership and privacy guarantees that no off-chain system can provide.

## License

MIT
