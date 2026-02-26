# FlowClaw Deployment Notes

Reference document for mainnet deployment. Captures every issue hit during testnet deployment and the fixes applied.

## Testnet Details

- **Account**: `0x808983d30a46aee2`
- **Account Name**: `flowclawtest`
- **Explorer**: https://testnet.flowscan.io/account/0x808983d30a46aee2
- **Contracts**: 10 deployed, all initialized
- **Key File**: `flowclawtest.pkey` (ECDSA_P256)

---

## Issue Log

### 1. Flow CLI Contract Deploy Syntax

**Problem**: `flow accounts add-contract ContractName --code ./path.cdc` fails.
**Fix**: Correct syntax is `flow accounts add-contract ./path/to/Contract.cdc --signer <account> --network <network>`. The CLI takes the file path as the positional argument — no separate contract name needed.

### 2. Deploy Script Account Detection

**Problem**: `deploy-testnet.sh` looked for `aliases` inside the account object in `flow.json`, but Flow CLI stores aliases on contracts, not accounts.
**Fix**: Changed detection to look in `deployments.testnet` for the account name, with fallback to any non-emulator account.

### 3. Cadence 1.0: `self.owner` is nil Before Storage Save

**Problem**: `initialize_account.cdc` created a `ToolCollection` resource, called `registerTool()` on it (which internally uses `self.owner!.address`), then saved it. But `self.owner` is nil until the resource is saved to account storage.
**Fix**: Save the resource to storage FIRST, then borrow it back to register tools:
```cadence
let toolCollection <- ToolRegistry.createToolCollection()
signer.storage.save(<- toolCollection, to: ToolRegistry.ToolCollectionStoragePath)
let toolRef = signer.storage.borrow<auth(ToolRegistry.ManageTools) &ToolRegistry.ToolCollection>(
    from: ToolRegistry.ToolCollectionStoragePath
)!
for tool in defaultTools {
    toolRef.registerTool(tool)
}
```
**Mainnet note**: Check ALL transactions that create resources and call methods on them before saving. Any method using `self.owner` will panic.

### 4. Cannot Emit Imported Events from Transactions

**Problem**: `send_message.cdc`, `complete_inference.cdc`, and `complete_inference_owner.cdc` all had `emit AgentEncryption.EncryptedMessageStored(...)`. Cadence does not allow emitting events declared in an imported contract from a transaction.
**Fix**: Removed all `emit` lines from transactions. Events should only be emitted from within the contract that declares them. Replaced with `log()` calls.
**Mainnet note**: If we need these events, add helper functions inside the contracts that emit them when called.

### 5. Entitlement Missing on `create_session.cdc`

**Problem**: `create_session.cdc` borrowed `&AgentRegistry.Agent` without entitlements, then called `agent.recordSession()` which requires `Execute` authorization.
**Fix**: Changed borrow to `auth(AgentRegistry.Execute) &AgentRegistry.Agent`.
**Mainnet note**: Always check what entitlements a method requires before borrowing. The emulator is sometimes more lenient than testnet/mainnet.

### 6. Encryption Key Fingerprint Not Registered On-Chain

**Problem**: During `initialize_account`, we used a placeholder encryption key fingerprint. The relay auto-generates a real key with a different fingerprint. On-chain `verifyPayload()` then fails with "Payload encrypted with unknown key."
**Fix**: After relay starts and generates a key, register the actual fingerprint on-chain:
```bash
# Get fingerprint
python3 -c "
import base64, hashlib
with open('<path-to-key>') as f:
    key_b64 = f.read().strip()
key = base64.b64decode(key_b64)
print(hashlib.sha256(key).hexdigest())
"
# Register on-chain
flow transactions send cadence/transactions/configure_encryption.cdc \
    --signer <account> --network <network> \
    --args-json '[{"type":"String","value":"<fingerprint>"},{"type":"UInt8","value":"0"},{"type":"String","value":"relay-xchacha20"}]'
```
**Mainnet note**: Automate this — have the deploy script or relay startup register the key fingerprint automatically. Or generate the key BEFORE initialize_account and pass the real fingerprint.

### 7. Encryption Key Path: Tilde Not Expanding

**Problem**: `.env` had `FLOWCLAW_ENCRYPTION_KEY=~/.flowclaw/encryption.key`. Python's `os.path.expanduser()` works, but the relay code was creating the directory literally as `~/.flowclaw/` inside the project directory instead of the home directory.
**Fix**: The key ended up at `/Users/mattnofi/flowclaw/~/.flowclaw/encryption.key`. For mainnet, ensure the path uses an absolute expanded path or fix the relay to call `os.path.expanduser()` on the configured path.
**Mainnet note**: Use absolute path in `.env`: `FLOWCLAW_ENCRYPTION_KEY=/Users/<user>/.flowclaw/encryption.key`

### 8. Relay Signer Hardcoded to `emulator-account`

**Problem**: `api.py`'s `run_flow_tx()` had `--signer emulator-account` hardcoded. On testnet, the signer is `flowclawtest`.
**Fix**: Dynamic signer selection based on network:
```python
signer = "flowclawtest" if config.flow_network == "testnet" else "emulator-account"
```
**Mainnet note**: Add mainnet signer config. Should be configurable via `.env` rather than if/else:
```
FLOW_SIGNER_ACCOUNT=flowclawmain
```

