// create_session.cdc
// Create a new conversation session for the account's agent.
// Sessions are private — only the account owner can read/write.

import "AgentRegistry"
import "AgentSession"

transaction(maxContextMessages: UInt64) {
    prepare(signer: auth(Storage) &Account) {
        // Borrow agent to get its ID
        let agent = signer.storage.borrow<auth(AgentRegistry.Execute) &AgentRegistry.Agent>(
            from: AgentRegistry.AgentStoragePath
        ) ?? panic("Agent not found. Run initialize_account first.")

        let agentId = agent.id

        // Borrow session manager
        let sessionManager = signer.storage.borrow<auth(AgentSession.Manage) &AgentSession.SessionManager>(
            from: AgentSession.SessionManagerStoragePath
        ) ?? panic("SessionManager not found.")

        // Create session
        let sessionId = sessionManager.createSession(
            agentId: agentId,
            maxContextMessages: maxContextMessages
        )

        // Record on agent
        agent.recordSession()

        log("Session created with ID: ".concat(sessionId.toString()))
    }
}
