# Relay Setup

The relay is the off-chain companion that bridges your Flow account to LLM providers. It runs on your machine, handles encryption, and processes inference requests. Each relay instance serves exactly one Flow account — that's the privacy model.

## Installation

```bash
cd flowclaw/relay
pip install -r requirements.txt
```

**Dependencies:**
- `python-dotenv` — Environment variable loading
- `anthropic` — Anthropic Claude SDK (optional)
- `openai` — OpenAI SDK (optional)
- `requests` — HTTP client for Ollama and Flow Access Node
- `pynacl` — XChaCha20-Poly1305 encryption (recommended)
- `cryptography` — Fallback encryption library

You only need the SDK for the provider you're using. If you use Ollama (local models), you don't need any API keys at all.

## Configuration

Create a `.env` file in the relay directory:

```env
# Flow network
FLOW_NETWORK=emulator                          # emulator, testnet, or mainnet
FLOW_ACCESS_NODE=http://localhost:8888         # Flow Access Node URL
FLOW_ACCOUNT_ADDRESS=0xf8d6e0586b0a20c7       # Your Flow account address
FLOW_PRIVATE_KEY=                              # Your Flow account private key

# LLM Providers (configure at least one)
ANTHROPIC_API_KEY=sk-ant-...                   # Anthropic Claude
OPENAI_API_KEY=sk-...                          # OpenAI GPT
OLLAMA_BASE_URL=http://localhost:11434         # Ollama (local models)

# Relay settings
RELAY_POLL_INTERVAL=2                          # Seconds between event polls
RELAY_MAX_RETRIES=3                            # Max retries for failed operations
RELAY_LOG_LEVEL=INFO                           # DEBUG, INFO, WARNING, ERROR

# Paths
FLOWCLAW_PROJECT_DIR=/path/to/flowclaw        # Project root (auto-detected)
FLOWCLAW_ENCRYPTION_KEY=~/.flowclaw/encryption.key  # Encryption key file
```

## Running Modes

### Interactive Mode (Testing)

The fastest way to test FlowClaw without a running emulator:

```bash
python flowclaw_relay.py --interactive
```

This simulates the full on-chain flow locally — including encryption round-trips — and gives you a chat interface. It auto-selects the first available provider.

```
============================================================
FlowClaw Interactive Mode
Account: (local)
Providers: ['anthropic', 'ollama']
Encryption: ENABLED
Key: 9f2e1d3a4b5c6d7e...
Type 'quit' to exit, 'new' for new session
============================================================
Using: anthropic/claude-sonnet-4-5-20250929

Session #1 created

You: What is the Flow blockchain?
Agent: Flow is a layer-1 blockchain designed for...
```

### Relay Mode (Production)

Listens for on-chain `InferenceRequested` events and processes them:

```bash
python flowclaw_relay.py
```

The relay polls the Flow Access Node every `RELAY_POLL_INTERVAL` seconds, filters events for your account address, decrypts session history, calls the LLM, encrypts the response, and posts it back on-chain.

```
============================================================
FlowClaw Inference Relay
Account: 0xf8d6e0586b0a20c7
Network: emulator
Providers: ['anthropic']
Encryption: ENABLED
============================================================
Starting from block height: 42
Processing inference request #1 (session=1, model=claude-sonnet-4-5-20250929)
  Turn 1/10
  Inference complete: 342 chars, 1247 tokens
  Posting encrypted response on-chain (request #1)
  Encrypted response posted on-chain successfully
Completed: request #1 (1247 tokens, 1 turns, encrypted=True)
```

### Single Cycle Mode

Process one polling cycle and exit (useful for cron or testing):

```bash
python flowclaw_relay.py --once
```

### Status Check

See current relay configuration:

```bash
python flowclaw_relay.py --status
```

```
FlowClaw Relay Status
  Network:    emulator
  Account:    0xf8d6e0586b0a20c7
  Access Node: http://localhost:8888
  Encryption: ENABLED
  Key:        9f2e1d3a4b5c6d7e...
  Key file:   /home/user/.flowclaw/encryption.key
  Providers:  anthropic, ollama
```

## Encryption Setup

Run once before first use:

```bash
python flowclaw_relay.py --setup-encryption
```

