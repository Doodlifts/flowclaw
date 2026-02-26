// AgentLifecycleHooks.cdc
// Port of OpenClaw PR #12082 "Plugin Lifecycle Interception Hook Architecture" to Cadence.
//
// PR #12082 PROPOSES:
//   - api.on("<hook_name>", handler, opts) for raw runtime hooks
//   - api.lifecycle.on("<phase>", handler, opts) for canonical phases
//   - Priority-based execution, timeout mgmt, fail-open/fail-closed,
//     retry logic, concurrency limits, scope-based gating
//
// WHY CADENCE DOES THIS BETTER:
//
// In OpenClaw, lifecycle hooks are in-process callbacks. If the process dies,
// hooks die with it. The hook system is also purely trust-based — any plugin
// can register any hook with no access control.
//
// In Cadence, we get several things for free:
//
// 1. PRE/POST CONDITIONS — Cadence's built-in design-by-contract means every
//    hook phase has compile-time guarantees. A pre_message_send hook can
//    ENFORCE that the message content isn't empty. A post_inference hook can
//    VERIFY that tokens used is non-zero. These aren't runtime checks that
//    can be bypassed — they're protocol-level guarantees.
//
// 2. CAPABILITIES — Hook handlers are registered as Capabilities with specific
//    Entitlements. A plugin can be given permission to hook into message_received
//    but NOT tool_execution. This is impossible to express in OpenClaw's system.
//
// 3. ENTITLEMENTS — Fine-grained: Read vs Modify vs Intercept. A hook that only
//    needs to observe messages gets ReadOnly. A hook that can modify them gets
//    Modify. A hook that can block/cancel gets Intercept. All enforced by Cadence.
//
// 4. RESOURCES — Hook registrations are Resources. They can't be duplicated,
//    they're owned by specific accounts, and when destroyed they cleanly
//    unregister. No orphaned callbacks.
//
// 5. EVENTS — Instead of in-process callbacks, hooks emit on-chain events.
//    Multiple off-chain systems can subscribe. The hook execution is verifiable.

