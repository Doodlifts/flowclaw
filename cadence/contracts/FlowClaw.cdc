// FlowClaw.cdc
// Main orchestrator contract — the agentic harness on Flow.
// Ties together AgentRegistry, AgentSession, InferenceOracle, ToolRegistry, and AgentMemory.
// Each Flow account gets a complete, private agent stack.
//
// Architecture:
// ┌──────────────────────────────────────────────────────┐
// │  Flow Account (Owner)                                │
// │  ┌─────────────┐  ┌──────────────┐  ┌────────────┐  │
// │  │   Agent      │  │  Sessions    │  │  Memory    │  │
// │  │  (Resource)  │  │  (Resource)  │  │  (Resource)│  │
// │  │             │  │              │  │            │  │
// │  │ - config    │  │ - history    │  │ - k/v store│  │
// │  │ - security  │  │ - messages   │  │ - tags     │  │
// │  │ - rate lim  │  │ - inference  │  │ - search   │  │
// │  └─────────────┘  └──────────────┘  └────────────┘  │
// │  ┌──────────────┐  ┌──────────────┐                  │
// │  │  Tools       │  │  Oracle      │                  │
// │  │  (Resource)  │  │  Config      │                  │
// │  │             │  │  (Resource)  │                  │
// │  │ - registry  │  │ - relays     │                  │
// │  │ - exec log  │  │ - dedup      │                  │
// │  └──────────────┘  └──────────────┘                  │
// └──────────────────────────────────────────────────────┘
//           │ Events ↓            ↑ Transactions
// ┌──────────────────────────────────────────────────────┐
// │  Off-Chain Inference Relay (per-account)             │
// │  - Listens for InferenceRequested events             │
// │  - Calls LLM provider with account's config         │
// │  - Posts results back via completeInference tx       │
// │  - Executes tool calls in sandboxed environment      │
// └──────────────────────────────────────────────────────┘

import "AgentRegistry"
import "AgentSession"
import "InferenceOracle"
import "ToolRegistry"
import "AgentMemory"

