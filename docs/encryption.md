# Encryption

FlowClaw uses end-to-end encryption so that the Flow blockchain never sees the plaintext of your conversations. Every message — both what you send and what the LLM responds — is encrypted before it enters a transaction.

## The Problem

Flow's storage model provides structural privacy: your `/storage/` path is private and other accounts can't read it. But transactions have a gap. Transaction arguments are publicly visible in Flow's transaction data. If you submit a transaction with `content: "What is my bank balance?"`, anyone with a block explorer can read that.

Events have the same issue — they're publicly emitted. FlowClaw already only emits content hashes in events (never plaintext), but the transaction arguments were the remaining hole.

## The Solution

Encrypt everything before it touches a transaction. The relay handles all encryption and decryption locally. The chain only ever stores ciphertext.

### What a block explorer sees

**Before encryption (the old way):**
```
Transaction: send_message
  sessionId: 1
  content: "What is the Flow blockchain?"        ← EXPOSED
  contentHash: "a3b8c1d2..."
```

**After encryption (the current way):**
```
Transaction: send_message
  sessionId: 1
  ciphertext: "x7Fk9mQ2a8vB3nR..."              ← Meaningless without key
  nonce: "Yz4kL8mN..."
  plaintextHash: "a3b8c1d2..."
  keyFingerprint: "9f2e1d..."
  algorithm: 0
  plaintextLength: 29
```

The same applies to LLM responses coming back via `complete_inference_owner` and memory stored via `store_memory`.

### What remains public

Some data is intentionally left unencrypted because it's structural, not sensitive:

| Data | Public? | Why |
|---|---|---|
| Session IDs | Yes | Needed for routing |
| Request IDs | Yes | Needed for dedup |
| Token counts | Yes | Cost tracking |
| Timestamps | Yes | Inherent to blocks |
| Provider/model | Yes | In InferenceRequested event |
| Content hashes | Yes | For verification |
| Memory tags | Optional | Plaintext enables on-chain search; encrypt if sensitive |
| Agent name/description | Optional | Public info struct is opt-in |
| Message content | **No** | Always ciphertext |
| LLM responses | **No** | Always ciphertext |
| Memory content | **No** | Always ciphertext |

## Encryption Scheme

FlowClaw uses **XChaCha20-Poly1305** — the same authenticated encryption scheme used by ZeroClaw (the Rust rewrite of OpenClaw). It provides both confidentiality (can't read without the key) and integrity (can't tamper without detection).

**Key details:**
- 256-bit symmetric key (32 bytes)
- 24-byte nonce (XChaCha20 extended nonce — safe to generate randomly without collision risk)
- Poly1305 MAC for authentication
- SHA-256 of the plaintext stored alongside for integrity verification after decryption

**Library priority:** PyNaCl (libsodium bindings) → `cryptography` library (a proper crypto library is required — no insecure fallbacks)

## Key Management

### Where the key lives

The encryption key is stored locally at `~/.flowclaw/encryption.key` with `0600` permissions (owner read/write only). It's a 32-byte key encoded in base64. The file never leaves your machine.

### What's stored on-chain

Only the key's fingerprint (SHA-256 of the key bytes) is stored on-chain in the `EncryptionConfig` resource. This lets the contract verify that a message was encrypted with a known key without ever seeing the key itself.

### Key rotation

You can rotate keys by generating a new one and registering its fingerprint on-chain:

```bash
# Generate new key (saves to ~/.flowclaw/encryption.key)
python relay/flowclaw_relay.py --setup-encryption

# Register new fingerprint on-chain
flow transactions send transactions/configure_encryption.cdc \
  --arg "String:<new-fingerprint>" \
  --arg "UInt8:0" \
  --arg "String:rotated-key-2025-02"
```

The `EncryptionConfig` contract keeps a history of all registered key fingerprints. This means the relay can still decrypt old messages that were encrypted with a previous key — as long as you keep the old key file. In practice, you'd maintain a key archive at `~/.flowclaw/keys/` for historical decryption.

