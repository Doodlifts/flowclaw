# FlowClaw

**The first agentic AI harness that couldn't exist on any other blockchain.**

FlowClaw puts your AI agent on-chain — not as a gimmick, but because Flow's account model solves problems that every other agent platform works around. Your agent is a Cadence Resource that lives in your account. Your conversations are end-to-end encrypted before they touch the chain. Your memory, sessions, scheduled tasks, and extensions are all owned by you — not by a platform, not by a DAO, not by whoever runs the server. And you never had to install a wallet or buy tokens to get here.

This isn't "AI + blockchain" for the sake of it. FlowClaw exists because Flow is the only chain where the entire agent ownership stack — account creation, key management, gas sponsorship, multi-party signing, scheduled execution, and resource-oriented storage — works natively without hacks or workarounds.

## Why Flow Makes This Possible

Most blockchains treat accounts as a thin wrapper around a keypair. Flow treats accounts as first-class programmable containers with their own storage, keys, and capabilities. That distinction is what makes FlowClaw work.

**Resource-oriented ownership.** In Cadence, a Resource can only exist in one place at a time. When your agent is a Resource stored in your account, no smart contract bug can duplicate it, no admin key can move it, and no platform can revoke it. This is a language-level guarantee — not a convention, not a governance promise. Ethereum's ERC-721 tokens approximate this with a mapping, but the "ownership" is just an entry in someone else's contract storage. On Flow, the agent literally lives in your account's storage. If the FlowClaw contracts disappeared tomorrow, your Resources would still be there.

**Native multi-party signing.** Flow transactions have three distinct roles — proposer, authorizer, and payer — built into the protocol. FlowClaw uses this so you authorize actions on your account while a gas sponsor pays the fees. On Ethereum, this requires ERC-4337 account abstraction with bundlers, paymasters, and entry point contracts. On Solana, you'd need a program to proxy-sign. On Flow, it's a first-class transaction feature that works with any contract. Every FlowClaw transaction uses this: you sign the payload (proposer + authorizer), the sponsor signs the envelope (payer). No proxy contracts. No relayers pretending to be you.

**Gasless onboarding with passkeys.** Flow accounts support P-256 keys natively — the same curve used by WebAuthn passkeys and Apple/Google's biometric authentication. FlowClaw creates your Flow account using your passkey's public key, then generates a SubtleCrypto P-256 signing key in your browser for transactions. No MetaMask. No seed phrases. No browser extension. You authenticate with Face ID or Touch ID and you have a fully functional blockchain account with its own storage, keys, and on-chain Resources. Try doing that on a secp256k1 chain.

**Validator-executed scheduled transactions.** Most blockchains require off-chain keepers (Chainlink Automation, Gelato) or centralized cron services to execute recurring tasks. Flow's AgentScheduler stores your task parameters on-chain and validators can trigger execution at the specified intervals. The schedule is a Resource in your account — you own it, you control it, you can cancel it. No third-party keeper network. No "sorry, our cron server was down."

**Account-level storage with cheap capacity.** Flow accounts have dedicated storage proportional to their FLOW balance. FlowClaw stores encrypted messages, memories, agent config, tool definitions, lifecycle hooks, and extension metadata directly in account storage. This is far cheaper than Ethereum's global state storage and far more natural than Solana's rent-based account model. A single Flow account can hold an agent's entire history — hundreds of sessions, thousands of encrypted messages — without running into storage rent concerns.

**Cadence's capability-based security.** Extensions in FlowClaw declare what entitlements they need — read memory, register hooks, execute tools — and the language enforces these boundaries. An extension that requests `ManageTools` literally cannot access your memory vault. This isn't a permissions check in a contract — it's a type system constraint that the Cadence runtime enforces. Publish your extension permissionlessly, and users can review exactly what capabilities it requests before installing.

## What This Means in Practice

On Ethereum, building FlowClaw would require: ERC-4337 for account abstraction + a bundler network + a paymaster contract + ERC-721 for agent "ownership" (still just a mapping) + Chainlink Automation for scheduling + a separate encryption layer + ENS or similar for human-readable identity + significant gas costs for storage. You'd need 6+ third-party dependencies before writing a single line of agent logic.

