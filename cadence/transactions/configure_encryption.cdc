// configure_encryption.cdc
// Set up or rotate encryption keys for your FlowClaw agent.
//
// This registers the KEY FINGERPRINT on-chain — the actual key NEVER touches the chain.
// The relay stores the real encryption key locally in ~/.flowclaw/encryption.key
//
// Usage:
//   1. Relay generates a random XChaCha20-Poly1305 key
//   2. Relay computes SHA-256(key) → fingerprint
//   3. User runs this transaction with the fingerprint
//   4. All future messages are encrypted with this key
//
// Key rotation: just run this again with a new fingerprint.
// Old keys are kept in history so the relay can still decrypt old messages.

import "AgentEncryption"

transaction(
    keyFingerprint: String,
    algorithm: UInt8,
    label: String
) {
    prepare(signer: auth(Storage) &Account) {
        // Create EncryptionConfig if it doesn't exist
        if signer.storage.borrow<&AgentEncryption.EncryptionConfig>(
            from: AgentEncryption.EncryptionConfigStoragePath
        ) == nil {
            let config <- AgentEncryption.createEncryptionConfig()
            signer.storage.save(<- config, to: AgentEncryption.EncryptionConfigStoragePath)
        }

        // Configure the key
        let encConfig = signer.storage.borrow<
            auth(AgentEncryption.ManageKeys) &AgentEncryption.EncryptionConfig
        >(
            from: AgentEncryption.EncryptionConfigStoragePath
        ) ?? panic("EncryptionConfig not found after creation")

        let algo = algorithm == 0
            ? AgentEncryption.Algorithm.xchacha20poly1305
            : AgentEncryption.Algorithm.aes256gcm

        encConfig.configureKey(
            fingerprint: keyFingerprint,
            algorithm: algo,
            label: label
        )

        log("Encryption configured with key: ".concat(keyFingerprint))
    }
}
