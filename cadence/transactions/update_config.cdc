// update_config.cdc
// Update the agent's inference configuration (model, provider, etc.)
// Only the account owner can do this — private storage.

import "AgentRegistry"

transaction(
    provider: String,
    model: String,
    apiKeyHash: String,
    maxTokens: UInt64,
    temperature: UFix64,
    systemPrompt: String
) {
    prepare(signer: auth(Storage) &Account) {
        let agent = signer.storage.borrow<auth(AgentRegistry.Configure) &AgentRegistry.Agent>(
            from: AgentRegistry.AgentStoragePath
        ) ?? panic("Agent not found. Run initialize_account first.")

        let newConfig = AgentRegistry.InferenceConfig(
            provider: provider,
            model: model,
            apiKeyHash: apiKeyHash,
            maxTokens: maxTokens,
            temperature: temperature,
            systemPrompt: systemPrompt
        )

        agent.updateInferenceConfig(newConfig)
        log("Inference config updated")
    }
}
