// register_hook.cdc
// Register a lifecycle hook for the agent.
// Maps to PR #12082's api.lifecycle.on("<phase>", handler, opts)

import "AgentLifecycleHooks"

transaction(
    phase: UInt8,
    priority: UInt8,
    failModeOpen: Bool,
    timeoutSeconds: UFix64,
    maxRetries: UInt8,
    description: String,
    handlerHash: String
) {
    prepare(signer: auth(Storage) &Account) {
        let hookManager = signer.storage.borrow<
            auth(AgentLifecycleHooks.RegisterHooks) &AgentLifecycleHooks.HookManager
        >(
            from: AgentLifecycleHooks.HookManagerStoragePath
        ) ?? panic("HookManager not found. Run initialize_account first.")

        let lifecyclePhase = AgentLifecycleHooks.LifecyclePhase(rawValue: phase)
            ?? panic("Invalid lifecycle phase")

        let failMode = failModeOpen
            ? AgentLifecycleHooks.FailMode.failOpen
            : AgentLifecycleHooks.FailMode.failClosed

        let config = AgentLifecycleHooks.HookConfig(
            phase: lifecyclePhase,
            priority: priority,
            failMode: failMode,
            timeoutSeconds: timeoutSeconds,
            maxRetries: maxRetries,
            retryBackoffSeconds: 2.0,
            description: description,
            scopeChannels: nil,
            scopeTools: nil,
            scopeSessionIds: nil
        )

        let hookId = hookManager.registerHook(
            config: config,
            handlerHash: handlerHash
        )

        log("Hook registered with ID: ".concat(hookId.toString()))
    }
}
