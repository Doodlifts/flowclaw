// publish_extension.cdc
// Publish an extension to the global registry.
// Anyone can publish — no maintainer approval needed.
// Users decide what to install on their own agents.

import "AgentExtensions"
import "ToolRegistry"
import "AgentLifecycleHooks"

transaction(
    name: String,
    description: String,
    version: String,
    category: UInt8,
    sourceHash: String,
    tags: [String]
) {
    prepare(signer: auth(Storage) &Account) {
        // Borrow or create the global registry
        // (In production, the registry would be deployed once on a known account)
        let registry = signer.storage.borrow<auth(AgentExtensions.Publish) &AgentExtensions.ExtensionRegistry>(
            from: AgentExtensions.ExtensionRegistryStoragePath
        ) ?? panic("ExtensionRegistry not found.")

        let extensionCategory = AgentExtensions.ExtensionCategory(rawValue: category)
            ?? panic("Invalid extension category")

        let extensionId = registry.publishExtension(
            name: name,
            description: description,
            version: version,
            author: signer.address,
            category: extensionCategory,
            sourceHash: sourceHash,
            requiredEntitlements: [],
            dependencies: [],
            tags: tags,
            toolDefinitions: [],
            hookConfigs: []
        )

        log("Extension published with ID: ".concat(extensionId.toString()))
    }
}
