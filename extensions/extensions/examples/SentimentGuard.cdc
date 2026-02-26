// SentimentGuard.cdc
// EXAMPLE EXTENSION: A lifecycle hook that analyzes message sentiment
// before sending and can block negative/harmful responses.
//
// This demonstrates how a third-party developer can add behavior to
// FlowClaw WITHOUT modifying any base contracts, WITHOUT opening a PR,
// and WITHOUT needing maintainer approval.
//
// The extension:
//   1. Registers a preSend lifecycle hook
//   2. When the agent is about to send a message, the hook fires
//   3. The relay runs sentiment analysis on the response
//   4. If sentiment is below threshold, the response is blocked
//   5. The agent is asked to rephrase
//
// REQUIRED ENTITLEMENTS:
//   - Hooks: RegisterHooks (to install the preSend hook)
//   - Session: ReadOnly (to read the message being sent)
//
// The extension CANNOT:
//   - Read other sessions (scoped to specific sessions)
//   - Modify agent config (no Configure entitlement)
//   - Access memory (no Memory entitlements)
//   - Execute tools (no Execute entitlement)

import AgentLifecycleHooks from "../../contracts/AgentLifecycleHooks.cdc"
import AgentExtensions from "../../contracts/AgentExtensions.cdc"
import ToolRegistry from "../../contracts/ToolRegistry.cdc"

access(all) contract SentimentGuard {

    access(all) let EXTENSION_NAME: String
    access(all) let EXTENSION_VERSION: String

    // The metadata for publishing to the registry
    access(all) fun getMetadata(author: Address): AgentExtensions.ExtensionMetadata {
        return AgentExtensions.ExtensionMetadata(
            extensionId: 0,  // Assigned on publish
            name: self.EXTENSION_NAME,
            description: "Analyzes agent responses for sentiment before sending. Blocks negative or harmful messages and asks the agent to rephrase. Configurable threshold.",
            version: self.EXTENSION_VERSION,
            author: author,
            category: AgentExtensions.ExtensionCategory.hook,
            sourceHash: "sha256:abc123...",  // Hash of this contract's source
            requiredEntitlements: [
                AgentExtensions.RequiredEntitlement(
                    resource: "Hooks",
                    entitlement: "RegisterHooks",
                    reason: "Needs to register a preSend lifecycle hook"
                ),
                AgentExtensions.RequiredEntitlement(
                    resource: "Session",
                    entitlement: "ReadOnly",
                    reason: "Needs to read the message content for sentiment analysis"
                )
            ],
            dependencies: [],
            tags: ["safety", "sentiment", "moderation", "guardrail"],
            isAudited: false,
            toolDefinitions: [],
            hookConfigs: [
                AgentLifecycleHooks.HookConfig(
                    phase: AgentLifecycleHooks.LifecyclePhase.preSend,
                    priority: 200,  // High priority — runs before most other hooks
                    failMode: AgentLifecycleHooks.FailMode.failClosed,  // If analysis fails, block the send
                    timeoutSeconds: 10.0,
                    maxRetries: 1,
                    retryBackoffSeconds: 2.0,
                    description: "Sentiment analysis guard on outgoing messages",
                    scopeChannels: nil,  // All channels
                    scopeTools: nil,
                    scopeSessionIds: nil  // All sessions
                )
            ]
        )
    }

    init() {
        self.EXTENSION_NAME = "sentiment-guard"
        self.EXTENSION_VERSION = "1.0.0"
    }
}
