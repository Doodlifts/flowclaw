// create_session.cdc
// Create a new conversation session for the account's agent.
// Sessions are private — only the account owner can read/write.

import "AgentRegistry"
import "AgentSession"

transaction(maxContextMessages: UInt64) {
    prepare(signer: auth(Storage) &Account) {
        // Borrow agent from AgentCollection (multi-agent) or legacy single-agent path
        let collection = signer.storage.borrow<auth(AgentRegistry.Manage) &AgentRegistry.AgentCollection>(
            from: AgentRegistry.AgentCollectionStoragePath
        )
        var agent: auth(AgentRegistry.Execute) &AgentRegistry.Agent? = nil
        if collection != nil {
            let defaultId = collection!.getDefaultAgentId()
            if defaultId != nil {
                agent = collection!.borrowAgentManaged(id: defaultId!)
            } else {
                let ids = collection!.getAgentIds()
                if ids.length > 0 {
                    agent = collection!.borrowAgentManaged(id: ids[0])
                }
            }
        }
        if agent == nil {
            agent = signer.storage.borrow<auth(AgentRegistry.Execute) &AgentRegistry.Agent>(
                from: AgentRegistry.AgentStoragePath
            )
        }
        let activeAgent = agent ?? panic("No agent found. Create an agent first.")

        let agentId = activeAgent.id

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
        activeAgent.recordSession()

        log("Session created with ID: ".concat(sessionId.toString()))
    }
}
