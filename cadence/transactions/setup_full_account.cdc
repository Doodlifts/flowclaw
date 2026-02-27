// setup_full_account.cdc
// One-transaction account initialization for new FlowClaw accounts.
// Creates storage resources only — NO agent is created here.
// Agent creation happens separately after the user configures their LLM provider.
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

transaction {
    prepare(signer: auth(Storage, Capabilities) &Account) {
        let ownerAddress = signer.address

        // 1. Create empty AgentCollection (multi-agent support) — no agent yet
        if signer.storage.type(at: AgentRegistry.AgentCollectionStoragePath) == nil {
            let collection <- AgentRegistry.createAgentCollection()
            signer.storage.save(<- collection, to: AgentRegistry.AgentCollectionStoragePath)
        }

        // 2. Create SessionManager
        if signer.storage.type(at: AgentSession.SessionManagerStoragePath) == nil {
            let sessionManager <- AgentSession.createSessionManager()
            signer.storage.save(<- sessionManager, to: AgentSession.SessionManagerStoragePath)
        }

        // 3. Create ToolCollection with defaults
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

        // 4. Create MemoryVault
        if signer.storage.type(at: AgentMemory.MemoryVaultStoragePath) == nil {
            let memoryVault <- AgentMemory.createMemoryVault()
            signer.storage.save(<- memoryVault, to: AgentMemory.MemoryVaultStoragePath)
        }

        // 5. Create CognitiveVault (cognitive memory)
        if signer.storage.type(at: CognitiveMemory.CognitiveVaultStoragePath) == nil {
            let cognitiveVault <- CognitiveMemory.createCognitiveVault()
            signer.storage.save(<- cognitiveVault, to: CognitiveMemory.CognitiveVaultStoragePath)
        }

        // 6. Create OracleConfig
        if signer.storage.type(at: InferenceOracle.OracleConfigStoragePath) == nil {
            let oracleConfig <- InferenceOracle.createOracleConfig()
            signer.storage.save(<- oracleConfig, to: InferenceOracle.OracleConfigStoragePath)
        }

        // 7. Create HookManager
        if signer.storage.type(at: AgentLifecycleHooks.HookManagerStoragePath) == nil {
            let hookManager <- AgentLifecycleHooks.createHookManager()
            signer.storage.save(<- hookManager, to: AgentLifecycleHooks.HookManagerStoragePath)
        }

        // 8. Create ExtensionManager
        if signer.storage.type(at: AgentExtensions.ExtensionManagerStoragePath) == nil {
            let extensionManager <- AgentExtensions.createExtensionManager()
            signer.storage.save(<- extensionManager, to: AgentExtensions.ExtensionManagerStoragePath)
        }

        // 9. Create EncryptionConfig
        if signer.storage.type(at: AgentEncryption.EncryptionConfigStoragePath) == nil {
            let encryptionConfig <- AgentEncryption.createEncryptionConfig()
            signer.storage.save(<- encryptionConfig, to: AgentEncryption.EncryptionConfigStoragePath)
        }

        // 10. Create AgentStack orchestrator (agentId 0 = placeholder until agent is created)
        if signer.storage.type(at: FlowClaw.FlowClawStoragePath) == nil {
            let agentStack <- FlowClaw.createAgentStack(ownerAddress: ownerAddress, agentId: 0)
            signer.storage.save(<- agentStack, to: FlowClaw.FlowClawStoragePath)
        }

        // 11. Auto-authorize owner as relay
        let oracleRef = signer.storage.borrow<auth(InferenceOracle.ManageRelays) &InferenceOracle.OracleConfig>(
            from: InferenceOracle.OracleConfigStoragePath
        )
        if oracleRef != nil {
            oracleRef!.authorizeRelay(relayAddress: ownerAddress, label: "self-relay")
        }
    }

    execute {
        log("FlowClaw account storage initialized — ready for provider setup and agent creation!")
    }
}
