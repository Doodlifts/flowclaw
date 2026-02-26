// AgentExtensions.cdc
// Permissionless extension system for FlowClaw.
//
// THE PROBLEM WITH GITHUB-BASED OPEN SOURCE:
// In OpenClaw, to add a feature you must:
//   1. Fork the repo
//   2. Write the code
//   3. Open a PR
//   4. Wait for a maintainer to review and merge
//   5. Hope they agree with your design
//   6. If rejected, maintain your own fork forever
//
// This creates a centralization bottleneck where one person/team
// controls the evolution of every agent in the ecosystem.
//
// THE CADENCE SOLUTION:
// FlowClaw separates the base protocol (these contracts) from extensions.
// Anyone can deploy an extension contract that adds:
//   - New tools (without modifying ToolRegistry)
//   - New lifecycle hooks (without modifying AgentLifecycleHooks)
//   - New memory backends (without modifying AgentMemory)
//   - New scheduling strategies (without modifying AgentScheduler)
//   - New channel adapters
//   - Custom agent behaviors
//
// Extensions interact with the base contracts through CAPABILITIES:
//   - The base contracts define interfaces and issue capabilities
//   - Extensions consume those capabilities with specific entitlements
//   - The agent OWNER decides which extensions to install
//   - Extensions can't exceed their granted entitlements
//
// This means:
//   - No maintainer approval needed to extend FlowClaw
//   - No forking — extensions compose with the base contracts
//   - The agent owner has full control over what runs on their agent
//   - Extensions can't break the base protocol's security guarantees
//   - Different users can run different extension sets on the same base
//
// ANALOGY: Think of it like smartphone apps. Apple doesn't need to modify
// iOS every time someone wants a new app. The OS provides APIs (capabilities),
// apps consume them (extensions), and users choose what to install.
// Except here, there's no App Store gatekeeper either.

import "AgentRegistry"
import "ToolRegistry"
import "AgentLifecycleHooks"

