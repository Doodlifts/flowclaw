// send_message.cdc
// Send an ENCRYPTED user message to a session and trigger inference.
// This is the main user-facing transaction — "talk to your agent".
//
// PRIVACY: The content field is CIPHERTEXT — encrypted by the relay before
// this transaction is submitted. Block explorers see encrypted gibberish.
// The plaintextHash lets the relay verify integrity after decryption.
//
// Flow:
//   User types "What is FLOW?"
//     → Relay encrypts → ciphertext "x7Fk9mQ2..."
//     → This transaction stores ciphertext on-chain
//     → InferenceRequested event fires (with hash, not content)
//     → Relay picks up event, decrypts locally, calls LLM

import "AgentRegistry"
import "AgentSession"
import "AgentEncryption"
import "FlowClaw"

transaction(
    sessionId: UInt64,
    ciphertext: String,
    nonce: String,
    plaintextHash: String,
    keyFingerprint: String,
    algorithm: UInt8,
    plaintextLength: UInt64
) {
    prepare(signer: auth(Storage) &Account) {
        // Build the encrypted payload
        let payload = AgentEncryption.EncryptedPayload(
            ciphertext: ciphertext,
            nonce: nonce,
            plaintextHash: plaintextHash,
            keyFingerprint: keyFingerprint,
            algorithm: algorithm,
            plaintextLength: plaintextLength
        )

        // Optionally verify the payload against the account's encryption config
        if let encConfig = signer.storage.borrow<auth(AgentEncryption.Verify) &AgentEncryption.EncryptionConfig>(
            from: AgentEncryption.EncryptionConfigStoragePath
        ) {
            assert(
                encConfig.verifyPayload(payload: payload),
                message: "Payload encrypted with unknown key"
            )
            encConfig.recordVerification()
        }

        // Borrow agent resources
        let agentStack = signer.storage.borrow<auth(FlowClaw.Operate) &FlowClaw.AgentStack>(
            from: FlowClaw.FlowClawStoragePath
        ) ?? panic("AgentStack not found. Run initialize_account first.")

        let sessionManager = signer.storage.borrow<auth(AgentSession.Manage) &AgentSession.SessionManager>(
            from: AgentSession.SessionManagerStoragePath
        ) ?? panic("SessionManager not found.")

        let agent = signer.storage.borrow<auth(AgentRegistry.Execute) &AgentRegistry.Agent>(
            from: AgentRegistry.AgentStoragePath
        ) ?? panic("Agent not found.")

        // Send message — content is CIPHERTEXT, hash is of PLAINTEXT
        // The relay decrypts locally; the chain never sees plaintext
        let requestId = agentStack.sendMessage(
            sessionManager: sessionManager,
            agent: agent,
            sessionId: sessionId,
            content: ciphertext,
            contentHash: plaintextHash
        )

        if let rid = requestId {
            log("Inference requested with ID: ".concat(rid.toString()))

            // Record encryption usage
            if let encConfig = signer.storage.borrow<auth(AgentEncryption.Encrypt) &AgentEncryption.EncryptionConfig>(
                from: AgentEncryption.EncryptionConfigStoragePath
            ) {
                encConfig.recordEncryption()
            }

            // Event emission handled by the contract internally
            log("Encrypted message stored for session ".concat(sessionId.toString()))
        } else {
            log("Failed to send message — agent paused or rate limited")
        }
    }
}
