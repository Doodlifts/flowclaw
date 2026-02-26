// get_all_extensions.cdc
// Retrieve all published extensions from the global registry.
// Returns metadata for all extensions (both published and installation status).

import "AgentExtensions"

access(all) struct ExtensionCatalog {
    access(all) let totalExtensions: UInt64
    access(all) let extensions: [AgentExtensions.ExtensionMetadata]

    init(totalExtensions: UInt64, extensions: [AgentExtensions.ExtensionMetadata]) {
        self.totalExtensions = totalExtensions
        self.extensions = extensions
    }
}

access(all) fun main(): ExtensionCatalog {
    // Get the extension registry from the contract account
    let registryAddress = AgentExtensions.account

    // Access the public registry resource to list all published extensions
    // Note: The registry is stored in contract account storage
    let account = getAccount(registryAddress)

    // For now, we can query published extensions through events
    // In a full implementation, the registry would expose a public collection interface
    // This script demonstrates the intended structure

    var allExtensions: [AgentExtensions.ExtensionMetadata] = []

    // This would be populated from the registry's stored extensions
    // For the MVP, we return the total count and an empty array,
    // which will be populated when the registry is queried via the public interface

    return ExtensionCatalog(totalExtensions: AgentExtensions.totalExtensions, extensions: allExtensions)
}