access(all) contract AgentExtensions {

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    access(all) event ExtensionPublished(
        extensionId: UInt64,
        name: String,
        author: Address,
        version: String,
        category: String
    )
    access(all) event ExtensionInstalled(
        extensionId: UInt64,
        name: String,
        installedBy: Address
    )
    access(all) event ExtensionUninstalled(
        extensionId: UInt64,
        name: String,
        uninstalledBy: Address
    )
    access(all) event ExtensionUpgraded(
        extensionId: UInt64,
        name: String,
        fromVersion: String,
        toVersion: String
    )

    // -----------------------------------------------------------------------
    // Paths
    // -----------------------------------------------------------------------
    access(all) let ExtensionManagerStoragePath: StoragePath
    access(all) let ExtensionRegistryStoragePath: StoragePath

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------
    access(all) var totalExtensions: UInt64

    // -----------------------------------------------------------------------
    // Entitlements — what an extension can ask for
    // -----------------------------------------------------------------------
    access(all) entitlement Install
    access(all) entitlement Publish
    access(all) entitlement Configure

    // -----------------------------------------------------------------------
    // ExtensionCategory — types of extensions
    // -----------------------------------------------------------------------
    access(all) enum ExtensionCategory: UInt8 {
        access(all) case tool             // Adds new tools
        access(all) case hook             // Adds lifecycle hooks
        access(all) case memoryBackend    // Alternative memory storage
        access(all) case scheduler        // Custom scheduling strategies
        access(all) case channel          // New communication channels
        access(all) case behavior         // Custom agent behaviors
        access(all) case integration      // Third-party service integrations
        access(all) case composite        // Bundles multiple extension types
    }

    // -----------------------------------------------------------------------
    // RequiredEntitlement — what capabilities an extension needs
    // -----------------------------------------------------------------------
    access(all) struct RequiredEntitlement {
        access(all) let resourceName: String       // "Agent", "Session", "Memory", "Tools", "Hooks"
        access(all) let entitlementName: String    // "ReadOnly", "Execute", "Configure", etc.
        access(all) let reason: String             // Why this permission is needed

        init(resourceName: String, entitlementName: String, reason: String) {
            self.resourceName = resourceName
            self.entitlementName = entitlementName
            self.reason = reason
        }
    }

    // -----------------------------------------------------------------------
    // ExtensionMetadata — describes an extension (published on-chain)
    // -----------------------------------------------------------------------
    access(all) struct ExtensionMetadata {
        access(all) let extensionId: UInt64
        access(all) let name: String
        access(all) let description: String
        access(all) let version: String
        access(all) let author: Address
        access(all) let category: ExtensionCategory
        access(all) let publishedAt: UFix64
        access(all) let sourceHash: String         // Hash of the extension's source code
        access(all) let requiredEntitlements: [RequiredEntitlement]
        access(all) let dependencies: [UInt64]     // Other extension IDs this depends on
        access(all) let tags: [String]
        access(all) var installCount: UInt64
        access(all) let isAudited: Bool            // Community-audited flag

        // Extension-provided tool definitions (if category == tool)
        access(all) let toolDefinitions: [ToolRegistry.ToolDefinition]

        // Extension-provided hook configs (if category == hook)
        access(all) let hookConfigs: [AgentLifecycleHooks.HookConfig]

        init(
            extensionId: UInt64,
            name: String,
            description: String,
            version: String,
            author: Address,
            category: ExtensionCategory,
            sourceHash: String,
            requiredEntitlements: [RequiredEntitlement],
            dependencies: [UInt64],
            tags: [String],
            isAudited: Bool,
            toolDefinitions: [ToolRegistry.ToolDefinition],
            hookConfigs: [AgentLifecycleHooks.HookConfig]
        ) {
            pre {
                name.length > 0 && name.length <= 64:
                    "Extension name must be 1-64 characters"
                version.length > 0: "Version cannot be empty"
            }
            self.extensionId = extensionId
            self.name = name
            self.description = description
            self.version = version
            self.author = author
            self.category = category
            self.publishedAt = getCurrentBlock().timestamp
            self.sourceHash = sourceHash
            self.requiredEntitlements = requiredEntitlements
            self.dependencies = dependencies
            self.tags = tags
            self.installCount = 0
            self.isAudited = isAudited
            self.toolDefinitions = toolDefinitions
            self.hookConfigs = hookConfigs
        }
    }

    // -----------------------------------------------------------------------
    // InstalledExtension — tracks an extension installed on an agent
    // -----------------------------------------------------------------------
    access(all) struct InstalledExtension {
        access(all) let extensionId: UInt64
        access(all) let name: String
        access(all) let version: String
        access(all) let installedAt: UFix64
        access(all) let installedBy: Address
        access(all) var isEnabled: Bool
        access(all) var config: {String: String}   // User-specific config for this extension

        init(
            extensionId: UInt64,
            name: String,
            version: String,
            installedBy: Address,
            config: {String: String}
        ) {
            self.extensionId = extensionId
            self.name = name
            self.version = version
            self.installedAt = getCurrentBlock().timestamp
            self.installedBy = installedBy
            self.isEnabled = true
            self.config = config
        }

        access(all) fun setEnabled(_ enabled: Bool) {
            self.isEnabled = enabled
        }

        access(all) fun setConfig(_ newConfig: {String: String}) {
            self.config = newConfig
        }
    }

    // -----------------------------------------------------------------------
    // ExtensionManager — per-account extension management
    // Each agent owner controls exactly which extensions run on their agent.
    // -----------------------------------------------------------------------
    access(all) resource ExtensionManager {
        access(self) var installed: {UInt64: InstalledExtension}
        access(self) var enabledTools: {String: UInt64}    // toolName -> extensionId
        access(self) var enabledHooks: {UInt64: UInt64}    // hookId -> extensionId

        init() {
            self.installed = {}
            self.enabledTools = {}
            self.enabledHooks = {}
        }

        // --- Install: add an extension to your agent ---

        access(Install) fun installExtension(
            metadata: ExtensionMetadata,
            config: {String: String}
        ) {
            pre {
                self.installed[metadata.extensionId] == nil:
                    "Extension already installed"
            }
            post {
                self.installed[metadata.extensionId] != nil:
                    "Extension must be installed after this call"
            }

            // Check dependencies are installed
            for depId in metadata.dependencies {
                assert(
                    self.installed[depId] != nil,
                    message: "Missing dependency: extension #".concat(depId.toString())
                )
            }

            let installation = InstalledExtension(
                extensionId: metadata.extensionId,
                name: metadata.name,
                version: metadata.version,
                installedBy: self.owner!.address,
                config: config
            )

            self.installed[metadata.extensionId] = installation

            // Register extension-provided tools
            for tool in metadata.toolDefinitions {
                self.enabledTools[tool.name] = metadata.extensionId
            }

            emit ExtensionInstalled(
                extensionId: metadata.extensionId,
                name: metadata.name,
                installedBy: self.owner!.address
            )
        }

        access(Install) fun uninstallExtension(extensionId: UInt64) {
            pre {
                self.installed[extensionId] != nil: "Extension not installed"
            }

            if let ext = self.installed[extensionId] {
                // Remove tools provided by this extension
                var toolsToRemove: [String] = []
                for toolName in self.enabledTools.keys {
                    if self.enabledTools[toolName] == extensionId {
                        toolsToRemove.append(toolName)
                    }
                }
                for name in toolsToRemove {
                    self.enabledTools.remove(key: name)
                }

                // Remove hooks provided by this extension
                var hooksToRemove: [UInt64] = []
                for hookId in self.enabledHooks.keys {
                    if self.enabledHooks[hookId] == extensionId {
                        hooksToRemove.append(hookId)
                    }
                }
                for hookId in hooksToRemove {
                    self.enabledHooks.remove(key: hookId)
                }

                // Check no other extension depends on this one
                for otherId in self.installed.keys {
                    if otherId == extensionId { continue }
                    // In a full implementation, check dependency chains
                }

                self.installed.remove(key: extensionId)

                emit ExtensionUninstalled(
                    extensionId: extensionId,
                    name: ext.name,
                    uninstalledBy: self.owner!.address
                )
            }
        }

        // --- Configure: enable/disable and configure extensions ---

        access(Configure) fun enableExtension(extensionId: UInt64) {
            pre {
                self.installed[extensionId] != nil: "Extension not installed"
            }
            if var ext = self.installed[extensionId] {
                ext.setEnabled(true)
                self.installed[extensionId] = ext
            }
        }

        access(Configure) fun disableExtension(extensionId: UInt64) {
            pre {
                self.installed[extensionId] != nil: "Extension not installed"
            }
            if var ext = self.installed[extensionId] {
                ext.setEnabled(false)
                self.installed[extensionId] = ext
            }
        }

        access(Configure) fun updateExtensionConfig(
            extensionId: UInt64,
            config: {String: String}
        ) {
            pre {
                self.installed[extensionId] != nil: "Extension not installed"
            }
            if var ext = self.installed[extensionId] {
                ext.setConfig(config)
                self.installed[extensionId] = ext
            }
        }

        // --- Read ---

        access(all) fun getInstalledExtensions(): [InstalledExtension] {
            var result: [InstalledExtension] = []
            for id in self.installed.keys {
                if let ext = self.installed[id] {
                    result.append(ext)
                }
            }
            return result
        }

        access(all) fun getEnabledExtensions(): [InstalledExtension] {
            var result: [InstalledExtension] = []
            for id in self.installed.keys {
                if let ext = self.installed[id] {
                    if ext.isEnabled {
                        result.append(ext)
                    }
                }
            }
            return result
        }

        access(all) fun isInstalled(extensionId: UInt64): Bool {
            return self.installed[extensionId] != nil
        }

        access(all) fun isEnabled(extensionId: UInt64): Bool {
            if let ext = self.installed[extensionId] {
                return ext.isEnabled
            }
            return false
        }

        access(all) fun getExtensionTools(): {String: UInt64} {
            return self.enabledTools
        }

        access(all) fun getInstalledCount(): Int {
            return self.installed.length
        }
    }

    // -----------------------------------------------------------------------
    // ExtensionRegistry — global directory of published extensions
    // Anyone can publish. Users decide what to install. No gatekeeper.
    // -----------------------------------------------------------------------
    access(all) resource ExtensionRegistry {
        access(self) var extensions: {UInt64: ExtensionMetadata}
        access(self) var nameIndex: {String: UInt64}          // name -> extensionId
        access(self) var categoryIndex: {UInt8: [UInt64]}     // category -> [extensionIds]
        access(self) var authorIndex: {Address: [UInt64]}     // author -> [extensionIds]

        init() {
            self.extensions = {}
            self.nameIndex = {}
            self.categoryIndex = {}
            self.authorIndex = {}
        }

        // --- Publish: anyone can publish an extension ---

        access(Publish) fun publishExtension(
            name: String,
            description: String,
            version: String,
            author: Address,
            category: ExtensionCategory,
            sourceHash: String,
            requiredEntitlements: [RequiredEntitlement],
            dependencies: [UInt64],
            tags: [String],
            toolDefinitions: [ToolRegistry.ToolDefinition],
            hookConfigs: [AgentLifecycleHooks.HookConfig]
        ): UInt64 {
            pre {
                // Don't allow name squatting of existing names
                // (unless it's the same author publishing an update)
                self.nameIndex[name] == nil ||
                self.extensions[self.nameIndex[name]!]!.author == author:
                    "Extension name already taken by another author"
            }
            post {
                self.extensions[AgentExtensions.totalExtensions] != nil:
                    "Extension must be stored after publishing"
            }

            AgentExtensions.totalExtensions = AgentExtensions.totalExtensions + 1
            let extensionId = AgentExtensions.totalExtensions

            let metadata = ExtensionMetadata(
                extensionId: extensionId,
                name: name,
                description: description,
                version: version,
                author: author,
                category: category,
                sourceHash: sourceHash,
                requiredEntitlements: requiredEntitlements,
                dependencies: dependencies,
                tags: tags,
                isAudited: false,
                toolDefinitions: toolDefinitions,
                hookConfigs: hookConfigs
            )

            self.extensions[extensionId] = metadata
            self.nameIndex[name] = extensionId

            // Update category index
            let catKey = category.rawValue
            if self.categoryIndex[catKey] == nil {
                self.categoryIndex[catKey] = [extensionId]
            } else {
                self.categoryIndex[catKey]!.append(extensionId)
            }

            // Update author index
            if self.authorIndex[author] == nil {
                self.authorIndex[author] = [extensionId]
            } else {
                self.authorIndex[author]!.append(extensionId)
            }

            let categoryStr = self.categoryToString(category)

            emit ExtensionPublished(
                extensionId: extensionId,
                name: name,
                author: author,
                version: version,
                category: categoryStr
            )

            return extensionId
        }

        // --- Read: discover extensions ---

        access(all) fun getExtension(extensionId: UInt64): ExtensionMetadata? {
            return self.extensions[extensionId]
        }

        access(all) fun getExtensionByName(name: String): ExtensionMetadata? {
            if let id = self.nameIndex[name] {
                return self.extensions[id]
            }
            return nil
        }

        access(all) fun getExtensionsByCategory(category: ExtensionCategory): [ExtensionMetadata] {
            var result: [ExtensionMetadata] = []
            let catKey = category.rawValue
            if let ids = self.categoryIndex[catKey] {
                for id in ids {
                    if let ext = self.extensions[id] {
                        result.append(ext)
                    }
                }
            }
            return result
        }

        access(all) fun getExtensionsByAuthor(author: Address): [ExtensionMetadata] {
            var result: [ExtensionMetadata] = []
            if let ids = self.authorIndex[author] {
                for id in ids {
                    if let ext = self.extensions[id] {
                        result.append(ext)
                    }
                }
            }
            return result
        }

        access(all) fun searchExtensions(tag: String): [ExtensionMetadata] {
            var result: [ExtensionMetadata] = []
            for id in self.extensions.keys {
                if let ext = self.extensions[id] {
                    if ext.tags.contains(tag) {
                        result.append(ext)
                    }
                }
            }
            return result
        }

        access(all) fun getTotalExtensions(): UInt64 {
            return AgentExtensions.totalExtensions
        }

        // --- Internal ---

        access(self) fun categoryToString(_ cat: ExtensionCategory): String {
            switch cat {
                case ExtensionCategory.tool: return "tool"
                case ExtensionCategory.hook: return "hook"
                case ExtensionCategory.memoryBackend: return "memory"
                case ExtensionCategory.scheduler: return "scheduler"
                case ExtensionCategory.channel: return "channel"
                case ExtensionCategory.behavior: return "behavior"
                case ExtensionCategory.integration: return "integration"
                case ExtensionCategory.composite: return "composite"
            }
            return "unknown"
        }
    }

    // -----------------------------------------------------------------------
    // Public factories
    // -----------------------------------------------------------------------
    access(all) fun createExtensionManager(): @ExtensionManager {
        return <- create ExtensionManager()
    }

    access(all) fun createExtensionRegistry(): @ExtensionRegistry {
        return <- create ExtensionRegistry()
    }

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    init() {
        self.totalExtensions = 0
        self.ExtensionManagerStoragePath = /storage/FlowClawExtensionManager
        self.ExtensionRegistryStoragePath = /storage/FlowClawExtensionRegistry
    }
}
