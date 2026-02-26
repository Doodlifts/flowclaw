# Mainnet Deployment Checklist

Step-by-step guide for moving FlowClaw from emulator/testnet to Flow mainnet. This isn't a "click deploy" situation — mainnet means real FLOW tokens, real gas costs, and immutable contract deployments. Go through each section carefully.

## Prerequisites

Before starting, you need:

1. **A funded Flow mainnet account.** You need enough FLOW to cover contract deployment gas (deploying 10 contracts costs roughly 0.01–0.05 FLOW total) plus ongoing transaction fees. Start with at least 1 FLOW.

2. **Flow CLI v1.x+ installed.** Verify with `flow version`. The CLI handles key generation, account creation, contract deployment, and transaction submission.

3. **All emulator tests passing.** Run `bash tests/test_emulator.sh` and confirm 0 failures. Don't deploy broken contracts to mainnet — they're immutable once deployed.

4. **Python relay tests passing.** Run `python3 tests/test_relay.py` and confirm all 48 tests pass, especially the encryption round-trip tests.

## Phase 1: Account Setup

### Create a mainnet account

If you don't already have one:

```bash
# Generate a key pair
flow keys generate --sig-algo ECDSA_P256

# Save the private key securely (NOT in git)
# Use the public key to create an account via:
#   - Flow Port: https://port.onflow.org
#   - Or the CLI with a funded parent account
```

### Add the account to flow.json

```json
{
  "accounts": {
    "mainnet-account": {
      "address": "0xYOUR_MAINNET_ADDRESS",
      "key": {
        "type": "file",
        "location": "./mainnet-key.pkey"
      }
    }
  }
}
```

Store the private key in a `.pkey` file that is **NOT committed to git**. Add `*.pkey` to `.gitignore`.

### Add mainnet deployment config

```json
{
  "deployments": {
    "mainnet": {
      "mainnet-account": [
        "AgentRegistry",
        "AgentSession",
        "InferenceOracle",
        "ToolRegistry",
        "AgentMemory",
        "AgentScheduler",
        "AgentLifecycleHooks",
        "FlowClaw",
        "AgentExtensions",
        "AgentEncryption"
      ]
    }
  }
}
```

## Phase 2: Contract Audit

### Review contract imports

Every contract that references another FlowClaw contract uses a relative import like `import AgentRegistry from "./AgentRegistry.cdc"`. The Flow CLI resolves these during deployment. Verify that `flow.json` lists all 10 contracts and that they deploy in dependency order (the order in the deployments array matters).

**Deployment order** (dependencies must deploy first):

1. `AgentRegistry` — no dependencies
2. `AgentSession` — depends on AgentRegistry
3. `InferenceOracle` — depends on AgentSession
4. `ToolRegistry` — no dependencies
5. `AgentMemory` — no dependencies
6. `AgentScheduler` — no dependencies
7. `AgentLifecycleHooks` — no dependencies
8. `AgentExtensions` — no dependencies
9. `AgentEncryption` — no dependencies
10. `FlowClaw` — depends on all of the above

### Check for hardcoded addresses

Search all `.cdc` files for hardcoded emulator addresses (`0xf8d6e0586b0a20c7`). These should be replaced with the `flow.json` import resolution pattern. If any transactions or scripts reference specific addresses, update them.

```bash
grep -r "0xf8d6e0586b0a20c7" contracts/ transactions/ scripts/
```

### Review entitlements and access control

Verify that no contract exposes unintended `access(all)` on sensitive functions. The security model relies on entitlement-scoped access. Key things to check:

- `Agent` resource: config modification requires `Configure` entitlement
- `SessionManager`: message addition requires `AddMessage` entitlement
- `EncryptionConfig`: key management requires `ManageKeys` entitlement
- `OracleConfig`: relay authorization requires `Authorize` entitlement
- `Scheduler`: task management requires `Schedule` entitlement

## Phase 3: Testnet Dry Run

Deploy to testnet first. This is your dress rehearsal.

```bash
# Create testnet account (if needed)
flow accounts create --network testnet

# Deploy all contracts
flow project deploy --network testnet

# Initialize your account
flow transactions send transactions/initialize_account.cdc --network testnet

# Set up encryption
python3 relay/flowclaw_relay.py --setup-encryption
flow transactions send transactions/configure_encryption.cdc \
  --arg "String:<fingerprint>" \
  --arg "UInt8:0" \
  --arg "String:primary-key" \
  --network testnet

# Create a session
flow transactions send transactions/create_session.cdc \
  --arg "UInt64:50" \
  --network testnet

# Send an encrypted message
# (Use the relay's interactive mode to test the full loop)
python3 relay/flowclaw_relay.py --interactive
```

### Testnet verification checklist

- [ ] All 10 contracts deployed successfully
- [ ] Account initialized with all 10 resources
- [ ] Encryption key registered on-chain
- [ ] Session created
- [ ] Encrypted message sent and stored as ciphertext
- [ ] Relay picks up InferenceRequested event
- [ ] LLM inference completes
- [ ] Encrypted response posted back on-chain
- [ ] Decrypted response matches expected output
- [ ] No plaintext visible in block explorer transactions
- [ ] Memory store/recall works with encryption
- [ ] Scheduled task creates and fires
- [ ] Extension publish and install works

