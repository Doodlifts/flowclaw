// get_session_history.cdc
// Read the message history for a session.

import "AgentSession"

access(all) fun main(address: Address, sessionId: UInt64): [AgentSession.Message] {
    let account = getAuthAccount<auth(Storage) &Account>(address)
    if let sessionManager = account.storage.borrow<auth(AgentSession.ReadHistory, AgentSession.Manage) &AgentSession.SessionManager>(
        from: AgentSession.SessionManagerStoragePath
    ) {
        if let session = sessionManager.borrowSession(sessionId: sessionId) {
            return session.getMessages()
        }
    }
    return []
}
