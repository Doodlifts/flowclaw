// complete_inference_owner.cdc
// Owner-signed version: posts the relay's ENCRYPTED response back on-chain.
//
// PRIVACY: The response from the LLM is encrypted by the relay before
// being submitted in this transaction. Block explorers see ciphertext only.
//
// Flow:
//   LLM responds "FLOW is a blockchain..."
//     → Relay encrypts → ciphertext "kR8pT3w..."
//     → This transaction stores ciphertext on-chain
//     → Relay reads back, decrypts locally, shows to user
//
// In production, this would use HybridCustody for delegated signing.

import "AgentRegistry"
import "AgentSession"
import "InferenceOracle"
import "AgentEncryption"
import "FlowClaw"

transaction(
    sessionId: UInt64,
    requestId: UInt64,
    responseCiphertext: String,
    responseNonce: String,
    responsePlaintextHash: String,
    responseKeyFingerprint: String,
    responseAlgorithm: UInt8,
    responsePlaintextLength: UInt64,
    tokensUsed: UInt64
) {
    prepare(owner: auth(Storage) &Account) {
        // Build the encrypted payload for the response
        let payload = AgentEncryption.EncryptedPayload(
            ciphertext: responseCiphertext,
            nonce: responseNonce,
            plaintextHash: responsePlaintextHash,
            keyFingerprint: responseKeyFingerprint,
            algorithm: responseAlgorithm,
            plaintextLength: responsePlaintextLength
        )

        // Verify encryption key is known to this account
        if let encConfig = owner.storage.borrow<auth(AgentEncryption.Verify) &AgentEncryption.EncryptionConfig>(
            from: AgentEncryption.EncryptionConfigStoragePath
        ) {
            assert(
                encConfig.verifyPayload(payload: payload),
                message: "Response encrypted with unknown key"
            )
            encConfig.recordVerification()
        }

        let agentStack = owner.storage.borrow<auth(FlowClaw.Operate) &FlowClaw.AgentStack>(
            from: FlowClaw.FlowClawStoragePath
        ) ?? panic("AgentStack not found.")

        let sessionManager = owner.storage.borrow<auth(AgentSession.Manage) &AgentSession.SessionManager>(
            from: AgentSession.SessionManagerStoragePath
        ) ?? panic("SessionManager not found.")

        let agent = owner.storage.borrow<auth(AgentRegistry.Execute) &AgentRegistry.Agent>(
            from: AgentRegistry.AgentStoragePath
        ) ?? panic("Agent not found.")

        let oracleConfig = owner.storage.borrow<auth(InferenceOracle.Relay) &InferenceOracle.OracleConfig>(
            from: InferenceOracle.OracleConfigStoragePath
        ) ?? panic("OracleConfig not found.")

        // Complete inference — content is CIPHERTEXT, hash is of PLAINTEXT
        agentStack.completeInference(
            sessionManager: sessionManager,
            agent: agent,
            oracleConfig: oracleConfig,
            sessionId: sessionId,
            requestId: requestId,
            responseContent: responseCiphertext,
            responseHash: responsePlaintextHash,
            tokensUsed: tokensUsed,
            relayAddress: owner.address
        )

        // Record encryption stats
        if let encConfig = owner.storage.borrow<auth(AgentEncryption.Encrypt) &AgentEncryption.EncryptionConfig>(
            from: AgentEncryption.EncryptionConfigStoragePath
        ) {
            encConfig.recordEncryption()
        }

        // Event emission handled by the contract internally
        log("Encrypted inference completed for session ".concat(sessionId.toString()))
    }
}
