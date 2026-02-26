// create_agent_in_collection.cdc
// Creates a new agent in the account's AgentCollection.
// Used for multi-agent accounts — adds a new agent without replacing existing ones.

import "AgentRegistry"

transaction(
    agentName: String,
    agentDescription: String,
    provider: String,
    model: String,
    apiKeyHash: String,
    maxTokens: UInt64,
    temperature: UFix64,
    systemPrompt: String,
    autonomyLevel: UInt8,
    maxActionsPerHour: UInt64,
    maxCostPerDay: UFix64
) {
    prepare(signer: auth(Storage) &Account) {
        // Borrow the collection
        let collection = signer.storage.borrow<auth(AgentRegistry.Manage) &AgentRegistry.AgentCollection>(
            from: AgentRegistry.AgentCollectionStoragePath
        ) ?? panic("AgentCollection not found. Run setup_full_account or migrate_to_agent_collection first.")

        let inferenceConfig = AgentRegistry.InferenceConfig(
            provider: provider,
            model: model,
            apiKeyHash: apiKeyHash,
            maxTokens: maxTokens,
            temperature: temperature,
            systemPrompt: systemPrompt
        )

        let securityPolicy = AgentRegistry.SecurityPolicy(
            autonomyLevel: autonomyLevel,
            maxActionsPerHour: maxActionsPerHour,
            maxCostPerDay: maxCostPerDay,
            allowedTools: ["memory_store", "memory_recall", "web_fetch", "flow_query",
                           "query_balance", "get_flow_price", "search_web"],
            deniedTools: ["shell_exec"]
        )

        let agentId = collection.createAgent(
            name: agentName,
            description: agentDescription,
            ownerAddress: signer.address,
            inferenceConfig: inferenceConfig,
            securityPolicy: securityPolicy
        )

        log("Created new agent #".concat(agentId.toString()).concat(" in collection"))
    }

    execute {
        log("Agent added to collection")
    }
}
