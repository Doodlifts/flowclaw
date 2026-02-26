// get_installed_extensions.cdc
// Retrieve all extensions installed on a user's agent.
// Returns which extensions the user has installed and their configuration status.

import "AgentExtensions"

access(all) struct InstalledExtensionsResult {
    access(all) let installedCount: Int
    access(all) let installed: [AgentExtensions.InstalledExtension]
    access(all) let enabled: [AgentExtensions.InstalledExtension]
    access(all) let disabled: [AgentExtensions.InstalledExtension]

    init(
        installedCount: Int,
        installed: [AgentExtensions.InstalledExtension],
        enabled: [AgentExtensions.InstalledExtension],
        disabled: [AgentExtensions.InstalledExtension]
    ) {
        self.installedCount = installedCount
        self.installed = installed
        self.enabled = enabled
        self.disabled = disabled
    }
}

access(all) fun main(address: Address): InstalledExtensionsResult {
    let account = getAuthAccount<auth(Storage) &Account>(address)

    var installed: [AgentExtensions.InstalledExtension] = []
    var enabled: [AgentExtensions.InstalledExtension] = []
    var disabled: [AgentExtensions.InstalledExtension] = []

    if let extensionManager = account.storage.borrow<&AgentExtensions.ExtensionManager>(
        from: AgentExtensions.ExtensionManagerStoragePath
    ) {
        installed = extensionManager.getInstalledExtensions()
        enabled = extensionManager.getEnabledExtensions()

        // Calculate disabled extensions
        for ext in installed {
            if !ext.isEnabled {
                disabled.append(ext)
            }
        }

        let installedCount = extensionManager.getInstalledCount()

        return InstalledExtensionsResult(
            installedCount: installedCount,
            installed: installed,
            enabled: enabled,
            disabled: disabled
        )
    }

    return InstalledExtensionsResult(installedCount: 0, installed: [], enabled: [], disabled: [])
}