This generates a 256-bit XChaCha20-Poly1305 key, saves it to `~/.flowclaw/encryption.key`, and prints the fingerprint. Then register the fingerprint on-chain:

```bash
flow transactions send transactions/configure_encryption.cdc \
  --arg "String:<fingerprint>" \
  --arg "UInt8:0" \
  --arg "String:primary-key"
```

See [Encryption](encryption.md) for the full details on key management, rotation, and the threat model.

## LLM Providers

### Anthropic Claude

```env
ANTHROPIC_API_KEY=sk-ant-api03-...
```

Default model: `claude-sonnet-4-5-20250929`. Supports tool use natively.

### OpenAI GPT

```env
OPENAI_API_KEY=sk-...
```

Default model: `gpt-4o`. Supports function calling natively.

### Ollama (Local Models)

```env
OLLAMA_BASE_URL=http://localhost:11434
```

Default model: `llama3`. No API key needed — runs entirely on your hardware. This is the most private option: your messages never leave your machine (not even to an API provider).

```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Pull a model
ollama pull llama3

# Start Ollama server (if not running as a service)
ollama serve
```

### Provider Selection

The relay uses whatever provider is configured in your agent's on-chain `InferenceConfig`. When you initialized your account, you specified a provider and model. The relay reads those from the `InferenceRequested` event and routes to the right provider.

To change providers, update your on-chain config:

```bash
flow transactions send transactions/update_config.cdc \
  --arg "String:openai" \
  --arg "String:gpt-4o" \
  ...
```

## Channel Adapters

The relay is designed to work with multiple frontends. The current PoC supports:

**CLI (built-in)** — The `--interactive` mode provides a terminal chat interface. No additional setup needed.

**React Web UI** — The `flowclaw-ui.jsx` file provides a tabbed web interface. Connect it to the relay via WebSocket or REST API (implementation pending).

**Telegram** — Planned. The relay would run a Telegram bot that forwards messages to the on-chain flow and sends responses back. The bot's token would be stored in the agent's config (hashed).

**Custom** — The relay's `InferenceRelay` class can be imported and extended. Subclass it to add any channel you want.

## Deployment Options

### Local Development

```bash
flow emulator start
flow project deploy --network emulator
python relay/flowclaw_relay.py --interactive
```

### Flow Testnet

```bash
# Create a testnet account
flow accounts create --network testnet

# Deploy contracts
flow project deploy --network testnet

# Update .env
FLOW_NETWORK=testnet
FLOW_ACCESS_NODE=https://rest-testnet.onflow.org
FLOW_ACCOUNT_ADDRESS=0x<your-testnet-address>
```

### Production (Mainnet)

```bash
FLOW_NETWORK=mainnet
FLOW_ACCESS_NODE=https://rest-mainnet.onflow.org
```

**Important:** On mainnet, every transaction costs FLOW tokens for gas. The relay should be configured with appropriate retry limits and error handling. Consider running it as a system service (systemd, Docker, etc.) for reliability.

## Agentic Loop

The relay supports multi-turn agentic execution with up to 10 tool call rounds per inference request:

1. Call LLM with message history
2. If LLM returns tool calls → execute each tool → add results to messages → go to 1
3. If LLM returns a text response → encrypt and post on-chain

Tool execution is sandboxed. The `ToolExecutor` denies dangerous shell commands and logs all executions. Available tools: `memory_store`, `memory_recall`, `web_fetch`, `shell_exec`, `flow_query`, `flow_transact` (requires approval).

## Troubleshooting

**"Flow CLI not found"** — Install from https://developers.flow.com/tools/flow-cli

**"No encryption key configured"** — Run `python flowclaw_relay.py --setup-encryption`

**"Provider not configured"** — Set the appropriate API key in `.env`

**"Script/transaction failed"** — Check that contracts are deployed and account is initialized. Run `flow project deploy --network emulator` and `flow transactions send transactions/initialize_account.cdc`.

**"Relay not authorized"** — Your relay address must be authorized in the `OracleConfig`. For the PoC, `initialize_account.cdc` auto-authorizes the owner as their own relay.

---

[← Extensions](extensions.md) | [Contract Reference →](contracts.md)
