// AgentRegistry.cdc
// Core contract for registering and managing AI agents on Flow.
// Each Flow account owns their Agents as Resources in an AgentCollection.
// Supports multiple agents per account, sub-agent spawning with TTL,
// and default agent selection.
// Private inference config (model, provider, encrypted API key hash) lives in the owner's storage.

access(all) contract AgentRegistry {

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    access(all) event AgentCreated(id: UInt64, owner: Address, name: String)
    access(all) event AgentUpdated(id: UInt64, owner: Address)
    access(all) event AgentDestroyed(id: UInt64, owner: Address)
    access(all) event AgentPaused(id: UInt64)
    access(all) event AgentResumed(id: UInt64)
    access(all) event SubAgentSpawned(parentId: UInt64, childId: UInt64, owner: Address, name: String)
    access(all) event SubAgentExpired(id: UInt64, parentId: UInt64, owner: Address)
    access(all) event DefaultAgentChanged(owner: Address, agentId: UInt64)

    // -----------------------------------------------------------------------
    // Paths
    // -----------------------------------------------------------------------
    access(all) let AgentStoragePath: StoragePath      // Legacy single-agent path
    access(all) let AgentPublicPath: PublicPath         // Legacy public path
    access(all) let AgentCollectionStoragePath: StoragePath
    access(all) let AgentCollectionPublicPath: PublicPath

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------
    access(all) var totalAgents: UInt64

    // -----------------------------------------------------------------------
    // Entitlements — fine-grained access control
    // -----------------------------------------------------------------------
    access(all) entitlement Configure
    access(all) entitlement Execute
    access(all) entitlement Admin
    access(all) entitlement Manage   // For AgentCollection operations

    // -----------------------------------------------------------------------
    // SubAgentInfo — metadata for agents spawned by other agents
    // -----------------------------------------------------------------------
    access(all) struct SubAgentInfo {
        access(all) let parentAgentId: UInt64
        access(all) let createdAt: UFix64
        access(all) let expiresAt: UFix64?   // nil = permanent sub-agent
        access(all) let inheritedConfig: Bool

        init(
            parentAgentId: UInt64,
            createdAt: UFix64,
            expiresAt: UFix64?,
            inheritedConfig: Bool
        ) {
            self.parentAgentId = parentAgentId
            self.createdAt = createdAt
            self.expiresAt = expiresAt
            self.inheritedConfig = inheritedConfig
        }

        access(all) fun isExpired(): Bool {
            if let expiry = self.expiresAt {
                return getCurrentBlock().timestamp >= expiry
            }
            return false
        }
    }

    // -----------------------------------------------------------------------
    // InferenceConfig — private per-account model/provider settings
    // -----------------------------------------------------------------------
    access(all) struct InferenceConfig {
        access(all) let provider: String       // "anthropic", "openai", "ollama", etc.
        access(all) let model: String          // "claude-sonnet-4-5-20250929", etc.
        access(all) let apiKeyHash: String     // SHA-256 hash of encrypted API key (actual key stored off-chain)
        access(all) let maxTokens: UInt64
        access(all) let temperature: UFix64    // 0.0 to 2.0
        access(all) let systemPrompt: String

        init(
            provider: String,
            model: String,
            apiKeyHash: String,
            maxTokens: UInt64,
            temperature: UFix64,
            systemPrompt: String
        ) {
            self.provider = provider
            self.model = model
            self.apiKeyHash = apiKeyHash
            self.maxTokens = maxTokens
            self.temperature = temperature
            self.systemPrompt = systemPrompt
        }
    }

    // -----------------------------------------------------------------------
    // SecurityPolicy — defense-in-depth settings per agent
    // -----------------------------------------------------------------------
    access(all) struct SecurityPolicy {
        access(all) let autonomyLevel: UInt8   // 0=readonly, 1=supervised, 2=full
        access(all) let maxActionsPerHour: UInt64
        access(all) let maxCostPerDay: UFix64  // in FLOW
        access(all) let allowedTools: [String]
        access(all) let deniedTools: [String]

        init(
            autonomyLevel: UInt8,
            maxActionsPerHour: UInt64,
            maxCostPerDay: UFix64,
            allowedTools: [String],
            deniedTools: [String]
        ) {
            pre {
                autonomyLevel <= 2: "Autonomy level must be 0, 1, or 2"
            }
            self.autonomyLevel = autonomyLevel
            self.maxActionsPerHour = maxActionsPerHour
            self.maxCostPerDay = maxCostPerDay
            self.allowedTools = allowedTools
            self.deniedTools = deniedTools
        }
    }

    // -----------------------------------------------------------------------
    // AgentPublicInfo — read-only view for public capabilities
    // -----------------------------------------------------------------------
    access(all) struct AgentPublicInfo {
        access(all) let id: UInt64
        access(all) let name: String
        access(all) let description: String
        access(all) let owner: Address
        access(all) let createdAt: UFix64
        access(all) let isActive: Bool
        access(all) let totalSessions: UInt64
        access(all) let totalInferences: UInt64

        init(
            id: UInt64,
            name: String,
            description: String,
            owner: Address,
            createdAt: UFix64,
            isActive: Bool,
            totalSessions: UInt64,
            totalInferences: UInt64
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.owner = owner
            self.createdAt = createdAt
            self.isActive = isActive
            self.totalSessions = totalSessions
            self.totalInferences = totalInferences
        }
    }

    // -----------------------------------------------------------------------
    // Agent Resource — the core owned entity
    // -----------------------------------------------------------------------
    access(all) resource Agent {
        access(all) let id: UInt64
        access(all) var name: String
        access(all) var description: String
        access(all) let createdAt: UFix64
        access(all) var isActive: Bool
        access(all) var totalSessions: UInt64
        access(all) var totalInferences: UInt64

        // Private: only owner can read/write
        access(self) var inferenceConfig: InferenceConfig
        access(self) var securityPolicy: SecurityPolicy
        access(self) var actionCountThisHour: UInt64
        access(self) var costToday: UFix64
        access(self) var lastHourReset: UFix64
        access(self) var lastDayReset: UFix64

        init(
            id: UInt64,
            name: String,
            description: String,
            inferenceConfig: InferenceConfig,
            securityPolicy: SecurityPolicy
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.createdAt = getCurrentBlock().timestamp
            self.isActive = true
            self.totalSessions = 0
            self.totalInferences = 0
            self.inferenceConfig = inferenceConfig
            self.securityPolicy = securityPolicy
            self.actionCountThisHour = 0
            self.costToday = 0.0
            self.lastHourReset = getCurrentBlock().timestamp
            self.lastDayReset = getCurrentBlock().timestamp
        }

        // --- Public read-only view ---
        access(all) fun getPublicInfo(): AgentPublicInfo {
            return AgentPublicInfo(
                id: self.id,
                name: self.name,
                description: self.description,
                owner: self.owner!.address,
                createdAt: self.createdAt,
                isActive: self.isActive,
                totalSessions: self.totalSessions,
                totalInferences: self.totalInferences
            )
        }

        // --- Configure entitlement: update settings ---
        access(Configure) fun updateInferenceConfig(_ config: InferenceConfig) {
            self.inferenceConfig = config
            emit AgentUpdated(id: self.id, owner: self.owner!.address)
        }

        access(Configure) fun updateSecurityPolicy(_ policy: SecurityPolicy) {
            self.securityPolicy = policy
            emit AgentUpdated(id: self.id, owner: self.owner!.address)
        }

        access(Configure) fun updateName(_ name: String) {
            self.name = name
        }

        access(Configure) fun updateDescription(_ description: String) {
            self.description = description
        }

        // --- Execute entitlement: run agent actions ---
        access(Execute) fun getInferenceConfig(): InferenceConfig {
            return self.inferenceConfig
        }

        access(Execute) fun getSecurityPolicy(): SecurityPolicy {
            return self.securityPolicy
        }

        access(Execute) fun recordInference() {
            self.totalInferences = self.totalInferences + 1
            self.actionCountThisHour = self.actionCountThisHour + 1
        }

        access(Execute) fun recordSession() {
            self.totalSessions = self.totalSessions + 1
        }

        access(Execute) fun recordCost(amount: UFix64) {
            self.costToday = self.costToday + amount
        }

        access(Execute) fun checkRateLimits(): Bool {
            let now = getCurrentBlock().timestamp
            // Reset hourly counter
            if now - self.lastHourReset > 3600.0 {
                self.actionCountThisHour = 0
                self.lastHourReset = now
            }
            // Reset daily counter
            if now - self.lastDayReset > 86400.0 {
                self.costToday = 0.0
                self.lastDayReset = now
            }
            let policy = self.securityPolicy
            if self.actionCountThisHour >= policy.maxActionsPerHour {
                return false
            }
            if self.costToday >= policy.maxCostPerDay {
                return false
            }
            return true
        }

        // --- Admin entitlement: pause/resume ---
        access(Admin) fun pause() {
            self.isActive = false
            emit AgentPaused(id: self.id)
        }

        access(Admin) fun resume() {
            self.isActive = true
            emit AgentResumed(id: self.id)
        }
    }

    // -----------------------------------------------------------------------
    // Public interface for reading agent info
    // -----------------------------------------------------------------------
    access(all) resource interface AgentPublicView {
        access(all) fun getPublicInfo(): AgentPublicInfo
    }

    // -----------------------------------------------------------------------
    // AgentCollection — holds multiple agents per account
    // -----------------------------------------------------------------------
    access(all) resource AgentCollection {
        access(self) let agents: @{UInt64: Agent}
        access(self) var defaultAgentId: UInt64?
        access(self) let subAgentInfo: {UInt64: SubAgentInfo}

        init() {
            self.agents <- {}
            self.defaultAgentId = nil
            self.subAgentInfo = {}
        }

        // --- Manage entitlement: add/remove agents ---

        access(Manage) fun addAgent(_ agent: @Agent) {
            let id = agent.id
            let old <- self.agents[id] <- agent
            destroy old

            // If this is the first agent, make it the default
            if self.defaultAgentId == nil {
                self.defaultAgentId = id
            }
        }

        access(Manage) fun createAgent(
            name: String,
            description: String,
            ownerAddress: Address,
            inferenceConfig: InferenceConfig,
            securityPolicy: SecurityPolicy
        ): UInt64 {
            let agent <- AgentRegistry.createAgent(
                name: name,
                description: description,
                ownerAddress: ownerAddress,
                inferenceConfig: inferenceConfig,
                securityPolicy: securityPolicy
            )
            let id = agent.id
            self.addAgent(<- agent)
            return id
        }

        access(Manage) fun removeAgent(id: UInt64): @Agent {
            let agent <- self.agents.remove(key: id)
                ?? panic("Agent not found in collection")

            // If we removed the default, pick another
            if self.defaultAgentId == id {
                let remaining = self.agents.keys
                self.defaultAgentId = remaining.length > 0 ? remaining[0] : nil
            }

            // Clean up sub-agent info
            self.subAgentInfo.remove(key: id)

            return <- agent
        }

        access(Manage) fun setDefault(agentId: UInt64) {
            pre {
                self.agents[agentId] != nil: "Agent not in collection"
            }
            self.defaultAgentId = agentId
            emit DefaultAgentChanged(owner: self.owner!.address, agentId: agentId)
        }

        // --- Sub-agent spawning ---

        access(Manage) fun spawnSubAgent(
            parentAgentId: UInt64,
            name: String,
            description: String,
            ownerAddress: Address,
            ttlSeconds: UFix64?,
            inheritConfig: Bool
        ): UInt64 {
            pre {
                self.agents[parentAgentId] != nil: "Parent agent not found"
            }

            // Build config: inherit from parent or use defaults
            var inferenceConfig: InferenceConfig? = nil
            var securityPolicy: SecurityPolicy? = nil

            if inheritConfig {
                let parentRef = (&self.agents[parentAgentId] as auth(Execute) &Agent?)!
                inferenceConfig = parentRef.getInferenceConfig()
                securityPolicy = parentRef.getSecurityPolicy()
            }

            let config = inferenceConfig ?? InferenceConfig(
                provider: "venice",
                model: "claude-sonnet-4-6",
                apiKeyHash: "",
                maxTokens: 4096,
                temperature: 0.70000000,
                systemPrompt: "You are a sub-agent of ".concat(name)
            )
            let policy = securityPolicy ?? SecurityPolicy(
                autonomyLevel: 1,
                maxActionsPerHour: 50,
                maxCostPerDay: 1.0,
                allowedTools: ["memory_store", "memory_recall"],
                deniedTools: ["shell_exec"]
            )

            let agent <- AgentRegistry.createAgent(
                name: name,
                description: description,
                ownerAddress: ownerAddress,
                inferenceConfig: config,
                securityPolicy: policy
            )
            let childId = agent.id

            // Calculate expiry
            var expiresAt: UFix64? = nil
            if let ttl = ttlSeconds {
                expiresAt = getCurrentBlock().timestamp + ttl
            }

            // Store sub-agent metadata
            self.subAgentInfo[childId] = SubAgentInfo(
                parentAgentId: parentAgentId,
                createdAt: getCurrentBlock().timestamp,
                expiresAt: expiresAt,
                inheritedConfig: inheritConfig
            )

            self.addAgent(<- agent)

            emit SubAgentSpawned(
                parentId: parentAgentId,
                childId: childId,
                owner: ownerAddress,
                name: name
            )

            return childId
        }

        // --- Clean up expired sub-agents ---

        access(Manage) fun cleanupExpiredSubAgents(): [UInt64] {
            let expired: [UInt64] = []
            for id in self.subAgentInfo.keys {
                if let info = self.subAgentInfo[id] {
                    if info.isExpired() {
                        expired.append(id)
                    }
                }
            }
            for id in expired {
                let agent <- self.removeAgent(id: id)
                emit SubAgentExpired(
                    id: id,
                    parentId: self.subAgentInfo[id]?.parentAgentId ?? 0,
                    owner: self.owner!.address
                )
                destroy agent
            }
            return expired
        }

        // --- Read access ---

        access(all) fun borrowAgent(id: UInt64): &Agent? {
            return &self.agents[id]
        }

        access(Manage) fun borrowAgentManaged(id: UInt64): auth(Configure, Execute, Admin) &Agent? {
            return &self.agents[id]
        }

        access(all) fun getAgentIds(): [UInt64] {
            return self.agents.keys
        }

        access(all) fun getAgentCount(): Int {
            return self.agents.keys.length
        }

        access(all) fun getDefaultAgentId(): UInt64? {
            return self.defaultAgentId
        }

        access(all) fun getSubAgentInfo(agentId: UInt64): SubAgentInfo? {
            return self.subAgentInfo[agentId]
        }

        access(all) fun isSubAgent(agentId: UInt64): Bool {
            return self.subAgentInfo[agentId] != nil
        }

        access(all) fun getSubAgents(parentId: UInt64): [UInt64] {
            let children: [UInt64] = []
            for id in self.subAgentInfo.keys {
                if let info = self.subAgentInfo[id] {
                    if info.parentAgentId == parentId {
                        children.append(id)
                    }
                }
            }
            return children
        }

        access(all) fun getAllAgentInfo(): [AgentPublicInfo] {
            let infos: [AgentPublicInfo] = []
            for id in self.agents.keys {
                if let agent = &self.agents[id] as &Agent? {
                    infos.append(agent.getPublicInfo())
                }
            }
            return infos
        }
    }

    // -----------------------------------------------------------------------
    // Create Agent — called by any Flow account to register their agent
    // -----------------------------------------------------------------------
    access(all) fun createAgent(
        name: String,
        description: String,
        ownerAddress: Address,
        inferenceConfig: InferenceConfig,
        securityPolicy: SecurityPolicy
    ): @Agent {
        self.totalAgents = self.totalAgents + 1
        let agent <- create Agent(
            id: self.totalAgents,
            name: name,
            description: description,
            inferenceConfig: inferenceConfig,
            securityPolicy: securityPolicy
        )
        emit AgentCreated(id: agent.id, owner: ownerAddress, name: name)
        return <- agent
    }

    // -----------------------------------------------------------------------
    // Create AgentCollection — for multi-agent accounts
    // -----------------------------------------------------------------------
    access(all) fun createAgentCollection(): @AgentCollection {
        return <- create AgentCollection()
    }

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    init() {
        self.totalAgents = 0
        self.AgentStoragePath = /storage/FlowClawAgent
        self.AgentPublicPath = /public/FlowClawAgent
        self.AgentCollectionStoragePath = /storage/FlowClawAgentCollection
        self.AgentCollectionPublicPath = /public/FlowClawAgentCollection
    }
}
