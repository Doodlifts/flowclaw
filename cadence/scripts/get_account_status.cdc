// get_account_status.cdc
// Get a complete status overview of a FlowClaw account.

import "AgentRegistry"
import "AgentSession"
import "AgentMemory"
import "ToolRegistry"
import "FlowClaw"

access(all) fun main(address: Address): FlowClaw.AccountStatus? {
    let account = getAuthAccount<auth(Storage) &Account>(address)

    // Get agent info
    if let agent = account.storage.borrow<&AgentRegistry.Agent>(
        from: AgentRegistry.AgentStoragePath
    ) {
        let agentInfo = agent.getPublicInfo()

        // Get session count
        var sessionCount = 0
        if let sessionManager = account.storage.borrow<&AgentSession.SessionManager>(
            from: AgentSession.SessionManagerStoragePath
        ) {
            sessionCount = sessionManager.getSessionCount()
        }

        // Get memory count
        var memoryCount: UInt64 = 0
        if let memoryVault = account.storage.borrow<&AgentMemory.MemoryVault>(
            from: AgentMemory.MemoryVaultStoragePath
        ) {
            memoryCount = memoryVault.totalEntries
        }

        // Get tool count
        var toolCount = 0
        if let toolCollection = account.storage.borrow<&ToolRegistry.ToolCollection>(
            from: ToolRegistry.ToolCollectionStoragePath
        ) {
            toolCount = toolCollection.getToolNames().length
        }

        return FlowClaw.AccountStatus(
            owner: address,
            agentInfo: agentInfo,
            sessionCount: sessionCount,
            memoryCount: memoryCount,
            toolCount: toolCount,
            isRelayConfigured: true  // simplified for PoC
        )
    }

    return nil
}