access(all) contract FlowClaw {

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    access(all) event AccountInitialized(owner: Address, agentId: UInt64)
    access(all) event AgentLoopStarted(agentId: UInt64, sessionId: UInt64, owner: Address)
    access(all) event AgentLoopCompleted(agentId: UInt64, sessionId: UInt64, turnsUsed: UInt64)
    access(all) event UserMessageSent(sessionId: UInt64, contentHash: String)
    access(all) event AgentResponseReceived(sessionId: UInt64, contentHash: String)

    // -----------------------------------------------------------------------
    // Paths
    // -----------------------------------------------------------------------
    access(all) let FlowClawStoragePath: StoragePath

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------
    access(all) var totalAccounts: UInt64
    access(all) var totalMessages: UInt64
    access(all) let version: String

    // -----------------------------------------------------------------------
    // Entitlements
    // -----------------------------------------------------------------------
    access(all) entitlement Owner
    access(all) entitlement Operate

    // -----------------------------------------------------------------------
    // AgentStack — the complete per-account agent infrastructure
    // -----------------------------------------------------------------------
    access(all) resource AgentStack {
        access(all) let agentId: UInt64
        access(all) var isInitialized: Bool

        // References to the per-account resources (stored separately)
        // The AgentStack coordinates between them

        init(agentId: UInt64) {
            self.agentId = agentId
            self.isInitialized = true
        }

        // --- Send a user message and request inference ---
        // This is the main entry point for the agentic loop
        access(Operate) fun sendMessage(
            sessionManager: auth(AgentSession.Manage) &AgentSession.SessionManager,
            agent: auth(AgentRegistry.Execute) &AgentRegistry.Agent,
            sessionId: UInt64,
            content: String,
            contentHash: String
        ): UInt64? {
            // 1. Validate agent is active and within rate limits
            if !agent.isActive {
                return nil
            }
            if !agent.checkRateLimits() {
                return nil
            }

            // 2. Get session
            let session = sessionManager.borrowSession(sessionId: sessionId)
                ?? panic("Session not found")

            // 3. Add user message to session
            session.addMessage(
                role: "user",
                content: content,
                contentHash: contentHash,
                toolName: nil,
                toolCallId: nil,
                tokensEstimate: UInt64(content.length / 4) // rough estimate
            )

            FlowClaw.totalMessages = FlowClaw.totalMessages + 1
            emit UserMessageSent(sessionId: sessionId, contentHash: contentHash)

            // 4. Request inference — emits event for relay
            let requestId = session.requestInference(
                agentRef: agent,
                messagesHash: contentHash
            )

            emit AgentLoopStarted(
                agentId: self.agentId,
                sessionId: sessionId,
                owner: self.owner!.address
            )

            return requestId
        }

        // --- Complete an inference (called by relay transaction) ---
        access(Operate) fun completeInference(
            sessionManager: auth(AgentSession.Manage) &AgentSession.SessionManager,
            agent: auth(AgentRegistry.Execute) &AgentRegistry.Agent,
            oracleConfig: auth(InferenceOracle.Relay) &InferenceOracle.OracleConfig,
            sessionId: UInt64,
            requestId: UInt64,
            responseContent: String,
            responseHash: String,
            tokensUsed: UInt64,
            relayAddress: Address
        ) {
            // 1. Verify relay is authorized for this account
            assert(
                oracleConfig.isRelayAuthorized(relayAddress: relayAddress),
                message: "Relay not authorized for this account"
            )

            // 2. Verify request hasn't already been completed (dedup)
            assert(
                !oracleConfig.isRequestCompleted(requestId: requestId),
                message: "Request already completed"
            )

            // 3. Get session and complete inference
            let session = sessionManager.borrowSession(sessionId: sessionId)
                ?? panic("Session not found")

            session.completeInference(
                requestId: requestId,
                responseContent: responseContent,
                responseHash: responseHash,
                tokensUsed: tokensUsed
            )

            // 4. Mark as completed in oracle (dedup)
            oracleConfig.markRequestCompleted(requestId: requestId)

            // 5. Record cost (rough estimate: $0.001 per 1000 tokens)
            let costEstimate = UFix64(tokensUsed) * 0.000001
            agent.recordCost(amount: costEstimate)

            FlowClaw.totalMessages = FlowClaw.totalMessages + 1

            emit AgentResponseReceived(sessionId: sessionId, contentHash: responseHash)
        }

        // --- Process tool call result from relay ---
        access(Operate) fun processToolResult(
            sessionManager: auth(AgentSession.Manage) &AgentSession.SessionManager,
            toolCollection: auth(ToolRegistry.ExecuteTools) &ToolRegistry.ToolCollection,
            sessionId: UInt64,
            toolCallId: String,
            toolName: String,
            output: String,
            outputHash: String,
            agentId: UInt64,
            executionTimeMs: UInt64
        ) {
            // 1. Log the execution
            toolCollection.logExecution(
                toolName: toolName,
                agentId: agentId,
                sessionId: sessionId,
                inputHash: toolCallId,
                outputHash: outputHash,
                status: 1, // completed
                executionTimeMs: executionTimeMs
            )

            // 2. Add tool result to session as a message
            let session = sessionManager.borrowSession(sessionId: sessionId)
                ?? panic("Session not found")

            session.addMessage(
                role: "tool",
                content: output,
                contentHash: outputHash,
                toolName: toolName,
                toolCallId: toolCallId,
                tokensEstimate: UInt64(output.length / 4)
            )
        }

        // --- Store to memory (on-chain) ---
        access(Operate) fun storeMemory(
            memoryVault: auth(AgentMemory.Store) &AgentMemory.MemoryVault,
            key: String,
            content: String,
            contentHash: String,
            tags: [String],
            source: String
        ): UInt64 {
            return memoryVault.store(
                key: key,
                content: content,
                contentHash: contentHash,
                tags: tags,
                source: source
            )
        }

        // --- Recall from memory ---
        access(Operate) fun recallMemory(
            memoryVault: auth(AgentMemory.Recall) &AgentMemory.MemoryVault,
            key: String
        ): AgentMemory.MemoryEntry? {
            return memoryVault.getByKey(key: key)
        }

        access(Operate) fun recallMemoryByTag(
            memoryVault: auth(AgentMemory.Recall) &AgentMemory.MemoryVault,
            tag: String
        ): [AgentMemory.MemoryEntry] {
            return memoryVault.getByTag(tag: tag)
        }
    }

    // -----------------------------------------------------------------------
    // AccountStatus — public view of a FlowClaw account
    // -----------------------------------------------------------------------
    access(all) struct AccountStatus {
        access(all) let owner: Address
        access(all) let agentInfo: AgentRegistry.AgentPublicInfo
        access(all) let sessionCount: Int
        access(all) let memoryCount: UInt64
        access(all) let toolCount: Int
        access(all) let isRelayConfigured: Bool

        init(
            owner: Address,
            agentInfo: AgentRegistry.AgentPublicInfo,
            sessionCount: Int,
            memoryCount: UInt64,
            toolCount: Int,
            isRelayConfigured: Bool
        ) {
            self.owner = owner
            self.agentInfo = agentInfo
            self.sessionCount = sessionCount
            self.memoryCount = memoryCount
            self.toolCount = toolCount
            self.isRelayConfigured = isRelayConfigured
        }
    }

    // -----------------------------------------------------------------------
    // Public factory
    // -----------------------------------------------------------------------
    access(all) fun createAgentStack(ownerAddress: Address, agentId: UInt64): @AgentStack {
        self.totalAccounts = self.totalAccounts + 1
        let stack <- create AgentStack(agentId: agentId)
        emit AccountInitialized(owner: ownerAddress, agentId: agentId)
        return <- stack
    }

    // -----------------------------------------------------------------------
    // Version info
    // -----------------------------------------------------------------------
    access(all) fun getVersion(): String {
        return self.version
    }

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    init() {
        self.totalAccounts = 0
        self.totalMessages = 0
        self.version = "0.1.0-alpha"
        self.FlowClawStoragePath = /storage/FlowClawStack
    }
}
