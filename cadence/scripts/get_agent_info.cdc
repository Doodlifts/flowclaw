// get_agent_info.cdc
// Read public info about any account's agent.

import "AgentRegistry"

access(all) fun main(address: Address): AgentRegistry.AgentPublicInfo? {
    let account = getAuthAccount<auth(Storage) &Account>(address)
    if let agent = account.storage.borrow<&AgentRegistry.Agent>(
        from: AgentRegistry.AgentStoragePath
    ) {
        return agent.getPublicInfo()
    }
    return nil
}
