// AgentEncryption.cdc
// End-to-end encryption for on-chain agent messages.
//
// THE PROBLEM:
// Cadence's /storage/ is private at rest — no other account can read it.
// But transaction arguments are publicly visible on the blockchain.
// When send_message.cdc includes the message text as an argument,
// that text is visible on every block explorer forever.
// The "private storage" only protects against script-based queries,
// not against reading the transaction payload that PUT the data there.
//
// THE SOLUTION:
// Encrypt ALL content before it enters a transaction.
// The transaction carries ciphertext + plaintext hash.
// Storage holds ciphertext. The relay decrypts locally.
// Block explorers see encrypted gibberish, not your conversations.
//
// HOW IT WORKS:
//
//  User types "What is FLOW?"
//       │
//       ▼
//  Relay encrypts: E("What is FLOW?", account_key) → "x7Fk9mQ2..."
//  Relay computes: SHA256("What is FLOW?") → "a3b8c1..."
//       │
//       ▼
//  Transaction: send_message("x7Fk9mQ2...", "a3b8c1...")
//       │                      ↑ ciphertext      ↑ hash of plaintext
//       ▼
//  On-chain: Session stores encrypted content + hash
//       │
//  Block explorer sees: "x7Fk9mQ2..." (meaningless)
//       │
//       ▼
//  LLM responds → Relay encrypts response → posts encrypted on-chain
//       │
//       ▼
//  Relay reads back, decrypts locally, shows to user
//
// KEY MANAGEMENT:
// - Each account has an EncryptionConfig resource in private storage
// - The config stores a public key (on-chain) and key metadata
// - The actual private/symmetric key NEVER touches the chain
// - The relay holds the decryption key locally in .env or keyfile
// - Key rotation is supported: old keys kept for decrypting history
//
// ENCRYPTION SCHEME:
// - Symmetric: XChaCha20-Poly1305 (same as ZeroClaw, industry standard)
// - The symmetric key is derived from a passphrase or generated randomly
// - Stored locally in ~/.flowclaw/encryption.key (never on-chain)
// - The on-chain EncryptionConfig stores only the public verification key
//   and a key fingerprint so the relay knows which key to use
//
// WHAT THIS ACHIEVES:
// - Transaction payloads: encrypted (public but unreadable)
// - Storage contents: encrypted (private AND encrypted — defense in depth)
// - Content hashes: of plaintext (verifiable without decrypting)
// - Block explorers: see ciphertext only
// - The relay: only party that can decrypt (holds the key locally)

