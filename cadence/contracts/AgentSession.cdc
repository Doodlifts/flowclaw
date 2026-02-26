// AgentSession.cdc
// Manages conversation sessions for agents on Flow.
// Each session is a Resource owned by the account — sessions are private by default.
// Supports multi-turn conversations, context windowing, and session compaction.

import "AgentRegistry"

access(all) contract AgentSession {

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    access(all) event SessionCreated(sessionId: UInt64, agentId: UInt64, owner: Address)
    access(all) event MessageAdded(sessionId: UInt64, role: String, contentHash: String)
    access(all) event SessionCompacted(sessionId: UInt64, messagesRemoved: UInt64)
    access(all) event SessionClosed(sessionId: UInt64)
    access(all) event InferenceRequested(
        requestId: UInt64,
        sessionId: UInt64,
        agentId: UInt64,
        owner: Address,
        provider: String,
        model: String,
        contentHash: String
    )
    access(all) event InferenceCompleted(
        requestId: UInt64,
        sessionId: UInt64,
        responseHash: String,
        tokensUsed: UInt64
    )

    // -----------------------------------------------------------------------
    // Paths
    // -----------------------------------------------------------------------
    access(all) let SessionManagerStoragePath: StoragePath

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------
    access(all) var totalSessions: UInt64
    access(all) var totalInferenceRequests: UInt64

    // -----------------------------------------------------------------------
    // Entitlements
    // -----------------------------------------------------------------------
    access(all) entitlement Manage
    access(all) entitlement ReadHistory

    // -----------------------------------------------------------------------
    // Message — a single turn in a conversation
    // -----------------------------------------------------------------------
    access(all) struct Message {
        access(all) let id: UInt64
        access(all) let role: String          // "user", "assistant", "system", "tool"
        access(all) let content: String       // On-chain: could be full text or hash
        access(all) let contentHash: String   // SHA-256 of full content (for verification)
        access(all) let timestamp: UFix64
        access(all) let toolName: String?     // If role == "tool"
        access(all) let toolCallId: String?   // Correlate tool calls with results
        access(all) let tokensEstimate: UInt64

        init(
            id: UInt64,
            role: String,
            content: String,
            contentHash: String,
            timestamp: UFix64,
            toolName: String?,
            toolCallId: String?,
            tokensEstimate: UInt64
        ) {
            pre {
                role == "user" || role == "assistant" || role == "system" || role == "tool":
                    "Invalid role"
            }
            self.id = id
            self.role = role
            self.content = content
            self.contentHash = contentHash
            self.timestamp = timestamp
            self.toolName = toolName
            self.toolCallId = toolCallId
            self.tokensEstimate = tokensEstimate
        }
    }

    // -----------------------------------------------------------------------
    // InferenceRequest — tracks a pending LLM call
    // -----------------------------------------------------------------------
    access(all) struct InferenceRequest {
        access(all) let requestId: UInt64
        access(all) let sessionId: UInt64
        access(all) let agentId: UInt64
        access(all) let owner: Address
        access(all) let provider: String
        access(all) let model: String
        access(all) let messagesHash: String  // Hash of the full message array sent
        access(all) let maxTokens: UInt64
        access(all) let temperature: UFix64
        access(all) let timestamp: UFix64
        access(all) var status: UInt8         // 0=pending, 1=completed, 2=failed
        access(all) var responseHash: String?
        access(all) var tokensUsed: UInt64

        init(
            requestId: UInt64,
            sessionId: UInt64,
            agentId: UInt64,
            owner: Address,
            provider: String,
            model: String,
            messagesHash: String,
            maxTokens: UInt64,
            temperature: UFix64
        ) {
            self.requestId = requestId
            self.sessionId = sessionId
            self.agentId = agentId
            self.owner = owner
            self.provider = provider
            self.model = model
            self.messagesHash = messagesHash
            self.maxTokens = maxTokens
            self.temperature = temperature
            self.timestamp = getCurrentBlock().timestamp
            self.status = 0
            self.responseHash = nil
            self.tokensUsed = 0
        }
    }

    // -----------------------------------------------------------------------
    // Session Resource — a conversation owned by a Flow account
    // -----------------------------------------------------------------------
    access(all) resource Session {
        access(all) let sessionId: UInt64
        access(all) let agentId: UInt64
        access(all) let createdAt: UFix64
        access(all) var isOpen: Bool
        access(all) var totalTokensUsed: UInt64

        access(self) var messages: [Message]
        access(self) var messageCounter: UInt64
        access(self) var pendingRequests: {UInt64: InferenceRequest}
        access(self) let maxContextMessages: UInt64  // Sliding window size

        init(
            sessionId: UInt64,
            agentId: UInt64,
            maxContextMessages: UInt64
        ) {
            self.sessionId = sessionId
            self.agentId = agentId
            self.createdAt = getCurrentBlock().timestamp
            self.isOpen = true
            self.totalTokensUsed = 0
            self.messages = []
            self.messageCounter = 0
            self.pendingRequests = {}
            self.maxContextMessages = maxContextMessages
        }

        // --- Read history ---
        access(ReadHistory) fun getMessages(): [Message] {
            return self.messages
        }

        access(ReadHistory) fun getRecentMessages(count: UInt64): [Message] {
            let len = UInt64(self.messages.length)
            if len <= count {
                return self.messages
            }
            let start = len - count
            var result: [Message] = []
            var i = start
            while i < len {
                result.append(self.messages[i])
                i = i + 1
            }
            return result
        }

        access(ReadHistory) fun getMessageCount(): UInt64 {
            return UInt64(self.messages.length)
        }

        // --- Manage: add messages, request inference ---
        access(Manage) fun addMessage(
            role: String,
            content: String,
            contentHash: String,
            toolName: String?,
            toolCallId: String?,
            tokensEstimate: UInt64
        ) {
            pre {
                self.isOpen: "Session is closed"
            }
            self.messageCounter = self.messageCounter + 1
            let msg = Message(
                id: self.messageCounter,
                role: role,
                content: content,
                contentHash: contentHash,
                timestamp: getCurrentBlock().timestamp,
                toolName: toolName,
                toolCallId: toolCallId,
                tokensEstimate: tokensEstimate
            )
            self.messages.append(msg)
            self.totalTokensUsed = self.totalTokensUsed + tokensEstimate

            emit MessageAdded(
                sessionId: self.sessionId,
                role: role,
                contentHash: contentHash
            )

            // Auto-compact if over context window
            if UInt64(self.messages.length) > self.maxContextMessages {
                self.compact()
            }
        }

        // Request inference — emits event for off-chain relay to pick up
        access(Manage) fun requestInference(
            agentRef: auth(AgentRegistry.Execute) &AgentRegistry.Agent,
            messagesHash: String
        ): UInt64 {
            pre {
                self.isOpen: "Session is closed"
                agentRef.isActive: "Agent is paused"
            }

            assert(agentRef.checkRateLimits(), message: "Rate limit exceeded")

            let config = agentRef.getInferenceConfig()

            AgentSession.totalInferenceRequests = AgentSession.totalInferenceRequests + 1
            let requestId = AgentSession.totalInferenceRequests

            let request = InferenceRequest(
                requestId: requestId,
                sessionId: self.sessionId,
                agentId: self.agentId,
                owner: self.owner!.address,
                provider: config.provider,
                model: config.model,
                messagesHash: messagesHash,
                maxTokens: config.maxTokens,
                temperature: config.temperature
            )

            self.pendingRequests[requestId] = request
            agentRef.recordInference()

            emit InferenceRequested(
                requestId: requestId,
                sessionId: self.sessionId,
                agentId: self.agentId,
                owner: self.owner!.address,
                provider: config.provider,
                model: config.model,
                contentHash: messagesHash
            )

            return requestId
        }

        // Complete inference — called when relay posts result back on-chain
        access(Manage) fun completeInference(
            requestId: UInt64,
            responseContent: String,
            responseHash: String,
            tokensUsed: UInt64
        ) {
            pre {
                self.pendingRequests[requestId] != nil: "No such pending request"
            }

            // Add assistant message
            self.addMessage(
                role: "assistant",
                content: responseContent,
                contentHash: responseHash,
                toolName: nil,
                toolCallId: nil,
                tokensEstimate: tokensUsed
            )

            // Clean up pending request
            self.pendingRequests.remove(key: requestId)

            emit InferenceCompleted(
                requestId: requestId,
                sessionId: self.sessionId,
                responseHash: responseHash,
                tokensUsed: tokensUsed
            )
        }

        // Compact old messages (keep system prompt + recent messages)
        access(self) fun compact() {
            let len = UInt64(self.messages.length)
            if len <= self.maxContextMessages {
                return
            }
            let removeCount = len - self.maxContextMessages
            // Keep system messages, remove oldest non-system messages
            var newMessages: [Message] = []
            var removed: UInt64 = 0
            for msg in self.messages {
                if msg.role == "system" {
                    newMessages.append(msg)
                } else if removed < removeCount {
                    removed = removed + 1
                } else {
                    newMessages.append(msg)
                }
            }
            self.messages = newMessages
            emit SessionCompacted(sessionId: self.sessionId, messagesRemoved: removed)
        }

        // Close session
        access(Manage) fun close() {
            self.isOpen = false
            emit SessionClosed(sessionId: self.sessionId)
        }

        access(Manage) fun getPendingRequests(): {UInt64: InferenceRequest} {
            return self.pendingRequests
        }
    }

    // -----------------------------------------------------------------------
    // SessionManager — collection of sessions per account
    // -----------------------------------------------------------------------
    access(all) resource SessionManager {
        access(self) var sessions: @{UInt64: Session}

        init() {
            self.sessions <- {}
        }

        access(Manage) fun createSession(
            agentId: UInt64,
            maxContextMessages: UInt64
        ): UInt64 {
            AgentSession.totalSessions = AgentSession.totalSessions + 1
            let sessionId = AgentSession.totalSessions

            let session <- create Session(
                sessionId: sessionId,
                agentId: agentId,
                maxContextMessages: maxContextMessages
            )

            self.sessions[sessionId] <-! session

            emit SessionCreated(
                sessionId: sessionId,
                agentId: agentId,
                owner: self.owner!.address
            )

            return sessionId
        }

        access(Manage) fun borrowSession(sessionId: UInt64): auth(Manage, ReadHistory) &Session? {
            return &self.sessions[sessionId] as auth(Manage, ReadHistory) &Session?
        }

        access(all) fun getSessionIds(): [UInt64] {
            return self.sessions.keys
        }

        access(all) fun getSessionCount(): Int {
            return self.sessions.length
        }
    }

    // -----------------------------------------------------------------------
    // Public factory
    // -----------------------------------------------------------------------
    access(all) fun createSessionManager(): @SessionManager {
        return <- create SessionManager()
    }

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    init() {
        self.totalSessions = 0
        self.totalInferenceRequests = 0
        self.SessionManagerStoragePath = /storage/FlowClawSessionManager
    }
}
