// migrate_to_agent_collection.cdc
// Migrates an account from single-Agent storage to AgentCollection.
// Moves the existing Agent at /storage/FlowClawAgent into a new AgentCollection
// at /storage/FlowClawAgentCollection, setting it as the default.
// This is a one-time migration for existing accounts.

import "AgentRegistry"

transaction {
    prepare(signer: auth(Storage) &Account) {
        // Check if already migrated
        if signer.storage.type(at: AgentRegistry.AgentCollectionStoragePath) != nil {
            log("Already migrated to AgentCollection — skipping")
            return
        }

        // Create new collection
        let collection <- AgentRegistry.createAgentCollection()

        // Move existing agent into collection (if it exists)
        if let agent <- signer.storage.load<@AgentRegistry.Agent>(from: AgentRegistry.AgentStoragePath) {
            let agentId = agent.id
            log("Migrating Agent #".concat(agentId.toString()).concat(" into AgentCollection"))
            collection.addAgent(<- agent)
            collection.setDefault(agentId: agentId)
        } else {
            log("No existing Agent found — creating empty collection")
        }

        // Save collection
        signer.storage.save(<- collection, to: AgentRegistry.AgentCollectionStoragePath)

        log("Migration complete! AgentCollection stored at /storage/FlowClawAgentCollection")
    }

    execute {
        log("Account migrated to multi-agent architecture")
    }
}
