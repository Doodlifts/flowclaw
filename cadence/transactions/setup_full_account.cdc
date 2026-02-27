// setup_full_account.cdc
// One-transaction account initialization for new FlowClaw accounts.
// Creates ALL resources including the new AgentCollection (multi-agent).
// Used during passkey onboarding — one tx, everything ready.
// Idempotent: skips any resource that already exists at the storage path.

import "AgentRegistry"
import "AgentSession"
import "InferenceOracle"
import "ToolRegistry"
import "AgentMemory"
import "AgentScheduler"
import "AgentLifecycleHooks"
import "AgentExtensions"
import "AgentEncryption"
import "CognitiveMemory"
import "FlowClaw"

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
    prepare(signer: auth(Storage, Capabilities) &Account) {
        let ownerAddress = signer.address
        var agentId: UInt64 = 1

        // 1. Create AgentCollection (multi-agent support)
        if signer.storage.type(at: AgentRegistry.AgentCollectionStoragePath) == nil {
            let collection <- AgentRegistry.createAgentCollection()

            // 2. Create default agent inside the collection
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
            agentId = collection.createAgent(
                name: agentName,
                description: agentDescription,
                ownerAddress: ownerAddress,
                inferenceConfig: inferenceConfig,
                securityPolicy: securityPolicy
            )

            signer.storage.save(<- collection, to: AgentRegistry.AgentCollectionStoragePath)
        }

        // 3. Create SessionManager
        if signer.storage.type(at: AgentSession.SessionManagerStoragePath) == nil {
            let sessionManager <- AgentSession.createSessionManager()
            signer.storage.save(<- sessionManager, to: AgentSession.SessionManagerStoragePath)
        }

        // 4. Create ToolCollection with defaults
        if signer.storage.type(at: ToolRegistry.ToolCollectionStoragePath) == nil {
            let toolCollection <- ToolRegistry.createToolCollection()
            signer.storage.save(<- toolCollection, to: ToolRegistry.ToolCollectionStoragePath)

            let toolRef = signer.storage.borrow<auth(ToolRegistry.ManageTools) &ToolRegistry.ToolCollection>(
                from: ToolRegistry.ToolCollectionStoragePath
            )!
            let defaultTools = ToolRegistry.getDefaultTools(registeredBy: ownerAddress)
            for tool in defaultTools {
                toolRef.registerTool(tool)
            }
        }

        // 5. Create MemoryVault
        if signer.storage.type(at: AgentMemory.MemoryVaultStoragePath) == nil {
            let memoryVault <- AgentMemory.createMemoryVault()
            signer.storage.save(<- memoryVault, to: AgentMemory.MemoryVaultStoragePath)
        }

        // 6. Create CognitiveVault (cognitive memory)
        if signer.storage.type(at: CognitiveMemory.CognitiveVaultStoragePath) == nil {
            let cognitiveVault <- CognitiveMemory.createCognitiveVault()
            signer.storage.save(<- cognitiveVault, to: CognitiveMemory.CognitiveVaultStoragePath)
        }

        // 7. Create OracleConfig
        if signer.storage.type(at: InferenceOracle.OracleConfigStoragePath) == nil {
            let oracleConfig <- InferenceOracle.createOracleConfig()
            signer.storage.save(<- oracleConfig, to: InferenceOracle.OracleConfigStoragePath)
        }

        // 8. Create Scheduler
        if signer.storage.type(at: AgentScheduler.SchedulerStoragePath) == nil {
            let scheduler <- AgentScheduler.createScheduler(agentId: agentId)
            signer.storage.save(<- scheduler, to: AgentScheduler.SchedulerStoragePath)
        }

        // 9. Create HookManager
        if signer.storage.type(at: AgentLifecycleHooks.HookManagerStoragePath) == nil {
            let hookManager <- AgentLifecycleHooks.createHookManager()
            signer.storage.save(<- hookManager, to: AgentLifecycleHooks.HookManagerStoragePath)
        }

        // 10. Create ExtensionManager
        if signer.storage.type(at: AgentExtensions.ExtensionManagerStoragePath) == nil {
            let extensionManager <- AgentExtensions.createExtensionManager()
            signer.storage.save(<- extensionManager, to: AgentExtensions.ExtensionManagerStoragePath)
        }

        // 11. Create EncryptionConfig
        if signer.storage.type(at: AgentEncryption.EncryptionConfigStoragePath) == nil {
            let encryptionConfig <- AgentEncryption.createEncryptionConfig()
            signer.storage.save(<- encryptionConfig, to: AgentEncryption.EncryptionConfigStoragePath)
        }

        // 12. Create AgentStack orchestrator
        if signer.storage.type(at: FlowClaw.FlowClawStoragePath) == nil {
            let agentStack <- FlowClaw.createAgentStack(ownerAddress: ownerAddress, agentId: agentId)
            signer.storage.save(<- agentStack, to: FlowClaw.FlowClawStoragePath)
        }

        // 13. Auto-authorize owner as relay
        let oracleRef = signer.storage.borrow<auth(InferenceOracle.ManageRelays) &InferenceOracle.OracleConfig>(
            from: InferenceOracle.OracleConfigStoragePath
        )
        if oracleRef != nil {
            oracleRef!.authorizeRelay(relayAddress: ownerAddress, label: "self-relay")
        }
    }

    execute {
        log("FlowClaw account fully initialized with multi-agent collection + cognitive memory!")
    }
}
