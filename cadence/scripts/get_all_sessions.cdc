// get_all_sessions.cdc
// Retrieve all sessions and their metadata for an account.
// Returns session count and detailed information about each session.

import "AgentSession"

access(all) struct SessionInfo {
    access(all) let sessionId: UInt64
    access(all) let agentId: UInt64
    access(all) let createdAt: UFix64
    access(all) let isOpen: Bool
    access(all) let messageCount: UInt64
    access(all) let totalTokensUsed: UInt64

    init(
        sessionId: UInt64,
        agentId: UInt64,
        createdAt: UFix64,
        isOpen: Bool,
        messageCount: UInt64,
        totalTokensUsed: UInt64
    ) {
        self.sessionId = sessionId
        self.agentId = agentId
        self.createdAt = createdAt
        self.isOpen = isOpen
        self.messageCount = messageCount
        self.totalTokensUsed = totalTokensUsed
    }
}

access(all) struct AllSessionsResult {
    access(all) let totalSessions: Int
    access(all) let sessions: [SessionInfo]

    init(totalSessions: Int, sessions: [SessionInfo]) {
        self.totalSessions = totalSessions
        self.sessions = sessions
    }
}

access(all) fun main(address: Address): AllSessionsResult {
    let account = getAuthAccount<auth(Storage) &Account>(address)

    var sessions: [SessionInfo] = []

    if let sessionManager = account.storage.borrow<&AgentSession.SessionManager>(
        from: AgentSession.SessionManagerStoragePath
    ) {
        let sessionIds = sessionManager.getSessionIds()
        let sessionCount = sessionManager.getSessionCount()

        // Iterate through all sessions and collect their metadata
        for sessionId in sessionIds {
            if let session = sessionManager.borrowSession(sessionId: sessionId) {
                let messageCount = session.getMessageCount()

                let info = SessionInfo(
                    sessionId: sessionId,
                    agentId: session.agentId,
                    createdAt: session.createdAt,
                    isOpen: session.isOpen,
                    messageCount: messageCount,
                    totalTokensUsed: session.totalTokensUsed
                )
                sessions.append(info)
            }
        }

        return AllSessionsResult(totalSessions: sessionCount, sessions: sessions)
    }

    return AllSessionsResult(totalSessions: 0, sessions: [])
}
