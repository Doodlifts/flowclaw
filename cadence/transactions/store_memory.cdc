// store_memory.cdc
// Store an ENCRYPTED memory entry in the agent's on-chain memory vault.
//
// PRIVACY: Both the key and content are encrypted by the relay.
// Tags remain plaintext for on-chain indexing (they're structural, not sensitive).
// If you need encrypted tags, encrypt the tag values before passing them.

import "AgentMemory"
import "AgentEncryption"
import "FlowClaw"

transaction(
    key: String,
    ciphertext: String,
    nonce: String,
    plaintextHash: String,
    keyFingerprint: String,
    algorithm: UInt8,
    plaintextLength: UInt64,
    tags: [String],
    source: String
) {
    prepare(signer: auth(Storage) &Account) {
        // Build encrypted payload for verification
        let payload = AgentEncryption.EncryptedPayload(
            ciphertext: ciphertext,
            nonce: nonce,
            plaintextHash: plaintextHash,
            keyFingerprint: keyFingerprint,
            algorithm: algorithm,
            plaintextLength: plaintextLength
        )

        // Verify the encryption key
        if let encConfig = signer.storage.borrow<auth(AgentEncryption.Verify) &AgentEncryption.EncryptionConfig>(
            from: AgentEncryption.EncryptionConfigStoragePath
        ) {
            assert(
                encConfig.verifyPayload(payload: payload),
                message: "Memory encrypted with unknown key"
            )
        }

        let agentStack = signer.storage.borrow<auth(FlowClaw.Operate) &FlowClaw.AgentStack>(
            from: FlowClaw.FlowClawStoragePath
        ) ?? panic("AgentStack not found.")

        let memoryVault = signer.storage.borrow<auth(AgentMemory.Store) &AgentMemory.MemoryVault>(
            from: AgentMemory.MemoryVaultStoragePath
        ) ?? panic("MemoryVault not found.")

        // Store encrypted content — the key can also be encrypted if desired
        let memoryId = agentStack.storeMemory(
            memoryVault: memoryVault,
            key: key,
            content: ciphertext,
            contentHash: plaintextHash,
            tags: tags,
            source: source
        )

        log("Encrypted memory stored with ID: ".concat(memoryId.toString()))
    }
}
