// get_hooks.cdc
// List all registered lifecycle hooks for an account.

import "AgentLifecycleHooks"

access(all) fun main(address: Address): [AgentLifecycleHooks.HookRegistration] {
    let account = getAuthAccount<auth(Storage) &Account>(address)
    if let hookManager = account.storage.borrow<&AgentLifecycleHooks.HookManager>(
        from: AgentLifecycleHooks.HookManagerStoragePath
    ) {
        return hookManager.getAllHooks()
    }
    return []
}