On Solana, you'd need: a custom program for agent accounts + a fee payer proxy + a keeper network for scheduling + a PDA scheme for storage + rent-exempt balance management + no resource-oriented safety guarantees.

On Flow, all of this is native: multi-party signing for gas sponsorship, P-256 keys for passkey auth, Resources for agent ownership, account storage for cheap on-chain state, and scheduled transactions for recurring tasks. FlowClaw's 11 contracts are the entire stack. No external dependencies. No keeper networks. No bundlers.

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

| Problem with traditional agents | FlowClaw's solution | Why it requires Flow |
|---|---|---|
| Maintainers control what gets merged | Permissionless extension system — publish without approval | Cadence entitlements enforce capability boundaries at the language level |
| Cron jobs are unreliable | Validator-executed scheduled transactions | Native to Flow — no Chainlink keepers or off-chain cron |
| No proof your agent said what it said | Every message is hashed and stored on-chain | Cheap account storage makes full history viable |
| Platform can read your conversations | E2E encryption — chain only sees ciphertext | Account storage keeps encrypted data in your control |
| Agent config lives on someone else's server | Config is a Cadence Resource in YOUR account | Resources can only exist in one place — language-level ownership |
| Platform locks you into their LLM provider | BYOK — bring your own key for any provider | Not chain-specific, but enabled by the self-sovereign architecture |
| Agent actions run on a centralized server | Multi-party signing — your account authorizes, sponsor just pays gas | Native transaction roles (proposer/authorizer/payer) — no ERC-4337 |
| Users need a wallet and tokens to start | Passkey onboarding — Face ID, no wallet, no tokens | P-256 native key support + multi-party signing for gas sponsorship |

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

Per-account sequence number tracking with optimistic nonce management ensures rapid successive transactions (e.g., creating a session then immediately sending a message) don't conflict.

## Bring Your Own Key (BYOK)

FlowClaw doesn't lock you into a single LLM provider. From Settings, you can configure:

- **Venice AI** — privacy-focused, OpenAI-compatible
- **OpenAI** — GPT-4o, GPT-4o-mini, o1
- **Anthropic** — Claude Sonnet, Claude Haiku
- **Ollama** — fully local inference (your messages never leave your machine)
- **Any OpenAI-compatible API** — OpenRouter, Together, Groq, etc.

Your API keys are stored per-account in the relay and never touch the blockchain. The relay supports concurrent users with isolated provider resolution — each user's BYOK configuration is independent.

## Agent Capabilities

Your agent can do more than chat. It has on-chain tools:

- **Check balances** — query any Flow account's FLOW balance
- **Send tokens** — transfer FLOW to any address (with configurable safety limits)
- **Execute transactions** — run custom Cadence transactions on-chain
- **Web fetch** — pull data from external APIs and websites
- **Spawn sub-agents** — create child agents for parallel tasks, with provider inheritance from the parent
- **Cognitive memory** — store and recall information with molecular bonding and dream cycles
- **Scheduled tasks** — validator-executed recurring actions stored as Resources in your account
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
- **Sequence management**: Per-account optimistic nonce tracking with automatic retry on conflicts

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

All 11 Cadence contracts deployed on Flow mainnet (`0x91d0a5b7c9832a8b`). Multi-party transaction signing with user as authorizer and gas sponsor as payer. E2E encryption enforced for all on-chain content (XChaCha20-Poly1305). Passkey authentication with SubtleCrypto transaction signing. BYOK support for any OpenAI-compatible, Anthropic, or Ollama provider. Cognitive memory with molecular bonding and dream cycles. Sub-agent spawning with provider inheritance. Per-account sequence number tracking for rapid transaction submission. Multi-user concurrent safety across all relay endpoints. React frontend with real-time chat.

## Contributing

FlowClaw is designed so that most contributions don't need to go through this repo at all. Extensions are published permissionlessly on-chain — no PR required. For core contract changes, PRs are welcome. See [BUILDING.md](BUILDING.md) for the full composability guide.

## Inspiration

FlowClaw reimagines [OpenClaw](https://github.com/openclaw/openclaw) and [ZeroClaw](https://github.com/theonlyhennygod/zeroclaw) for the blockchain era. Where those projects run agents entirely off-chain, FlowClaw anchors the agent harness on Flow and uses Cadence's resource model for ownership and privacy guarantees that no off-chain system can provide.

## License

MIT
