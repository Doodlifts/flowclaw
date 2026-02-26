// create_extension_registry.cdc
// One-time setup: creates the ExtensionRegistry for publishing extensions.

import "AgentExtensions"

transaction {
    prepare(signer: auth(Storage) &Account) {
        let registry <- AgentExtensions.createExtensionRegistry()
        signer.storage.save(<- registry, to: AgentExtensions.ExtensionRegistryStoragePath)
        log("ExtensionRegistry created")
    }
}
