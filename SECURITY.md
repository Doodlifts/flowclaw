# FlowClaw Security Model

## Architecture Overview

FlowClaw uses a hybrid on-chain/off-chain architecture where sensitive operations happen locally and only encrypted data touches the blockchain.

## What's On-Chain (Public)

- Agent configuration (name, model, system prompt hash)
- Encrypted session messages (XChaCha20-Poly1305 ciphertext)
- Encrypted memory entries
- Extension metadata and marketplace listings
- Transaction hashes and event logs

**Block explorers see ciphertext at every step.** The plaintext exists only in your relay's memory during inference.

## What's Off-Chain (Private)

- Encryption keys (never leave your machine)
- LLM API keys
- Plaintext conversations (decrypted only in relay memory)
- Flow account private keys

## Encryption

- Algorithm: XChaCha20-Poly1305 (via libsodium/PyNaCl)
- Key storage: Local filesystem (`~/.flowclaw/encryption.key`)
- On-chain: Only the key fingerprint is stored (for key rotation tracking)
- The encryption key is generated on first relay startup and never transmitted

## Key Management

### Flow Account Keys

Your Flow private key signs all on-chain transactions. Protect it:

- Never commit `.env` files or `.pkey` files to version control
- Use environment variables or a secrets manager in production
- Rotate keys if compromised (Flow supports multiple keys per account)
- Consider using a hardware security module (HSM) for mainnet

### LLM API Keys

- Stored in `.env`, never transmitted on-chain
- The relay sends plaintext to your chosen LLM provider over HTTPS
- Choose providers based on your privacy requirements

## Safety Limits

| Limit | Default | Config |
|-------|---------|--------|
| Max FLOW per agent transfer | 10.0 | `MAX_FLOW_TRANSFER` |
| Gas sponsor daily limit | 100 tx/account | `GAS_SPONSOR_DAILY_LIMIT` |
| Agent actions per hour | 100 | `SecurityContext.max_actions_per_hour` |
| Financial tools | Require autonomy level >= 1 | Agent security policy |

## CORS Policy

The relay restricts cross-origin requests via the `ALLOWED_ORIGINS` environment variable. In production, set this to your frontend domain only.

## Relay Trust Model

The relay is a trusted component — it holds your encryption key and Flow private key. Anyone with access to your relay can:

- Read your decrypted conversations
- Sign transactions on your behalf
- Access your LLM provider

**Run the relay on infrastructure you control.** Do not use shared or public relay instances for sensitive conversations.

## Reporting Vulnerabilities

If you find a security issue, please report it responsibly by opening a GitHub issue or contacting the maintainers directly.