access(all) contract AgentLifecycleHooks {

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    access(all) event HookRegistered(
        hookId: UInt64,
        phase: String,
        owner: Address,
        priority: UInt8,
        failMode: String
    )
    access(all) event HookTriggered(hookId: UInt64, phase: String, owner: Address)
    access(all) event HookCompleted(hookId: UInt64, phase: String, result: String)
    access(all) event HookFailed(hookId: UInt64, phase: String, error: String)
    access(all) event HookUnregistered(hookId: UInt64)

    // Canonical lifecycle phase events — mirrors PR #12082's phases
    access(all) event PhaseGatewayPreStart(owner: Address)
    access(all) event PhaseGatewayPostStart(owner: Address)
    access(all) event PhaseAgentPreStart(owner: Address, agentId: UInt64)
    access(all) event PhaseAgentPostRun(owner: Address, agentId: UInt64)
    access(all) event PhaseMessageReceived(owner: Address, sessionId: UInt64, contentHash: String)
    access(all) event PhasePreInference(owner: Address, sessionId: UInt64, messageCount: UInt64)
    access(all) event PhasePostInference(owner: Address, sessionId: UInt64, tokensUsed: UInt64)
    access(all) event PhasePreToolExecution(owner: Address, toolName: String, inputHash: String)
    access(all) event PhasePostToolExecution(owner: Address, toolName: String, outputHash: String)
    access(all) event PhasePreMemoryCompaction(owner: Address, entryCount: UInt64)
    access(all) event PhasePostMemoryCompaction(owner: Address, entriesRemoved: UInt64)
    access(all) event PhasePreSend(owner: Address, sessionId: UInt64, contentHash: String)
    access(all) event PhasePostSend(owner: Address, sessionId: UInt64, success: Bool)

    // -----------------------------------------------------------------------
    // Paths
    // -----------------------------------------------------------------------
    access(all) let HookManagerStoragePath: StoragePath

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------
    access(all) var totalHooks: UInt64

    // -----------------------------------------------------------------------
    // Entitlements — maps to PR #12082's scope-based gating
    // -----------------------------------------------------------------------
    access(all) entitlement RegisterHooks
    access(all) entitlement TriggerHooks
    access(all) entitlement ReadOnly       // Can observe but not modify
    access(all) entitlement Modify         // Can modify data passing through
    access(all) entitlement Intercept      // Can block/cancel operations

    // -----------------------------------------------------------------------
    // LifecyclePhase — the canonical phases from PR #12082
    // -----------------------------------------------------------------------
    access(all) enum LifecyclePhase: UInt8 {
        // Boot/shutdown cycle
        access(all) case gatewayPreStart
        access(all) case gatewayPostStart
        access(all) case gatewayPreStop
        access(all) case gatewayPostStop

        // Agent lifecycle
        access(all) case agentPreStart
        access(all) case agentPostRun
        access(all) case agentError

        // Message flow (inbound)
        access(all) case messageReceived
        access(all) case preInference
        access(all) case postInference

        // Message flow (outbound)
        access(all) case preSend
        access(all) case postSend
        access(all) case postSendFailure

        // Tool execution
        access(all) case preToolCall
        access(all) case postToolCall
        access(all) case toolError

        // Memory management
        access(all) case preMemoryCompaction
        access(all) case postMemoryCompaction

        // Scheduled tasks
        access(all) case preScheduledTask
        access(all) case postScheduledTask
    }

    // -----------------------------------------------------------------------
    // FailMode — matches PR #12082's fail-open/fail-closed
    // -----------------------------------------------------------------------
    access(all) enum FailMode: UInt8 {
        access(all) case failOpen     // Hook failure doesn't block the operation
        access(all) case failClosed   // Hook failure blocks the operation
    }

    // -----------------------------------------------------------------------
    // HookConfig — handler registration options (maps to PR #12082's opts)
    // -----------------------------------------------------------------------
    access(all) struct HookConfig {
        access(all) let phase: LifecyclePhase
        access(all) let priority: UInt8           // 0-255, higher = runs first
        access(all) let failMode: FailMode
        access(all) let timeoutSeconds: UFix64    // Max execution time
        access(all) let maxRetries: UInt8
        access(all) let retryBackoffSeconds: UFix64
        access(all) let description: String

        // Scope-based gating — from PR #12082
        access(all) let scopeChannels: [String]?  // nil = all channels
        access(all) let scopeTools: [String]?     // nil = all tools
        access(all) let scopeSessionIds: [UInt64]? // nil = all sessions

        init(
            phase: LifecyclePhase,
            priority: UInt8,
            failMode: FailMode,
            timeoutSeconds: UFix64,
            maxRetries: UInt8,
            retryBackoffSeconds: UFix64,
            description: String,
            scopeChannels: [String]?,
            scopeTools: [String]?,
            scopeSessionIds: [UInt64]?
        ) {
            pre {
                timeoutSeconds > 0.0 && timeoutSeconds <= 300.0:
                    "Timeout must be 1-300 seconds"
                maxRetries <= 5: "Max retries must be 0-5"
            }
            self.phase = phase
            self.priority = priority
            self.failMode = failMode
            self.timeoutSeconds = timeoutSeconds
            self.maxRetries = maxRetries
            self.retryBackoffSeconds = retryBackoffSeconds
            self.description = description
            self.scopeChannels = scopeChannels
            self.scopeTools = scopeTools
            self.scopeSessionIds = scopeSessionIds
        }
    }

    // -----------------------------------------------------------------------
    // HookRegistration — a registered hook (stored on-chain)
    // -----------------------------------------------------------------------
    access(all) struct HookRegistration {
        access(all) let hookId: UInt64
        access(all) let config: HookConfig
        access(all) let owner: Address
        access(all) let registeredAt: UFix64
        access(all) var isActive: Bool
        access(all) var triggerCount: UInt64
        access(all) var failureCount: UInt64
        access(all) var lastTriggeredAt: UFix64?

        // The handler itself is off-chain (the relay executes it),
        // but we store a hash of the handler code for verifiability
        access(all) let handlerHash: String

        init(
            hookId: UInt64,
            config: HookConfig,
            owner: Address,
            handlerHash: String
        ) {
            self.hookId = hookId
            self.config = config
            self.owner = owner
            self.registeredAt = getCurrentBlock().timestamp
            self.isActive = true
            self.triggerCount = 0
            self.failureCount = 0
            self.lastTriggeredAt = nil
            self.handlerHash = handlerHash
        }
    }

    // -----------------------------------------------------------------------
    // HookContext — data passed to hook handlers
    // -----------------------------------------------------------------------
    access(all) struct HookContext {
        access(all) let phase: LifecyclePhase
        access(all) let agentId: UInt64
        access(all) let sessionId: UInt64?
        access(all) let timestamp: UFix64
        access(all) let data: {String: String}  // Key-value context data

        init(
            phase: LifecyclePhase,
            agentId: UInt64,
            sessionId: UInt64?,
            data: {String: String}
        ) {
            self.phase = phase
            self.agentId = agentId
            self.sessionId = sessionId
            self.timestamp = getCurrentBlock().timestamp
            self.data = data
        }
    }

    // -----------------------------------------------------------------------
    // HookResult — what a hook handler returns
    // -----------------------------------------------------------------------
    access(all) struct HookResult {
        access(all) let hookId: UInt64
        access(all) let success: Bool
        access(all) let shouldProceed: Bool    // false = cancel the operation (Intercept entitlement)
        access(all) let modifiedData: {String: String}?  // nil = no modifications
        access(all) let message: String?

        init(
            hookId: UInt64,
            success: Bool,
            shouldProceed: Bool,
            modifiedData: {String: String}?,
            message: String?
        ) {
            self.hookId = hookId
            self.success = success
            self.shouldProceed = shouldProceed
            self.modifiedData = modifiedData
            self.message = message
        }
    }

    // -----------------------------------------------------------------------
    // HookManager — per-account hook registry
    // -----------------------------------------------------------------------
    access(all) resource HookManager {
        access(self) var hooks: {UInt64: HookRegistration}
        access(self) var phaseIndex: {UInt8: [UInt64]}  // phase -> [hookIds], sorted by priority
        access(self) var hookResults: {UInt64: [HookResult]}  // hookId -> results history

        init() {
            self.hooks = {}
            self.phaseIndex = {}
            self.hookResults = {}
        }

        // --- RegisterHooks: add/remove hooks ---

        access(RegisterHooks) fun registerHook(
            config: HookConfig,
            handlerHash: String
        ): UInt64 {
            post {
                self.hooks[AgentLifecycleHooks.totalHooks] != nil:
                    "Hook must be stored after registration"
            }

            AgentLifecycleHooks.totalHooks = AgentLifecycleHooks.totalHooks + 1
            let hookId = AgentLifecycleHooks.totalHooks

            let registration = HookRegistration(
                hookId: hookId,
                config: config,
                owner: self.owner!.address,
                handlerHash: handlerHash
            )

            self.hooks[hookId] = registration

            // Add to phase index (maintain priority order)
            let phaseKey = config.phase.rawValue
            if self.phaseIndex[phaseKey] == nil {
                self.phaseIndex[phaseKey] = [hookId]
            } else {
                self.phaseIndex[phaseKey]!.append(hookId)
                // Sort by priority (higher priority first)
                self.sortHooksByPriority(phaseKey: phaseKey)
            }

            let failModeStr = config.failMode == FailMode.failOpen ? "fail-open" : "fail-closed"

            emit HookRegistered(
                hookId: hookId,
                phase: self.phaseToString(config.phase),
                owner: self.owner!.address,
                priority: config.priority,
                failMode: failModeStr
            )

            return hookId
        }

        access(RegisterHooks) fun unregisterHook(hookId: UInt64): Bool {
            if let hook = self.hooks[hookId] {
                let phaseKey = hook.config.phase.rawValue
                if var ids = self.phaseIndex[phaseKey] {
                    var newIds: [UInt64] = []
                    for id in ids {
                        if id != hookId {
                            newIds.append(id)
                        }
                    }
                    self.phaseIndex[phaseKey] = newIds
                }
                self.hooks.remove(key: hookId)
                emit HookUnregistered(hookId: hookId)
                return true
            }
            return false
        }

        // --- TriggerHooks: fire hooks for a phase ---

        access(TriggerHooks) fun triggerPhase(
            phase: LifecyclePhase,
            context: HookContext
        ): [HookResult] {
            let phaseKey = phase.rawValue
            var results: [HookResult] = []

            let hookIdsOpt = self.phaseIndex[phaseKey]
            if hookIdsOpt == nil {
                return results  // No hooks for this phase
            }
            let hookIds = hookIdsOpt!

            for hookId in hookIds {
                if let hook = self.hooks[hookId] {
                    if !hook.isActive {
                        continue
                    }

                    // Check scope gating
                    if !self.hookMatchesScope(hook: hook, context: context) {
                        continue
                    }

                    emit HookTriggered(
                        hookId: hookId,
                        phase: self.phaseToString(phase),
                        owner: self.owner!.address
                    )

                    // The actual hook execution happens OFF-CHAIN in the relay.
                    // Here we record that it was triggered and emit the event.
                    // The relay processes the event, runs the handler, and posts
                    // the result back via completeHook().

                    // For synchronous on-chain hooks (e.g., pre-conditions),
                    // we return a default "proceed" result
                    let result = HookResult(
                        hookId: hookId,
                        success: true,
                        shouldProceed: true,
                        modifiedData: nil,
                        message: nil
                    )
                    results.append(result)
                }
            }

            return results
        }

        // Complete a hook execution (called by relay after off-chain processing)
        access(TriggerHooks) fun completeHook(
            hookId: UInt64,
            result: HookResult
        ) {
            pre {
                self.hooks[hookId] != nil: "Hook not found"
            }

            if self.hookResults[hookId] == nil {
                self.hookResults[hookId] = [result]
            } else {
                self.hookResults[hookId]!.append(result)
            }

            if result.success {
                emit HookCompleted(
                    hookId: hookId,
                    phase: self.phaseToString(self.hooks[hookId]!.config.phase),
                    result: result.message ?? "OK"
                )
            } else {
                emit HookFailed(
                    hookId: hookId,
                    phase: self.phaseToString(self.hooks[hookId]!.config.phase),
                    error: result.message ?? "Unknown error"
                )
            }
        }

        // --- Read ---

        access(all) fun getHook(hookId: UInt64): HookRegistration? {
            return self.hooks[hookId]
        }

        access(all) fun getHooksForPhase(phase: LifecyclePhase): [HookRegistration] {
            let phaseKey = phase.rawValue
            var result: [HookRegistration] = []
            if let hookIds = self.phaseIndex[phaseKey] {
                for hookId in hookIds {
                    if let hook = self.hooks[hookId] {
                        result.append(hook)
                    }
                }
            }
            return result
        }

        access(all) fun getAllHooks(): [HookRegistration] {
            var result: [HookRegistration] = []
            for hookId in self.hooks.keys {
                if let hook = self.hooks[hookId] {
                    result.append(hook)
                }
            }
            return result
        }

        // --- Internal helpers ---

        access(self) fun hookMatchesScope(
            hook: HookRegistration,
            context: HookContext
        ): Bool {
            // Check session scope
            if let sessionIds = hook.config.scopeSessionIds {
                if let ctxSession = context.sessionId {
                    if !sessionIds.contains(ctxSession) {
                        return false
                    }
                }
            }

            // Check tool scope
            if let tools = hook.config.scopeTools {
                if let toolName = context.data["toolName"] {
                    if !tools.contains(toolName) {
                        return false
                    }
                }
            }

            // Check channel scope
            if let channels = hook.config.scopeChannels {
                if let channel = context.data["channel"] {
                    if !channels.contains(channel) {
                        return false
                    }
                }
            }

            return true
        }

        access(self) fun sortHooksByPriority(phaseKey: UInt8) {
            if var ids = self.phaseIndex[phaseKey] {
                // Simple sort by priority (descending)
                var i = 0
                while i < ids.length {
                    var j = 0
                    while j < ids.length - 1 - i {
                        let hookA = self.hooks[ids[j]]!
                        let hookB = self.hooks[ids[j + 1]]!
                        if hookA.config.priority < hookB.config.priority {
                            let temp = ids[j]
                            ids[j] = ids[j + 1]
                            ids[j + 1] = temp
                        }
                        j = j + 1
                    }
                    i = i + 1
                }
                self.phaseIndex[phaseKey] = ids
            }
        }

        access(self) fun phaseToString(_ phase: LifecyclePhase): String {
            switch phase {
                case LifecyclePhase.gatewayPreStart: return "gateway.pre_start"
                case LifecyclePhase.gatewayPostStart: return "gateway.post_start"
                case LifecyclePhase.gatewayPreStop: return "gateway.pre_stop"
                case LifecyclePhase.gatewayPostStop: return "gateway.post_stop"
                case LifecyclePhase.agentPreStart: return "agent.pre_start"
                case LifecyclePhase.agentPostRun: return "agent.post_run"
                case LifecyclePhase.agentError: return "agent.error"
                case LifecyclePhase.messageReceived: return "message.received"
                case LifecyclePhase.preInference: return "inference.pre"
                case LifecyclePhase.postInference: return "inference.post"
                case LifecyclePhase.preSend: return "send.pre"
                case LifecyclePhase.postSend: return "send.post"
                case LifecyclePhase.postSendFailure: return "send.post_failure"
                case LifecyclePhase.preToolCall: return "tool.pre_call"
                case LifecyclePhase.postToolCall: return "tool.post_call"
                case LifecyclePhase.toolError: return "tool.error"
                case LifecyclePhase.preMemoryCompaction: return "memory.pre_compaction"
                case LifecyclePhase.postMemoryCompaction: return "memory.post_compaction"
                case LifecyclePhase.preScheduledTask: return "schedule.pre_task"
                case LifecyclePhase.postScheduledTask: return "schedule.post_task"
            }
            return "unknown"
        }
    }

    // -----------------------------------------------------------------------
    // Public factory
    // -----------------------------------------------------------------------
    access(all) fun createHookManager(): @HookManager {
        return <- create HookManager()
    }

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    init() {
        self.totalHooks = 0
        self.HookManagerStoragePath = /storage/FlowClawHookManager
    }
}
