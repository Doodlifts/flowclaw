// ToolRegistry.cdc
// Manages agent tools — the actions an agent can take.
// Tools are registered globally but access is gated per-agent via SecurityPolicy.
// Supports tool execution requests that flow through the InferenceOracle relay.

access(all) contract ToolRegistry {

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    access(all) event ToolRegistered(name: String, registeredBy: Address)
    access(all) event ToolUpdated(name: String)
    access(all) event ToolRemoved(name: String)
    access(all) event ToolExecuted(toolName: String, agentId: UInt64, sessionId: UInt64)

    // -----------------------------------------------------------------------
    // Paths
    // -----------------------------------------------------------------------
    access(all) let ToolCollectionStoragePath: StoragePath

    // -----------------------------------------------------------------------
    // Entitlements
    // -----------------------------------------------------------------------
    access(all) entitlement ManageTools
    access(all) entitlement ExecuteTools

    // -----------------------------------------------------------------------
    // ToolParameter — describes an input parameter for a tool
    // -----------------------------------------------------------------------
    access(all) struct ToolParameter {
        access(all) let name: String
        access(all) let description: String
        access(all) let type: String          // "string", "number", "boolean", "array", "object"
        access(all) let required: Bool
        access(all) let defaultValue: String? // JSON-encoded default

        init(
            name: String,
            description: String,
            type: String,
            required: Bool,
            defaultValue: String?
        ) {
            self.name = name
            self.description = description
            self.type = type
            self.required = required
            self.defaultValue = defaultValue
        }
    }

    // -----------------------------------------------------------------------
    // ToolDefinition — full description of a tool for LLM function calling
    // -----------------------------------------------------------------------
    access(all) struct ToolDefinition {
        access(all) let name: String
        access(all) let description: String
        access(all) let category: String       // "execution", "memory", "browser", "messaging", etc.
        access(all) let parameters: [ToolParameter]
        access(all) let returnsDescription: String
        access(all) let isAsync: Bool          // Does this tool need off-chain execution?
        access(all) let requiresApproval: Bool // Supervised mode: needs user OK first?
        access(all) let version: UInt64
        access(all) let registeredBy: Address
        access(all) let registeredAt: UFix64

        init(
            name: String,
            description: String,
            category: String,
            parameters: [ToolParameter],
            returnsDescription: String,
            isAsync: Bool,
            requiresApproval: Bool,
            version: UInt64,
            registeredBy: Address
        ) {
            self.name = name
            self.description = description
            self.category = category
            self.parameters = parameters
            self.returnsDescription = returnsDescription
            self.isAsync = isAsync
            self.requiresApproval = requiresApproval
            self.version = version
            self.registeredBy = registeredBy
            self.registeredAt = getCurrentBlock().timestamp
        }
    }

    // -----------------------------------------------------------------------
    // ToolExecution — record of a tool being invoked
    // -----------------------------------------------------------------------
    access(all) struct ToolExecution {
        access(all) let executionId: UInt64
        access(all) let toolName: String
        access(all) let agentId: UInt64
        access(all) let sessionId: UInt64
        access(all) let inputHash: String
        access(all) let outputHash: String?
        access(all) let status: UInt8        // 0=pending, 1=completed, 2=failed, 3=denied
        access(all) let timestamp: UFix64
        access(all) let executionTimeMs: UInt64?

        init(
            executionId: UInt64,
            toolName: String,
            agentId: UInt64,
            sessionId: UInt64,
            inputHash: String,
            outputHash: String?,
            status: UInt8,
            executionTimeMs: UInt64?
        ) {
            self.executionId = executionId
            self.toolName = toolName
            self.agentId = agentId
            self.sessionId = sessionId
            self.inputHash = inputHash
            self.outputHash = outputHash
            self.status = status
            self.timestamp = getCurrentBlock().timestamp
            self.executionTimeMs = executionTimeMs
        }
    }

    // -----------------------------------------------------------------------
    // ToolCollection — per-account collection of registered tools
    // -----------------------------------------------------------------------
    access(all) resource ToolCollection {
        access(self) var tools: {String: ToolDefinition}
        access(self) var executionLog: [ToolExecution]
        access(self) var executionCounter: UInt64

        init() {
            self.tools = {}
            self.executionLog = []
            self.executionCounter = 0
        }

        // --- ManageTools: register/update/remove ---
        access(ManageTools) fun registerTool(_ definition: ToolDefinition) {
            self.tools[definition.name] = definition
            emit ToolRegistered(name: definition.name, registeredBy: self.owner!.address)
        }

        access(ManageTools) fun removeTool(name: String) {
            self.tools.remove(key: name)
            emit ToolRemoved(name: name)
        }

        // --- Read ---
        access(all) fun getTool(name: String): ToolDefinition? {
            return self.tools[name]
        }

        access(all) fun getAllTools(): {String: ToolDefinition} {
            return self.tools
        }

        access(all) fun getToolNames(): [String] {
            return self.tools.keys
        }

        // Generate JSON schema for LLM function calling
        access(all) fun getToolSchemas(allowedTools: [String]): [ToolDefinition] {
            var result: [ToolDefinition] = []
            for name in allowedTools {
                if let tool = self.tools[name] {
                    result.append(tool)
                }
            }
            return result
        }

        // --- ExecuteTools: log tool execution ---
        access(ExecuteTools) fun logExecution(
            toolName: String,
            agentId: UInt64,
            sessionId: UInt64,
            inputHash: String,
            outputHash: String?,
            status: UInt8,
            executionTimeMs: UInt64?
        ): UInt64 {
            self.executionCounter = self.executionCounter + 1
            let execution = ToolExecution(
                executionId: self.executionCounter,
                toolName: toolName,
                agentId: agentId,
                sessionId: sessionId,
                inputHash: inputHash,
                outputHash: outputHash,
                status: status,
                executionTimeMs: executionTimeMs
            )
            self.executionLog.append(execution)
            emit ToolExecuted(toolName: toolName, agentId: agentId, sessionId: sessionId)
            return self.executionCounter
        }

        access(all) fun getRecentExecutions(count: Int): [ToolExecution] {
            let len = self.executionLog.length
            if len <= count {
                return self.executionLog
            }
            let start = len - count
            return self.executionLog.slice(from: start, upTo: len)
        }
    }

    // -----------------------------------------------------------------------
    // Default tool definitions — built-in tools every agent gets
    // -----------------------------------------------------------------------
    access(all) fun getDefaultTools(registeredBy: Address): [ToolDefinition] {
        return [
            ToolDefinition(
                name: "memory_store",
                description: "Store information in the agent's long-term memory",
                category: "memory",
                parameters: [
                    ToolParameter(name: "key", description: "Memory key/topic", type: "string", required: true, defaultValue: nil),
                    ToolParameter(name: "content", description: "Content to remember", type: "string", required: true, defaultValue: nil),
                    ToolParameter(name: "tags", description: "Comma-separated tags for retrieval", type: "string", required: false, defaultValue: nil)
                ],
                returnsDescription: "Confirmation of storage with memory ID",
                isAsync: false,
                requiresApproval: false,
                version: 1,
                registeredBy: registeredBy
            ),
            ToolDefinition(
                name: "memory_recall",
                description: "Search and retrieve from the agent's long-term memory",
                category: "memory",
                parameters: [
                    ToolParameter(name: "query", description: "Search query", type: "string", required: true, defaultValue: nil),
                    ToolParameter(name: "limit", description: "Max results to return", type: "number", required: false, defaultValue: "5")
                ],
                returnsDescription: "Array of matching memory entries with relevance scores",
                isAsync: false,
                requiresApproval: false,
                version: 1,
                registeredBy: registeredBy
            ),
            ToolDefinition(
                name: "shell_exec",
                description: "Execute a shell command in a sandboxed environment",
                category: "execution",
                parameters: [
                    ToolParameter(name: "command", description: "Shell command to execute", type: "string", required: true, defaultValue: nil),
                    ToolParameter(name: "timeout_ms", description: "Execution timeout in milliseconds", type: "number", required: false, defaultValue: "30000")
                ],
                returnsDescription: "Command stdout, stderr, and exit code",
                isAsync: true,
                requiresApproval: true,
                version: 1,
                registeredBy: registeredBy
            ),
            ToolDefinition(
                name: "web_fetch",
                description: "Fetch and extract content from a URL",
                category: "browser",
                parameters: [
                    ToolParameter(name: "url", description: "URL to fetch", type: "string", required: true, defaultValue: nil),
                    ToolParameter(name: "extract", description: "What to extract: 'text', 'links', 'all'", type: "string", required: false, defaultValue: "\"text\"")
                ],
                returnsDescription: "Extracted content from the URL",
                isAsync: true,
                requiresApproval: false,
                version: 1,
                registeredBy: registeredBy
            ),
            ToolDefinition(
                name: "flow_query",
                description: "Execute a read-only Cadence script on Flow blockchain",
                category: "blockchain",
                parameters: [
                    ToolParameter(name: "script", description: "Cadence script to execute", type: "string", required: true, defaultValue: nil),
                    ToolParameter(name: "arguments", description: "JSON array of script arguments", type: "string", required: false, defaultValue: "\"[]\"")
                ],
                returnsDescription: "Script execution result as JSON",
                isAsync: true,
                requiresApproval: false,
                version: 1,
                registeredBy: registeredBy
            ),
            ToolDefinition(
                name: "flow_transact",
                description: "Send a Cadence transaction on Flow blockchain",
                category: "blockchain",
                parameters: [
                    ToolParameter(name: "transaction", description: "Cadence transaction code", type: "string", required: true, defaultValue: nil),
                    ToolParameter(name: "arguments", description: "JSON array of transaction arguments", type: "string", required: false, defaultValue: "\"[]\"")
                ],
                returnsDescription: "Transaction ID and status",
                isAsync: true,
                requiresApproval: true,
                version: 1,
                registeredBy: registeredBy
            )
        ]
    }

    // -----------------------------------------------------------------------
    // Public factory
    // -----------------------------------------------------------------------
    access(all) fun createToolCollection(): @ToolCollection {
        return <- create ToolCollection()
    }

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    init() {
        self.ToolCollectionStoragePath = /storage/FlowClawToolCollection
    }
}
