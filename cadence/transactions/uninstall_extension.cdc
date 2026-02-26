// uninstall_extension.cdc
// Remove an extension from your agent.

import "AgentExtensions"

transaction(extensionId: UInt64) {
    prepare(signer: auth(Storage) &Account) {
        let extensionManager = signer.storage.borrow<
            auth(AgentExtensions.Install) &AgentExtensions.ExtensionManager
        >(
            from: AgentExtensions.ExtensionManagerStoragePath
        ) ?? panic("ExtensionManager not found.")

        extensionManager.uninstallExtension(extensionId: extensionId)
        log("Extension uninstalled")
    }
}
