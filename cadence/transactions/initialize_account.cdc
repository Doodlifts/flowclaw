// initialize_account.cdc
// One-time setup: creates ALL FlowClaw resources in the signer's account.
// This gives the Flow account a complete private agent stack:
// Agent + SessionManager + ToolCollection + MemoryVault + OracleConfig
// + Scheduler + HookManager + ExtensionManager + AgentStack

import "AgentRegistry"
import "AgentSession"
import "InferenceOracle"
import "ToolRegistry"
import "AgentMemory"
import "AgentScheduler"
import "AgentLifecycleHooks"
import "AgentExtensions"
import "AgentEncryption"
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

        // 1. Create InferenceConfig
        let inferenceConfig = AgentRegistry.InferenceConfig(
            provider: provider,
            model: model,
            apiKeyHash: apiKeyHash,
            maxTokens: maxTokens,
            temperature: temperature,
            systemPrompt: systemPrompt
        )

        // 2. Create SecurityPolicy with defaults
        let securityPolicy = AgentRegistry.SecurityPolicy(
            autonomyLevel: autonomyLevel,
            maxActionsPerHour: maxActionsPerHour,
            maxCostPerDay: maxCostPerDay,
            allowedTools: ["memory_store", "memory_recall", "web_fetch", "flow_query"],
            deniedTools: ["shell_exec"]  // Denied by default for safety
        )

        // 3. Create Agent resource
        let agent <- AgentRegistry.createAgent(
            name: agentName,
            description: agentDescription,
            ownerAddress: ownerAddress,
            inferenceConfig: inferenceConfig,
            securityPolicy: securityPolicy
        )
        let agentId = agent.id
        signer.storage.save(<- agent, to: AgentRegistry.AgentStoragePath)

        // 4. Create SessionManager
        let sessionManager <- AgentSession.createSessionManager()
        signer.storage.save(<- sessionManager, to: AgentSession.SessionManagerStoragePath)

        // 5. Create ToolCollection — save first so self.owner is set,
        //    then borrow back to register default tools
        let toolCollection <- ToolRegistry.createToolCollection()
        signer.storage.save(<- toolCollection, to: ToolRegistry.ToolCollectionStoragePath)

        let toolRef = signer.storage.borrow<auth(ToolRegistry.ManageTools) &ToolRegistry.ToolCollection>(
            from: ToolRegistry.ToolCollectionStoragePath
        )!
        let defaultTools = ToolRegistry.getDefaultTools(registeredBy: ownerAddress)
        for tool in defaultTools {
            toolRef.registerTool(tool)
        }

        // 6. Create MemoryVault
        let memoryVault <- AgentMemory.createMemoryVault()
        signer.storage.save(<- memoryVault, to: AgentMemory.MemoryVaultStoragePath)

        // 7. Create OracleConfig (relay authorization)
        let oracleConfig <- InferenceOracle.createOracleConfig()
        signer.storage.save(<- oracleConfig, to: InferenceOracle.OracleConfigStoragePath)

        // 8. Create Scheduler (replaces OpenClaw cron)
        let scheduler <- AgentScheduler.createScheduler(agentId: agentId)
        signer.storage.save(<- scheduler, to: AgentScheduler.SchedulerStoragePath)

        // 9. Create HookManager (lifecycle interception from PR #12082)
        let hookManager <- AgentLifecycleHooks.createHookManager()
        signer.storage.save(<- hookManager, to: AgentLifecycleHooks.HookManagerStoragePath)

        // 10. Create ExtensionManager (permissionless plugin system)
        let extensionManager <- AgentExtensions.createExtensionManager()
        signer.storage.save(<- extensionManager, to: AgentExtensions.ExtensionManagerStoragePath)

        // 11. Create EncryptionConfig (E2E encrypted messages)
        let encryptionConfig <- AgentEncryption.createEncryptionConfig()
        signer.storage.save(<- encryptionConfig, to: AgentEncryption.EncryptionConfigStoragePath)

        // 12. Create AgentStack orchestrator
        let agentStack <- FlowClaw.createAgentStack(ownerAddress: ownerAddress, agentId: agentId)
        signer.storage.save(<- agentStack, to: FlowClaw.FlowClawStoragePath)

        // Auto-authorize owner as their own relay (for local relay setup)
        let oracleRef = signer.storage.borrow<auth(InferenceOracle.ManageRelays) &InferenceOracle.OracleConfig>(
            from: InferenceOracle.OracleConfigStoragePath
        )!
        oracleRef.authorizeRelay(relayAddress: ownerAddress, label: "self-relay")
    }

    execute {
        log("FlowClaw account initialized with all 10 resource types!")
    }
}