access(all) contract AgentEncryption {

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    access(all) event EncryptionConfigured(owner: Address, algorithm: String, keyFingerprint: String)
    access(all) event KeyRotated(owner: Address, oldFingerprint: String, newFingerprint: String)
    access(all) event EncryptedMessageStored(sessionId: UInt64, contentHash: String, ciphertextLength: UInt64)

    // -----------------------------------------------------------------------
    // Paths
    // -----------------------------------------------------------------------
    access(all) let EncryptionConfigStoragePath: StoragePath

    // -----------------------------------------------------------------------
    // Entitlements
    // -----------------------------------------------------------------------
    access(all) entitlement ManageKeys
    access(all) entitlement Encrypt
    access(all) entitlement Verify

    // -----------------------------------------------------------------------
    // Supported encryption algorithms
    // -----------------------------------------------------------------------
    access(all) enum Algorithm: UInt8 {
        access(all) case xchacha20poly1305    // Symmetric AEAD (recommended)
        access(all) case aes256gcm            // Alternative symmetric AEAD
    }

    // -----------------------------------------------------------------------
    // KeyInfo — metadata about an encryption key (key itself is NEVER on-chain)
    // -----------------------------------------------------------------------
    access(all) struct KeyInfo {
        access(all) let fingerprint: String     // SHA-256 of the key (for identification)
        access(all) let algorithm: Algorithm
        access(all) let createdAt: UFix64
        access(all) let isActive: Bool
        access(all) let label: String

        init(
            fingerprint: String,
            algorithm: Algorithm,
            label: String,
            isActive: Bool
        ) {
            self.fingerprint = fingerprint
            self.algorithm = algorithm
            self.createdAt = getCurrentBlock().timestamp
            self.isActive = isActive
            self.label = label
        }
    }

    // -----------------------------------------------------------------------
    // EncryptedPayload — what gets stored on-chain instead of plaintext
    // -----------------------------------------------------------------------
    access(all) struct EncryptedPayload {
        access(all) let ciphertext: String         // Base64-encoded encrypted content
        access(all) let nonce: String              // Base64-encoded nonce/IV
        access(all) let plaintextHash: String      // SHA-256 of original plaintext
        access(all) let keyFingerprint: String     // Which key was used (for rotation)
        access(all) let algorithm: UInt8           // Which algorithm
        access(all) let plaintextLength: UInt64    // Length of original text (for estimation)

        init(
            ciphertext: String,
            nonce: String,
            plaintextHash: String,
            keyFingerprint: String,
            algorithm: UInt8,
            plaintextLength: UInt64
        ) {
            pre {
                ciphertext.length > 0: "Ciphertext cannot be empty"
                nonce.length > 0: "Nonce cannot be empty"
                plaintextHash.length > 0: "Plaintext hash cannot be empty"
                keyFingerprint.length > 0: "Key fingerprint cannot be empty"
            }
            self.ciphertext = ciphertext
            self.nonce = nonce
            self.plaintextHash = plaintextHash
            self.keyFingerprint = keyFingerprint
            self.algorithm = algorithm
            self.plaintextLength = plaintextLength
        }
    }

    // -----------------------------------------------------------------------
    // EncryptionConfig — per-account encryption settings
    // Stored in /storage/ (private), but only contains key metadata,
    // NEVER the actual encryption key.
    // -----------------------------------------------------------------------
    access(all) resource EncryptionConfig {
        access(self) var activeKey: KeyInfo?
        access(self) var keyHistory: [KeyInfo]   // For decrypting old messages after rotation
        access(all) var isEnabled: Bool
        access(all) var totalEncrypted: UInt64
        access(all) var totalDecryptVerified: UInt64

        init() {
            self.activeKey = nil
            self.keyHistory = []
            self.isEnabled = false
            self.totalEncrypted = 0
            self.totalDecryptVerified = 0
        }

        // --- ManageKeys: configure encryption ---

        access(ManageKeys) fun configureKey(
            fingerprint: String,
            algorithm: Algorithm,
            label: String
        ) {
            post {
                self.activeKey != nil: "Active key must be set after configuration"
                self.isEnabled: "Encryption must be enabled after configuration"
            }

            // If there's an existing active key, move it to history
            if let oldKey = self.activeKey {
                let deactivated = KeyInfo(
                    fingerprint: oldKey.fingerprint,
                    algorithm: oldKey.algorithm,
                    label: oldKey.label,
                    isActive: false
                )
                self.keyHistory.append(deactivated)

                emit KeyRotated(
                    owner: self.owner!.address,
                    oldFingerprint: oldKey.fingerprint,
                    newFingerprint: fingerprint
                )
            }

            self.activeKey = KeyInfo(
                fingerprint: fingerprint,
                algorithm: algorithm,
                label: label,
                isActive: true
            )
            self.isEnabled = true

            let algoStr = algorithm == Algorithm.xchacha20poly1305
                ? "xchacha20-poly1305" : "aes-256-gcm"

            emit EncryptionConfigured(
                owner: self.owner!.address,
                algorithm: algoStr,
                keyFingerprint: fingerprint
            )
        }

        access(ManageKeys) fun disable() {
            self.isEnabled = false
        }

        access(ManageKeys) fun enable() {
            pre {
                self.activeKey != nil: "Configure a key first"
            }
            self.isEnabled = true
        }

        // --- Encrypt: record encrypted operations ---

        access(Encrypt) fun recordEncryption() {
            self.totalEncrypted = self.totalEncrypted + 1
        }

        // --- Verify: validate a payload's integrity ---

        access(Verify) fun verifyPayload(payload: EncryptedPayload): Bool {
            // Check that the key fingerprint matches a known key
            if let active = self.activeKey {
                if active.fingerprint == payload.keyFingerprint {
                    return true
                }
            }
            for key in self.keyHistory {
                if key.fingerprint == payload.keyFingerprint {
                    return true
                }
            }
            return false
        }

        access(Verify) fun recordVerification() {
            self.totalDecryptVerified = self.totalDecryptVerified + 1
        }

        // --- Read ---

        access(all) fun getActiveKeyInfo(): KeyInfo? {
            return self.activeKey
        }

        access(all) fun getKeyHistory(): [KeyInfo] {
            return self.keyHistory
        }

        access(all) fun getKeyForFingerprint(fingerprint: String): KeyInfo? {
            if let active = self.activeKey {
                if active.fingerprint == fingerprint {
                    return active
                }
            }
            for key in self.keyHistory {
                if key.fingerprint == fingerprint {
                    return key
                }
            }
            return nil
        }
    }

    // -----------------------------------------------------------------------
    // Public factory
    // -----------------------------------------------------------------------
    access(all) fun createEncryptionConfig(): @EncryptionConfig {
        return <- create EncryptionConfig()
    }

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    init() {
        self.EncryptionConfigStoragePath = /storage/FlowClawEncryptionConfig
    }
}
