# FlowClaw Deployment Guide

## Prerequisites

- Python 3.11+
- Node.js 20+ (for frontend)
- A Flow account with FLOW tokens
- An LLM API key (Venice AI, Anthropic, OpenAI, or Ollama)

## Local Development

### 1. Clone and install

```bash
git clone https://github.com/doodlifts/flowclaw.git
cd flowclaw
pip3 install -r relay/requirements.txt
```

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env with your values:
#   FLOW_NETWORK=testnet
#   FLOW_ACCOUNT_ADDRESS=0xYourAddress
#   FLOW_PRIVATE_KEY=YourPrivateKeyHex
#   VENICE_API_KEY=YourVeniceKey
```

### 3. Start the relay

```bash
python3.11 -m uvicorn relay.api:app --host 0.0.0.0 --port 8000 --reload
```

### 4. Start the frontend

```bash
cd frontend
npm install && npm run dev
```

## Docker

```bash
# Build and run everything
docker compose up --build

# Or just the relay (no emulator)
docker build -t flowclaw .
docker run --env-file .env -p 8000:8000 flowclaw
```

## Testnet Deployment

FlowClaw contracts are deployed on Flow testnet at `0x808983d30a46aee2`.

Set your `.env`:
```
FLOW_NETWORK=testnet
FLOW_ACCESS_NODE=https://rest-testnet.onflow.org
```

## Mainnet Deployment

### 1. Create a mainnet account

Use [Flow Port](https://port.onflow.org) or the Flow CLI to create a mainnet account and fund it with FLOW.

### 2. Deploy contracts

Contracts must be deployed in order (dependencies first):

1. AgentRegistry
2. AgentSession
3. InferenceOracle
4. ToolRegistry
5. AgentMemory
6. AgentScheduler
7. AgentLifecycleHooks
8. AgentEncryption
9. AgentExtensions
10. CognitiveMemory
11. FlowClaw (depends on all above)

```bash
flow project deploy --network mainnet
```

### 3. Update configuration

Update `flow.json` mainnet aliases with deployed contract addresses.

Set `.env`:
```
FLOW_NETWORK=mainnet
FLOW_ACCESS_NODE=https://rest-mainnet.onflow.org
FLOW_ACCOUNT_ADDRESS=0xYourMainnetAddress
FLOW_PRIVATE_KEY=YourMainnetPrivateKey
```

Update `frontend/.env`:
```
VITE_FLOW_NETWORK=mainnet
VITE_RELAY_URL=https://your-relay-domain.com
```

### 4. Security checklist

- [ ] Rotate all API keys (never reuse testnet keys)
- [ ] Set `ALLOWED_ORIGINS` to your production domain only
- [ ] Set `MAX_FLOW_TRANSFER` to a conservative limit
- [ ] Set `GAS_SPONSOR_DAILY_LIMIT` appropriately
- [ ] Configure HTTPS for the relay endpoint
- [ ] Review `SECURITY.md` for the full threat model

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `FLOW_NETWORK` | Yes | testnet | Flow network (testnet/mainnet) |
| `FLOW_ACCESS_NODE` | Yes | — | REST API endpoint |
| `FLOW_ACCOUNT_ADDRESS` | Yes | — | Your Flow account address |
| `FLOW_PRIVATE_KEY` | Yes | — | Account private key (hex) |
| `VENICE_API_KEY` | No | — | Venice AI API key |
| `ANTHROPIC_API_KEY` | No | — | Anthropic API key |
| `OPENAI_API_KEY` | No | — | OpenAI API key |
| `OLLAMA_BASE_URL` | No | localhost:11434 | Ollama endpoint |
| `ALLOWED_ORIGINS` | No | localhost variants | CORS origins (comma-separated) |
| `MAX_FLOW_TRANSFER` | No | 10.0 | Max FLOW per agent transfer |
| `GAS_SPONSOR_DAILY_LIMIT` | No | 100 | Max sponsored txs per account/day |
| `RELAY_LOG_LEVEL` | No | INFO | Logging level |
