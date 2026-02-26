// get_session_messages.cdc
// Retrieve all messages for a specific session.
// Returns an array of messages including encrypted payloads.

import "AgentSession"

access(all) fun main(address: Address, sessionId: UInt64): [AgentSession.Message] {
    let account = getAuthAccount<auth(Storage) &Account>(address)

    if let sessionManager = account.storage.borrow<&AgentSession.SessionManager>(
        from: AgentSession.SessionManagerStoragePath
    ) {
        if let session = sessionManager.borrowSession(sessionId: sessionId) {
            return session.getMessages()
        }
    }

    return []
}
