// store_cognitive_memory.cdc
// Stores a memory in AgentMemory AND registers cognitive metadata in CognitiveMemory.
// This is the primary write path for the cognitive memory system.

import AgentMemory from "../contracts/AgentMemory.cdc"
import AgentEncryption from "../contracts/AgentEncryption.cdc"
import CognitiveMemory from "../contracts/CognitiveMemory.cdc"

transaction(
    key: String,
    ciphertext: String,
    nonce: String,
    plaintextHash: String,
    keyFingerprint: String,
    algorithm: UInt8,
    plaintextLength: UInt64,
    tags: [String],
    source: String,
    memoryType: UInt8,
    importance: UInt8,
    emotionalWeight: UInt8
) {
    let memoryVault: auth(AgentMemory.Store) &AgentMemory.MemoryVault
    let cognitiveVault: auth(CognitiveMemory.Cognize) &CognitiveMemory.CognitiveVault

    prepare(signer: auth(BorrowValue, SaveValue) &Account) {
        // Verify encryption if configured
        if keyFingerprint.length > 0 {
            if let encConfig = signer.storage.borrow<&AgentEncryption.EncryptionConfig>(
                from: AgentEncryption.EncryptionConfigStoragePath
            ) {
                assert(
                    encConfig.verifyPayload(fingerprint: keyFingerprint, algorithm: algorithm),
                    message: "Invalid encryption key fingerprint"
                )
            }
        }

        // Get or create memory vault
        if signer.storage.borrow<&AgentMemory.MemoryVault>(from: AgentMemory.MemoryVaultStoragePath) == nil {
            signer.storage.save(<- AgentMemory.createMemoryVault(), to: AgentMemory.MemoryVaultStoragePath)
        }
        self.memoryVault = signer.storage.borrow<auth(AgentMemory.Store) &AgentMemory.MemoryVault>(
            from: AgentMemory.MemoryVaultStoragePath
        ) ?? panic("Could not borrow MemoryVault")

        // Get or create cognitive vault
        if signer.storage.borrow<&CognitiveMemory.CognitiveVault>(from: CognitiveMemory.CognitiveVaultStoragePath) == nil {
            signer.storage.save(<- CognitiveMemory.createCognitiveVault(), to: CognitiveMemory.CognitiveVaultStoragePath)
        }
        self.cognitiveVault = signer.storage.borrow<auth(CognitiveMemory.Cognize) &CognitiveMemory.CognitiveVault>(
            from: CognitiveMemory.CognitiveVaultStoragePath
        ) ?? panic("Could not borrow CognitiveVault")
    }

    execute {
        // Store content in base AgentMemory
        let contentToStore = ciphertext.length > 0 ? ciphertext : plaintextHash
        let memoryId = self.memoryVault.store(
            key: key,
            content: contentToStore,
            contentHash: plaintextHash,
            tags: tags,
            source: source
        )

        // Register cognitive metadata
        self.cognitiveVault.storeCognitive(
            memoryId: memoryId,
            memoryType: memoryType,
            importance: importance,
            emotionalWeight: emotionalWeight
        )
    }
}