### Key backup

If you lose your encryption key, your on-chain messages become permanently unreadable. There is no recovery mechanism by design — this is the tradeoff for true privacy. Back up `~/.flowclaw/encryption.key` securely.

## Encrypted Flow Step by Step

### Sending a message (Multi-Party Signing)

FlowClaw uses multi-party signing where the user is the authorizer and the sponsor pays gas. Encryption happens at the relay before the user signs the transaction:

1. You type "What is FLOW?" in the web UI
2. Your browser calls `POST /encrypt` on the relay — the relay encrypts with XChaCha20-Poly1305 and returns the encrypted payload
3. Your browser calls `POST /transaction/build` with the **ciphertext** as the transaction argument
4. The relay builds a `send_message.cdc` transaction with you as proposer + authorizer and the sponsor as payer
5. Your browser signs the transaction payload with your SubtleCrypto P-256 key
6. Your browser calls `POST /transaction/submit` — the relay adds the sponsor's envelope signature and submits to Flow
7. On-chain: `AgentSession` stores the ciphertext on **your account**, `InferenceRequested` event fires with contentHash

The plaintext never enters a transaction argument. The relay encrypts, the user signs, the sponsor pays.

### Receiving a response

1. The relay calls your configured LLM provider (BYOK) with the plaintext
2. The LLM responds — the relay displays it immediately in the UI
3. On-chain response posting uses the same encrypt → build → sign → submit flow

### Storing memory

1. Agent decides to remember something
2. Relay encrypts the memory content
3. Relay submits `store_memory.cdc` with encrypted content
4. On-chain: `AgentMemory` stores ciphertext under the given key
5. Tags remain plaintext for on-chain indexing (encrypt tag values if sensitive)

## Verification

The `plaintextHash` field enables two types of verification:

**Integrity check:** After decryption, the relay computes SHA-256 of the decrypted plaintext and compares it to the stored `plaintextHash`. If they don't match, the content was corrupted or tampered with.

**Provenance check:** If you ever need to prove what was said in a conversation, you can decrypt the message and show that its SHA-256 matches the on-chain hash. The hash was committed to the blockchain at the time of the message — it can't be altered retroactively.

## Setup

```bash
# One-time setup
python relay/flowclaw_relay.py --setup-encryption

# This will:
# 1. Generate a random 256-bit key
# 2. Save it to ~/.flowclaw/encryption.key (mode 0600)
# 3. Print the fingerprint for on-chain registration
# 4. Run a round-trip verification test

# Then register on-chain:
flow transactions send transactions/configure_encryption.cdc \
  --arg "String:<fingerprint>" \
  --arg "UInt8:0" \
  --arg "String:primary-key"
```

The relay automatically detects the key at startup and logs whether encryption is enabled:

```
2025-02-17 10:00:00 [INFO] Encryption key loaded (fingerprint: 9f2e1d3a...)
2025-02-17 10:00:00 [INFO] Encryption: ENABLED
```

If no key is found, the relay auto-generates one at startup and registers its fingerprint on-chain. Encryption is always required for on-chain content — the relay refuses to store unencrypted data on-chain.

## Threat Model

**What encryption protects against:** Anyone reading your messages on a block explorer, validator nodes inspecting transaction payloads, other Flow accounts trying to read your conversations, network observers monitoring transaction content.

**What encryption does NOT protect against:** Someone with physical access to your machine (they could read `~/.flowclaw/encryption.key`), a compromised relay process (it holds plaintext in memory during inference), the LLM provider seeing your messages (they receive plaintext for inference — use Ollama for fully local inference if this is a concern).

**Side channel considerations:** Message length is partially leaked via `plaintextLength` and ciphertext size. Timing of messages is visible via block timestamps. The provider and model are visible in the `InferenceRequested` event. Token counts are visible. None of these reveal the actual content, but they reveal that a conversation happened and roughly how long each message was.

---

[← Architecture](architecture.md) | [Extensions →](extensions.md)
