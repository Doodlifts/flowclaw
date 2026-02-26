// install_extension.cdc
// Install an extension from the registry onto your agent.
// YOU control what runs on your agent — no one else.
//
// This transaction:
// 1. Looks up the extension in the global registry
// 2. Verifies you're okay with the required entitlements
// 3. Installs it on your ExtensionManager
// 4. Registers any tools it provides in your ToolCollection
// 5. Registers any hooks it provides in your HookManager

import "AgentExtensions"
import "ToolRegistry"
import "AgentLifecycleHooks"

transaction(extensionId: UInt64, config: {String: String}) {
    prepare(signer: auth(Storage) &Account) {
        // 1. Get the extension metadata from registry
        let registry = signer.storage.borrow<&AgentExtensions.ExtensionRegistry>(
            from: AgentExtensions.ExtensionRegistryStoragePath
        ) ?? panic("ExtensionRegistry not found.")

        let metadata = registry.getExtension(extensionId: extensionId)
            ?? panic("Extension not found in registry")

        // 2. Install on your ExtensionManager
        let extensionManager = signer.storage.borrow<
            auth(AgentExtensions.Install) &AgentExtensions.ExtensionManager
        >(
            from: AgentExtensions.ExtensionManagerStoragePath
        ) ?? panic("ExtensionManager not found. Run initialize_account first.")

        extensionManager.installExtension(metadata: metadata, config: config)

        // 3. Register any tools the extension provides
        if metadata.toolDefinitions.length > 0 {
            let toolCollection = signer.storage.borrow<
                auth(ToolRegistry.ManageTools) &ToolRegistry.ToolCollection
            >(
                from: ToolRegistry.ToolCollectionStoragePath
            ) ?? panic("ToolCollection not found.")

            for tool in metadata.toolDefinitions {
                toolCollection.registerTool(tool)
            }
            log("Registered ".concat(metadata.toolDefinitions.length.toString()).concat(" tools"))
        }

        // 4. Register any hooks the extension provides
        if metadata.hookConfigs.length > 0 {
            let hookManager = signer.storage.borrow<
                auth(AgentLifecycleHooks.RegisterHooks) &AgentLifecycleHooks.HookManager
            >(
                from: AgentLifecycleHooks.HookManagerStoragePath
            ) ?? panic("HookManager not found.")

            for hookConfig in metadata.hookConfigs {
                hookManager.registerHook(
                    config: hookConfig,
                    handlerHash: metadata.sourceHash
                )
            }
            log("Registered ".concat(metadata.hookConfigs.length.toString()).concat(" hooks"))
        }

        log("Extension '".concat(metadata.name).concat("' installed successfully"))
    }
}
