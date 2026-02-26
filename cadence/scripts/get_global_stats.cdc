// get_global_stats.cdc
// Get global FlowClaw network statistics.

import "AgentRegistry"
import "AgentSession"
import "FlowClaw"

access(all) struct GlobalStats {
    access(all) let version: String
    access(all) let totalAgents: UInt64
    access(all) let totalSessions: UInt64
    access(all) let totalInferenceRequests: UInt64
    access(all) let totalAccounts: UInt64
    access(all) let totalMessages: UInt64

    init(
        version: String,
        totalAgents: UInt64,
        totalSessions: UInt64,
        totalInferenceRequests: UInt64,
        totalAccounts: UInt64,
        totalMessages: UInt64
    ) {
        self.version = version
        self.totalAgents = totalAgents
        self.totalSessions = totalSessions
        self.totalInferenceRequests = totalInferenceRequests
        self.totalAccounts = totalAccounts
        self.totalMessages = totalMessages
    }
}

access(all) fun main(): GlobalStats {
    return GlobalStats(
        version: FlowClaw.getVersion(),
        totalAgents: AgentRegistry.totalAgents,
        totalSessions: AgentSession.totalSessions,
        totalInferenceRequests: AgentSession.totalInferenceRequests,
        totalAccounts: FlowClaw.totalAccounts,
        totalMessages: FlowClaw.totalMessages
    )
}