### 9. Session ID Not Parsed from Transaction Output

**Problem**: `create_session` endpoint generated a fake session ID (`int(time.time()) % 100000`) instead of the real on-chain ID. Messages sent with this ID caused "Session not found" on-chain.
**Fix**: After creating a session, query `get_account_status.cdc` to get `sessionCount`, then use `count - 1` as the session ID (0-indexed).
**Mainnet note**: Even better — parse the `SessionCreated` event from the transaction output. The regex `sessionId\s*\(UInt64\):\s*(\d+)` works but the Flow CLI output may contain binary/emoji characters that need to be handled. The combined stdout+stderr approach works.

### 10. Request ID Hardcoded to 0 in complete_inference

**Problem**: The relay passed `requestId: 0` to `complete_inference_owner.cdc`, but the actual request ID is generated by `sendMessage` on-chain. The contract's pre-condition checks for a matching pending request.
**Fix**: Parse the request ID from the `send_message` transaction output (event `requestId (UInt64): N` or log `Inference requested with ID: N`) and pass it to complete_inference.
**Mainnet note**: This is critical — without the correct request ID, inference completion will always fail.

### 11. Flow CLI Output Parsing: Binary Characters

**Problem**: Flow CLI outputs security warnings with emoji (❗) which appear as binary when piped. `grep` treats the output as binary and skips it. `strings` is needed to extract readable text.
**Fix**: In the relay, combine stdout and stderr (`result.stdout + result.stderr`) and use regex on the combined string. For manual debugging, use `strings <logfile> | grep <pattern>` instead of `cat | grep`.
**Mainnet note**: Consider adding `--yes` or `--skip-security-warnings` flags if available, or redirect to a clean log format.

### 12. Uvicorn Process Not Dying on pkill

**Problem**: `pkill -f uvicorn` sometimes doesn't kill the process, so the new relay starts on the same port and gets "address already in use."
**Fix**: Use `lsof -ti:8000 | xargs kill -9` to kill by port, not by process name.
**Mainnet note**: Use Docker or systemd for proper process management. The Dockerfile and docker-compose.yml are already created.

---

## Deployment Order (Critical)

Contracts must be deployed in this exact order due to import dependencies:

1. **Layer 1** (no cross-dependencies): AgentRegistry, AgentSession, InferenceOracle, ToolRegistry
2. **Layer 2** (depends on Layer 1): AgentMemory, AgentScheduler, AgentLifecycleHooks, AgentEncryption
3. **Layer 3** (depends on Layer 2): AgentExtensions
4. **Layer 4** (depends on all): FlowClaw

## Initialization Order (Critical)

After all contracts are deployed:

1. `initialize_account.cdc` — creates all 10 resources in the account
2. `configure_encryption.cdc` — registers the REAL encryption key fingerprint
3. `authorize_relay.cdc` — (optional, already done in initialize_account as self-relay)

## Mainnet Checklist

- [ ] Create mainnet account with `flow accounts create --network mainnet`
- [ ] Fund account with FLOW
- [ ] Add mainnet aliases to `flow.json` for all 10 contracts
- [ ] Add mainnet deployment config to `flow.json`
- [ ] Generate encryption key BEFORE deploying (so fingerprint is known)
- [ ] Deploy contracts in order (Layer 1 → 2 → 3 → 4)
- [ ] Run `initialize_account.cdc` with real encryption fingerprint
- [ ] Register encryption key on-chain with `configure_encryption.cdc`
- [ ] Update `.env` with mainnet account, key, and signer
- [ ] Update relay signer logic for mainnet account name
- [ ] Set absolute path for encryption key in `.env`
- [ ] Consider multi-key security (setup_multikey_security.cdc)
- [ ] Use Docker/systemd for process management
- [ ] Test full chat round-trip before going live

## Testnet Feature Verification (Completed)

- [x] Chat — encrypted messages + Venice AI inference, clean round-trip
- [x] Memory — `store_memory.cdc` (needs 9 params with encryption fields, not 3)
- [x] Scheduling — `schedule_task.cdc` one-shot task sealed clean
- [x] Lifecycle Hooks — `register_hook.cdc` (7 params) sealed clean
- [x] Extensions — `publish_extension.cdc` (6 params) sealed clean
  - **NOTE**: `ExtensionRegistry` is not created by `initialize_account.cdc`. Must run `create_extension_registry.cdc` separately before publishing extensions. Add this to mainnet init flow.
- [ ] Extensions — install_extension.cdc, uninstall_extension.cdc (not yet tested)
- [ ] Multi-session management
- [ ] Tool execution through the agent loop
- [ ] Global stats accuracy after fresh deploy

### 13. ExtensionRegistry Not Created During Account Init

**Problem**: `initialize_account.cdc` creates `ExtensionManager` but not `ExtensionRegistry`. Publishing extensions fails with "ExtensionRegistry not found."
**Fix**: Run `create_extension_registry.cdc` after account initialization.
**Mainnet note**: Add this to the init sequence, or add it to `initialize_account.cdc` directly.
