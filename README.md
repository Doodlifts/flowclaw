# FlowClaw

**An agentic AI harness on the Flow blockchain — private inference, verifiable history, permissionless extensions, and composable on-chain primitives.**

FlowClaw reimagines [OpenClaw](https://github.com/openclaw/openclaw) as a blockchain-native system. Every agent is a Cadence Resource owned by a Flow account. Your conversations are end-to-end encrypted. Your config, memory, and session history live in your account's private storage. Nobody — not even FlowClaw's creators — can read your messages or control your agent.

## Get Started

Visit [flowclaw.app](https://flowclaw.app) to start chatting with your own on-chain agent. No wallet needed — FlowClaw creates a Flow account for you using passkey authentication (Face ID, Touch ID, or security key). Your agent is ready in seconds.

What happens when you sign up:

1. You authenticate with a passkey (biometric or security key)
2. FlowClaw creates a Flow account with your passkey's P-256 public key
3. A separate SubtleCrypto signing key is generated in your browser for transaction signing
4. On-chain resources (agent, sessions, memory, encryption, tools) are initialized on your account via multi-party signing
5. Gas fees are sponsored — you don't need FLOW tokens to get started
6. Every conversation is E2E encrypted before touching the chain

```
┌──────────────────────────────────────────────────────────────┐
│  Your Flow Account (Authorizer)                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐  │
│  │  Agent   │  │ Sessions │  │  Memory  │  │   Tools     │  │
│  │Collection│  │ Manager  │  │  Vault   │  │ Collection  │  │
│  └──────────┘  └──────────┘  └──────────┘  └─────────────┘  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐  │
│  │ Oracle   │  │Scheduler │  │Lifecycle │  │  Extension  │  │
│  │ Config   │  │ Resource │  │  Hooks   │  │  Manager    │  │
│  └──────────┘  └──────────┘  └──────────┘  └─────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  Encryption Config (key fingerprint — key never on-chain)│ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────┬─────────────────────────────────────────┘
                     │  Multi-Party Signed Txs
                     │  (You = authorizer, Sponsor = payer)
┌────────────────────┴─────────────────────────────────────────┐
│  Relay (hosted or self-hosted)                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────────────┐   │
│  │Encryption│  │  BYOK    │  │    Tool Executor          │   │
│  │ Manager  │  │ Provider │  │ (memory, web, chain, DeFi)│   │
│  └──────────┘  │ Router   │  └──────────────────────────┘   │
│                └──────────┘                                   │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  Gas Sponsor — pays transaction fees for users            │ │
│  └──────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

## Why FlowClaw?

| Problem with traditional agents | FlowClaw's solution |
|---|---|
| Maintainers control what gets merged | Permissionless extension system — publish without approval |
| Cron jobs are unreliable | Flow's validator-executed scheduled transactions |
| No proof your agent said what it said | Every message is hashed and stored on-chain |
| Platform can read your conversations | E2E encryption — chain only sees ciphertext |
| Agent config lives on someone else's server | Config is a Cadence Resource in YOUR account |
| Platform locks you into their LLM provider | BYOK — bring your own key for any OpenAI-compatible, Anthropic, or local Ollama provider |
| Agent actions run on a centralized server | Multi-party signing — your account authorizes, sponsor just pays gas |

## How It Works

When you send a message, here's the full encrypted flow:

1. You type a message in the web UI
2. Your browser calls `POST /encrypt` — the relay encrypts it with XChaCha20-Poly1305
3. Your browser calls `POST /transaction/build` with the **ciphertext** as transaction arguments
4. Your browser signs the transaction payload with your SubtleCrypto P-256 key (you are the authorizer)
5. Your browser calls `POST /transaction/submit` — the relay adds the sponsor's envelope signature (payer) and submits to Flow
6. On-chain: the encrypted message is stored in your session on **your account**
7. Meanwhile, the relay calls your LLM provider (BYOK) with the **plaintext**
8. The LLM responds — displayed immediately in the UI

Block explorers see ciphertext at every step. The plaintext exists only in the relay's memory during inference. Your account authorizes the transaction; the sponsor only pays gas.

## Multi-Party Transaction Signing

FlowClaw uses Flow's native multi-party signing so that on-chain operations happen on the user's account, not the sponsor's:

**User** = Proposer + Authorizer (signs the payload — "I authorize this action on my account")

**Sponsor** = Payer only (signs the envelope — "I'll pay the gas fee for this transaction")

This means your on-chain agent, sessions, memories, and encryption config all live in YOUR Flow account. The sponsor never touches your data — they just cover the gas.

The signing flow:

1. Frontend requests an unsigned transaction from the relay (`POST /transaction/build`)
2. Relay builds the RLP-encoded payload with the user as proposer + authorizer and sponsor as payer
3. Frontend signs the payload locally with the user's SubtleCrypto P-256 key
4. Frontend sends the signature to the relay (`POST /transaction/submit`)
5. Relay adds the sponsor's envelope signature and submits to Flow's REST API
6. Flow verifies both signatures and executes the transaction

## Bring Your Own Key (BYOK)

FlowClaw doesn't lock you into a single LLM provider. From Settings, you can configure:

- **Venice AI** — privacy-focused, OpenAI-compatible
- **OpenAI** — GPT-4o, GPT-4o-mini, o1
- **Anthropic** — Claude Sonnet, Claude Haiku
- **Ollama** — fully local inference (your messages never leave your machine)
- **Any OpenAI-compatible API** — OpenRouter, Together, Groq, etc.

Your API keys are stored per-account and never touch the blockchain.

## Agent Capabilities

Your agent can do more than chat. It has on-chain tools:

- **Check balances** — query any Flow account's FLOW balance
- **Send tokens** — transfer FLOW to any address (with configurable safety limits)
- **Execute transactions** — run custom Cadence transactions on-chain
- **Web fetch** — pull data from external APIs and websites
- **Spawn sub-agents** — create child agents for parallel tasks
- **Cognitive memory** — store and recall information with molecular bonding and dream cycles
- **DeFi integrations** — via permissionless extensions

All agent actions are rate-limited and subject to your security policy.

## Contracts

FlowClaw deploys 11 Cadence contracts on Flow mainnet (`0x91d0a5b7c9832a8b`) and testnet (`0x808983d30a46aee2`):

| Contract | Purpose |
|---|---|
| `AgentRegistry` | Agent creation, ownership, config, multi-agent collections, rate limiting |
| `AgentSession` | Multi-turn conversations, context windowing, inference tracking |
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

## Building on FlowClaw

FlowClaw is designed for composability. The contracts, extension system, and on-chain primitives are all permissionless — you can build on top of them without asking anyone for permission.

See **[BUILDING.md](BUILDING.md)** for the full developer composability guide, including:

- How to publish extensions to the on-chain marketplace
- How to build custom tools, hooks, and channel adapters
- How to read FlowClaw state from your own contracts via Cadence scripts
- How to integrate FlowClaw agents into your own dApps
- How to run your own relay and customize the inference pipeline

---

## For Developers

### Prerequisites

- Python 3.11+ (with `pynacl` or `cryptography` for encryption)
- Node.js 20+ (for the frontend)
- An LLM API key (or Ollama for local inference)

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

The relay auto-generates an encryption key if none exists, registers its fingerprint on-chain, and syncs all on-chain state at startup.

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
- **Transaction building**: RLP-encoded payloads with multi-party signer support
- **Transaction signing**: ECDSA P-256 with SHA2-256 (user) and SHA3-256 (sponsor)
- **Transaction submission**: HTTP POST to `/v1/transactions` with base64-encoded envelope
- **Account queries**: HTTP GET to `/v1/accounts/{addr}?expand=keys`
- **Content encryption**: `POST /encrypt` for encrypting content before multi-party signed transactions

The `FlowRESTClient` (`relay/flow_client.py`) handles all of this.

#### Multi-Party Transaction Signing

Flow transactions use a specific RLP encoding structure:

- **Payload**: 9 flat fields — `[script, arguments, refBlockId, gasLimit, proposalKeyAddress, proposalKeyIndex, proposalKeySequenceNumber, payer, authorizers]`
- **Envelope**: 2 nested items — `[[payload], [payloadSignatures]]`
- **Domain tag**: `FLOW-V0.0-transaction` right-padded to 32 bytes
- **Payload signing** (user): SHA2-256 hash of `domainTag + payloadRLP`, signed with ECDSA P-256 via SubtleCrypto
- **Envelope signing** (sponsor): SHA3-256 hash of `domainTag + envelopeRLP`, signed with ECDSA P-256

#### Import Resolution

The REST API requires fully-qualified contract imports. The relay automatically resolves three import styles from `flow.json` aliases:

1. Cadence 1.0 quoted: `import "AgentSession"` → `import AgentSession from 0x91d0a5b7c9832a8b`
2. Legacy bare: `import AgentSession` → `import AgentSession from 0x91d0a5b7c9832a8b`
3. Relative path: `import AgentSession from "../contracts/AgentSession.cdc"` → resolved from aliases

### Project Structure

```
flowclaw/
├── cadence/
│   ├── contracts/               # 11 Cadence smart contracts
│   ├── transactions/            # 25 Cadence transactions
│   └── scripts/                 # Read-only Cadence scripts
├── relay/                       # Python relay server
│   ├── api.py                   # FastAPI relay (multi-party signing, BYOK, encryption)
│   ├── flow_client.py           # Flow REST API client (signing, RLP, multi-party txs)
│   ├── cognitive_memory.py      # Molecular memory engine
│   ├── account_manager.py       # Passkey account creation + HMAC session tokens
│   ├── tx_executor.py           # Agent tool execution
│   ├── gas_sponsor.py           # Gas sponsorship for users
│   ├── flowclaw_relay.py        # Core relay config, encryption, LLM providers
│   └── requirements.txt         # Pinned Python dependencies
├── frontend/                    # React + Tailwind web UI
│   └── src/
│       ├── App.jsx              # Main app with session management
│       ├── AgentCanvas.jsx      # Chat canvas
│       ├── AuthContext.jsx       # Passkey auth + SubtleCrypto key gen
│       ├── transactionSigner.js  # Multi-party transaction signing
│       ├── api.js               # Relay API client with encryption + signing
│       └── flow-config.js       # FCL network configuration
├── extensions/examples/         # Example Cadence extensions
├── docs/                        # Additional documentation
├── .github/workflows/ci.yml     # GitHub Actions CI
├── Dockerfile                   # Multi-stage production build
├── docker-compose.yml           # Full stack orchestration
├── flow.json                    # Flow project config (testnet + mainnet)
├── BUILDING.md                  # Developer composability guide
├── DEPLOYMENT.md                # Deployment guide
└── SECURITY.md                  # Security model documentation
```

## Documentation

| Document | What it covers |
|---|---|
| [Building on FlowClaw](BUILDING.md) | Composability guide — extensions, tools, hooks, integrations |
| [Deployment Guide](DEPLOYMENT.md) | Local dev, Docker, testnet, and mainnet deployment |
| [Security Model](SECURITY.md) | Encryption, key management, safety limits, trust model |
| [Architecture](docs/architecture.md) | Hybrid on-chain/off-chain design, data flow, storage model |
| [Encryption](docs/encryption.md) | E2E encryption, key management, what's public vs private |
| [Extensions](docs/extensions.md) | Permissionless extension system, publishing, installing |
| [Relay Setup](docs/relay-setup.md) | Configuring the relay, providers, channels |
| [Contract Reference](docs/contracts.md) | All 11 contracts — resources, entitlements, events |
| [Mainnet Checklist](docs/mainnet-checklist.md) | Step-by-step guide for mainnet deployment |

## Status

**v0.3.0-alpha** — Mainnet-deployed and functional.

All 11 Cadence contracts deployed on Flow mainnet (`0x91d0a5b7c9832a8b`). Multi-party transaction signing with user as authorizer and gas sponsor as payer. E2E encryption enforced for all on-chain content (XChaCha20-Poly1305). Passkey authentication with SubtleCrypto transaction signing. BYOK support for any OpenAI-compatible, Anthropic, or Ollama provider. Cognitive memory with molecular bonding and dream cycles. React frontend with real-time chat.

## Contributing

FlowClaw is designed so that most contributions don't need to go through this repo at all. Extensions are published permissionlessly on-chain — no PR required. For core contract changes, PRs are welcome. See [BUILDING.md](BUILDING.md) for the full composability guide.

## Inspiration

FlowClaw reimagines [OpenClaw](https://github.com/openclaw/openclaw) and [ZeroClaw](https://github.com/theonlyhennygod/zeroclaw) for the blockchain era. Where those projects run agents entirely off-chain, FlowClaw anchors the agent harness on Flow and uses Cadence's resource model for ownership and privacy guarantees that no off-chain system can provide.

## License

MIT