## Phase 4: Mainnet Deployment

### Deploy contracts

```bash
flow project deploy --network mainnet
```

Watch the output carefully. Each contract should show "deployed" status. If any fail, the remaining contracts that depend on them will also fail.

### Initialize your account

```bash
flow transactions send transactions/initialize_account.cdc --network mainnet
```

### Set up encryption

```bash
# Generate a PRODUCTION encryption key (separate from testnet)
python3 relay/flowclaw_relay.py --setup-encryption

# Register on-chain
flow transactions send transactions/configure_encryption.cdc \
  --arg "String:<fingerprint>" \
  --arg "UInt8:0" \
  --arg "String:mainnet-primary" \
  --network mainnet
```

**Critical: Back up your encryption key.** If you lose `~/.flowclaw/encryption.key`, you lose access to all encrypted messages on-chain. There is no recovery mechanism. Store a backup in a secure location (encrypted USB, password manager, etc.).

### Configure the relay

Update `.env`:

```env
FLOW_NETWORK=mainnet
FLOW_ACCESS_NODE=https://rest-mainnet.onflow.org
FLOW_ACCOUNT_ADDRESS=0xYOUR_MAINNET_ADDRESS
FLOW_PRIVATE_KEY=<your-mainnet-private-key>
```

### Start the relay

```bash
python3 relay/flowclaw_relay.py --status  # Verify config
python3 relay/flowclaw_relay.py           # Start relay
```

## Phase 5: Post-Deployment Verification

### Verify on Flowscan

Go to [flowscan.io](https://flowscan.io) and check:

- [ ] Your account shows the deployed contracts
- [ ] Transaction arguments show ciphertext (not plaintext)
- [ ] Events emit content hashes (not content)

### Send a test message

```bash
# Create a session
flow transactions send transactions/create_session.cdc \
  --arg "UInt64:50" \
  --network mainnet

# Use the relay to send a test message
python3 relay/flowclaw_relay.py --interactive
```

Verify:
- [ ] Message encrypted before transaction submission
- [ ] Block explorer shows ciphertext in transaction data
- [ ] Response arrives and decrypts correctly
- [ ] Token count and gas cost are reasonable

## Ongoing Operations

### Cost monitoring

Every message is 2 transactions (send + complete). At current mainnet gas prices, each transaction costs approximately 0.00001 FLOW. For heavy usage (100+ messages/day), monitor your account balance.

```bash
flow accounts get 0xYOUR_ADDRESS --network mainnet
```

### Key rotation

If you suspect your encryption key has been compromised:

```bash
# Generate new key
python3 relay/flowclaw_relay.py --setup-encryption

# Register new key on-chain (old key remains in rotation history)
flow transactions send transactions/configure_encryption.cdc \
  --arg "String:<new-fingerprint>" \
  --arg "UInt8:0" \
  --arg "String:rotated-key" \
  --network mainnet
```

Old messages remain decryptable with the old key (the relay stores key history). New messages use the new key.

### Relay reliability

For production use, run the relay as a system service:

```bash
# systemd example
sudo tee /etc/systemd/system/flowclaw-relay.service > /dev/null << 'EOF'
[Unit]
Description=FlowClaw Inference Relay
After=network.target

[Service]
Type=simple
User=flowclaw
WorkingDirectory=/home/flowclaw/flowclaw/relay
ExecStart=/usr/bin/python3 flowclaw_relay.py
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable flowclaw-relay
sudo systemctl start flowclaw-relay
```

### Contract upgrades

Cadence contracts on mainnet can be updated under certain conditions (you can add new fields and functions, but cannot remove existing ones or change their types). Plan upgrades carefully. Test on emulator and testnet first.

```bash
# Update a contract
flow project deploy --network mainnet --update
```

## Security Reminders

- **Never commit private keys or encryption keys to git.** Use `.gitignore` and `.env` files.
- **Never share your encryption key.** It's the only thing protecting your message content.
- **Monitor your account for unauthorized relay addresses.** Check `OracleConfig` periodically.
- **Keep your relay machine secure.** The relay holds your private key and encryption key in memory during operation.
- **Use separate keys for testnet and mainnet.** If a testnet key leaks, your mainnet data stays safe.

## Rollback Plan

If something goes wrong after mainnet deployment:

1. **Stop the relay** — no new inferences will be processed
2. **Don't panic about existing data** — encrypted messages on-chain are safe (they're ciphertext)
3. **Fix the issue on emulator** — reproduce and fix locally
4. **Test on testnet** — verify the fix
5. **Update mainnet contracts** — use `--update` flag if contract changes are needed
6. **Restart the relay** — resume operations

There is no way to delete on-chain data. But since everything is encrypted, "leaked" ciphertext is useless without the key.

---

[← Relay Setup](relay-setup.md) | [Back to README →](../README.md)
