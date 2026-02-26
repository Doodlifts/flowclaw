// ConversationSummarizer.cdc
// EXAMPLE EXTENSION: Composite extension that combines hooks + scheduling + memory.
//
// Automatically summarizes long conversations and stores summaries in memory.
// Demonstrates a "composite" extension that uses multiple FlowClaw subsystems.
//
// Behavior:
//   1. postInference hook: After every 10th message in a session, trigger summarization
//   2. Scheduled task: Also runs daily to summarize all active sessions
//   3. Stores summaries in AgentMemory with tag "conversation-summary"
//   4. When a new session starts, recalls relevant summaries for context
//
// This is the kind of feature that would require a significant PR in OpenClaw,
// touching the agent loop, memory system, and cron system. In FlowClaw,
// it's a standalone extension that any user can install.

import AgentLifecycleHooks from "../../contracts/AgentLifecycleHooks.cdc"
import AgentExtensions from "../../contracts/AgentExtensions.cdc"
import ToolRegistry from "../../contracts/ToolRegistry.cdc"

access(all) contract ConversationSummarizer {

    access(all) let EXTENSION_NAME: String
    access(all) let EXTENSION_VERSION: String

    access(all) fun getMetadata(author: Address): AgentExtensions.ExtensionMetadata {
        return AgentExtensions.ExtensionMetadata(
            extensionId: 0,
            name: self.EXTENSION_NAME,
            description: "Automatically summarizes long conversations and stores them in agent memory. Provides context continuity across sessions. Runs on postInference hook (every 10 messages) and daily scheduled task.",
            version: self.EXTENSION_VERSION,
            author: author,
            category: AgentExtensions.ExtensionCategory.composite,
            sourceHash: "sha256:ghi789...",
            requiredEntitlements: [
                AgentExtensions.RequiredEntitlement(
                    resource: "Hooks",
                    entitlement: "RegisterHooks",
                    reason: "Register postInference hook for message counting"
                ),
                AgentExtensions.RequiredEntitlement(
                    resource: "Session",
                    entitlement: "ReadOnly",
                    reason: "Read conversation history for summarization"
                ),
                AgentExtensions.RequiredEntitlement(
                    resource: "Memory",
                    entitlement: "Store",
                    reason: "Store conversation summaries"
                ),
                AgentExtensions.RequiredEntitlement(
                    resource: "Memory",
                    entitlement: "Recall",
                    reason: "Retrieve past summaries for context"
                ),
                AgentExtensions.RequiredEntitlement(
                    resource: "Scheduler",
                    entitlement: "Schedule",
                    reason: "Daily summary task"
                )
            ],
            dependencies: [],
            tags: ["memory", "summarization", "context", "productivity"],
            isAudited: false,
            toolDefinitions: [
                ToolRegistry.ToolDefinition(
                    name: "summarize_session",
                    description: "Manually trigger a conversation summary for a specific session",
                    category: "memory",
                    parameters: [
                        ToolRegistry.ToolParameter(
                            name: "session_id",
                            description: "Session to summarize",
                            type: "number",
                            required: true,
                            defaultValue: nil
                        )
                    ],
                    returnsDescription: "Summary text and memory ID where it was stored",
                    isAsync: true,
                    requiresApproval: false,
                    version: 1,
                    registeredBy: author
                )
            ],
            hookConfigs: [
                AgentLifecycleHooks.HookConfig(
                    phase: AgentLifecycleHooks.LifecyclePhase.postInference,
                    priority: 50,   // Low priority — runs after more critical hooks
                    failMode: AgentLifecycleHooks.FailMode.failOpen,  // Don't block inference if summary fails
                    timeoutSeconds: 30.0,
                    maxRetries: 0,  // No retry — will catch up on next trigger
                    retryBackoffSeconds: 0.0,
                    description: "Count messages and trigger summarization every 10th message",
                    scopeChannels: nil,
                    scopeTools: nil,
                    scopeSessionIds: nil
                ),
                AgentLifecycleHooks.HookConfig(
                    phase: AgentLifecycleHooks.LifecyclePhase.agentPreStart,
                    priority: 100,  // Medium priority — load context before agent runs
                    failMode: AgentLifecycleHooks.FailMode.failOpen,
                    timeoutSeconds: 15.0,
                    maxRetries: 1,
                    retryBackoffSeconds: 2.0,
                    description: "Load relevant conversation summaries into context on agent start",
                    scopeChannels: nil,
                    scopeTools: nil,
                    scopeSessionIds: nil
                )
            ]
        )
    }

    init() {
        self.EXTENSION_NAME = "conversation-summarizer"
        self.EXTENSION_VERSION = "1.0.0"
    }
}
