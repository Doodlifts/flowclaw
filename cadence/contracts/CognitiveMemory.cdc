// CognitiveMemory.cdc
// Cognitive memory layer for FlowClaw AI agents on Flow.
// Implements the four biological memory types (episodic, semantic, procedural, self-model),
// molecular memory bonds for O(k) retrieval, importance scoring, and dream cycle consolidation.
//
// Built on top of AgentMemory — this contract adds cognitive structure without
// replacing the base storage layer. Think of it as the prefrontal cortex
// sitting on top of the hippocampus.
//
// Architecture inspired by:
//   - Stanford Generative Agents (Park et al. 2023) — importance scoring, reflection
//   - CoALA cognitive architecture — episodic/semantic/procedural/self-model split
//   - ByteDance Mole-Syn — molecular memory bonds for graph-based retrieval
//   - Flow advantages: Cadence resources (memories can't be duplicated), native scheduled
//     transactions (dream cycles on-chain), entitlements (fine-grained access control),
//     and XChaCha20 encryption (privacy Solana doesn't have)

import AgentMemory from "./AgentMemory.cdc"

access(all) contract CognitiveMemory {

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    access(all) event CognitiveMemoryStored(
        memoryId: UInt64,
        memoryType: UInt8,
        importance: UInt8,
        owner: Address
    )
    access(all) event BondCreated(
        fromMemoryId: UInt64,
        toMemoryId: UInt64,
        bondType: UInt8,
        strength: UFix64
    )
    access(all) event MoleculeFormed(
        moleculeId: UInt64,
        atomCount: UInt64,
        stability: UFix64,
        owner: Address
    )
    access(all) event DreamCycleCompleted(
        memoriesConsolidated: UInt64,
        bondsCreated: UInt64,
        memoriesPruned: UInt64,
        owner: Address
    )
    access(all) event MemoryPromoted(
        memoryId: UInt64,
        fromType: UInt8,
        toType: UInt8
    )
    access(all) event MemoryDecayed(
        memoryId: UInt64,
        newStrength: UFix64
    )

    // -----------------------------------------------------------------------
    // Paths
    // -----------------------------------------------------------------------
    access(all) let CognitiveVaultStoragePath: StoragePath

    // -----------------------------------------------------------------------
    // Entitlements
    // -----------------------------------------------------------------------
    access(all) entitlement Cognize    // Store with cognitive metadata
    access(all) entitlement Bond       // Create/modify bonds between memories
    access(all) entitlement Dream      // Run dream cycle consolidation
    access(all) entitlement Introspect // Read cognitive metadata

    // -----------------------------------------------------------------------
    // Memory Types — from cognitive science (CoALA framework)
    // -----------------------------------------------------------------------
    // 0 = Episodic:    "I did X at time T" — events, conversations, experiences
    // 1 = Semantic:    "X means Y" — learned facts, knowledge
    // 2 = Procedural:  "To do X, do Y then Z" — skills, behaviors, workflows
    // 3 = Self-Model:  "I am an agent who..." — identity, beliefs, preferences

    access(all) fun getMemoryTypeName(_ t: UInt8): String {
        switch t {
            case 0: return "episodic"
            case 1: return "semantic"
            case 2: return "procedural"
            case 3: return "self-model"
            default: return "unknown"
        }
    }

    // -----------------------------------------------------------------------
    // Bond Types — molecular connections between memories (Mole-Syn inspired)
    // -----------------------------------------------------------------------
    // 0 = Causal:        "this led to that" — cause and effect chains
    // 1 = Semantic:      "these are related concepts" — topic/meaning similarity
    // 2 = Temporal:      "these happened together" — co-occurring in time
    // 3 = Contradictory: "these conflict" — opposing information

    access(all) fun getBondTypeName(_ t: UInt8): String {
        switch t {
            case 0: return "causal"
            case 1: return "semantic"
            case 2: return "temporal"
            case 3: return "contradictory"
            default: return "unknown"
        }
    }

    // -----------------------------------------------------------------------
    // Decay rates per memory type (% per day, scaled as UFix64)
    // Episodic fades fast unless reinforced. Identity persists.
    // -----------------------------------------------------------------------
    access(all) fun getDecayRate(_ memoryType: UInt8): UFix64 {
        switch memoryType {
            case 0: return 0.07  // Episodic:   7% per day
            case 1: return 0.02  // Semantic:   2% per day
            case 2: return 0.03  // Procedural: 3% per day
            case 3: return 0.01  // Self-Model: 1% per day
            default: return 0.05
        }
    }

    // -----------------------------------------------------------------------
    // CognitiveEntry — cognitive metadata layered on top of AgentMemory.MemoryEntry
    // -----------------------------------------------------------------------
    access(all) struct CognitiveEntry {
        access(all) let memoryId: UInt64       // References AgentMemory entry ID
        access(all) let memoryType: UInt8      // 0=episodic, 1=semantic, 2=procedural, 3=self-model
        access(all) let importance: UInt8      // 1-10 scale (Stanford Generative Agents)
        access(all) let strength: UFix64       // Current strength after decay (0.0 - 1.0)
        access(all) let emotionalWeight: UInt8 // 1-10, how emotionally significant
        access(all) let moleculeId: UInt64     // 0 if unassigned, else which molecule cluster
        access(all) let bondCount: UInt64      // Number of bonds this memory has
        access(all) let promotedFrom: UInt8    // Original type if promoted (255 = never promoted)
        access(all) let lastDecayAt: UFix64    // Timestamp of last decay calculation
        access(all) let createdAt: UFix64

        init(
            memoryId: UInt64,
            memoryType: UInt8,
            importance: UInt8,
            strength: UFix64,
            emotionalWeight: UInt8,
            moleculeId: UInt64,
            bondCount: UInt64,
            promotedFrom: UInt8,
            lastDecayAt: UFix64,
            createdAt: UFix64
        ) {
            pre {
                memoryType <= 3: "Invalid memory type"
                importance >= 1 && importance <= 10: "Importance must be 1-10"
                emotionalWeight >= 1 && emotionalWeight <= 10: "Emotional weight must be 1-10"
                strength >= 0.0 && strength <= 1.0: "Strength must be 0.0-1.0"
            }
            self.memoryId = memoryId
            self.memoryType = memoryType
            self.importance = importance
            self.strength = strength
            self.emotionalWeight = emotionalWeight
            self.moleculeId = moleculeId
            self.bondCount = bondCount
            self.promotedFrom = promotedFrom
            self.lastDecayAt = lastDecayAt
            self.createdAt = createdAt
        }
    }

    // -----------------------------------------------------------------------
    // MemoryBond — typed relationship between two memories
    // -----------------------------------------------------------------------
    access(all) struct MemoryBond {
        access(all) let fromMemoryId: UInt64
        access(all) let toMemoryId: UInt64
        access(all) let bondType: UInt8        // 0=causal, 1=semantic, 2=temporal, 3=contradictory
        access(all) let strength: UFix64       // 0.0 - 1.0 (how strong the connection)
        access(all) let createdAt: UFix64

        init(
            fromMemoryId: UInt64,
            toMemoryId: UInt64,
            bondType: UInt8,
            strength: UFix64,
            createdAt: UFix64
        ) {
            pre {
                bondType <= 3: "Invalid bond type"
                strength >= 0.0 && strength <= 1.0: "Bond strength must be 0.0-1.0"
                fromMemoryId != toMemoryId: "Cannot bond memory to itself"
            }
            self.fromMemoryId = fromMemoryId
            self.toMemoryId = toMemoryId
            self.bondType = bondType
            self.strength = strength
            self.createdAt = createdAt
        }
    }

    // -----------------------------------------------------------------------
    // Molecule — stable cluster of bonded memories
    // -----------------------------------------------------------------------
    access(all) struct Molecule {
        access(all) let id: UInt64
        access(all) let atomIds: [UInt64]      // Memory IDs in this molecule
        access(all) let stability: UFix64      // 0.0 - 1.0 (higher = more stable, resists pruning)
        access(all) let topic: String          // Primary topic/label
        access(all) let bondCount: UInt64      // Total internal bonds
        access(all) let createdAt: UFix64
        access(all) let lastConsolidatedAt: UFix64

        init(
            id: UInt64,
            atomIds: [UInt64],
            stability: UFix64,
            topic: String,
            bondCount: UInt64,
            createdAt: UFix64,
            lastConsolidatedAt: UFix64
        ) {
            self.id = id
            self.atomIds = atomIds
            self.stability = stability
            self.topic = topic
            self.bondCount = bondCount
            self.createdAt = createdAt
            self.lastConsolidatedAt = lastConsolidatedAt
        }
    }

    // -----------------------------------------------------------------------
    // DreamCycleResult — output of a consolidation cycle
    // -----------------------------------------------------------------------
    access(all) struct DreamCycleResult {
        access(all) let memoriesConsolidated: UInt64
        access(all) let bondsCreated: UInt64
        access(all) let memoriesPruned: UInt64
        access(all) let moleculesFormed: UInt64
        access(all) let promotions: UInt64
        access(all) let timestamp: UFix64

        init(
            memoriesConsolidated: UInt64,
            bondsCreated: UInt64,
            memoriesPruned: UInt64,
            moleculesFormed: UInt64,
            promotions: UInt64,
            timestamp: UFix64
        ) {
            self.memoriesConsolidated = memoriesConsolidated
            self.bondsCreated = bondsCreated
            self.memoriesPruned = memoriesPruned
            self.moleculesFormed = moleculesFormed
            self.promotions = promotions
            self.timestamp = timestamp
        }
    }

    // -----------------------------------------------------------------------
    // CognitiveVault — the cognitive layer resource
    // -----------------------------------------------------------------------
    access(all) resource CognitiveVault {
        // Cognitive metadata indexed by AgentMemory entry ID
        access(self) var entries: {UInt64: CognitiveEntry}

        // Bond graph: memory ID → array of bonds FROM this memory
        access(self) var bonds: {UInt64: [MemoryBond]}

        // Reverse bond index: memory ID → array of memory IDs that bond TO it
        access(self) var reverseBonds: {UInt64: [UInt64]}

        // Molecules: cluster ID → Molecule
        access(self) var molecules: {UInt64: Molecule}

        // Type index: memory type → [memory IDs] for fast type-based queries
        access(self) var typeIndex: {UInt8: [UInt64]}

        // Dream cycle history
        access(self) var dreamHistory: [DreamCycleResult]

        // Counters
        access(self) var moleculeCounter: UInt64
        access(all) var totalCognitiveEntries: UInt64
        access(all) var totalBonds: UInt64
        access(all) var totalMolecules: UInt64
        access(all) var lastDreamCycleAt: UFix64

        init() {
            self.entries = {}
            self.bonds = {}
            self.reverseBonds = {}
            self.molecules = {}
            self.typeIndex = {0: [], 1: [], 2: [], 3: []}
            self.dreamHistory = []
            self.moleculeCounter = 0
            self.totalCognitiveEntries = 0
            self.totalBonds = 0
            self.totalMolecules = 0
            self.lastDreamCycleAt = 0.0
        }

        // ---------------------------------------------------------------
        // Cognize: Store cognitive metadata for a memory
        // ---------------------------------------------------------------
        access(Cognize) fun storeCognitive(
            memoryId: UInt64,
            memoryType: UInt8,
            importance: UInt8,
            emotionalWeight: UInt8
        ) {
            let now = getCurrentBlock().timestamp

            let entry = CognitiveEntry(
                memoryId: memoryId,
                memoryType: memoryType,
                importance: importance,
                strength: 1.0,  // Starts at full strength
                emotionalWeight: emotionalWeight,
                moleculeId: 0,  // Unassigned
                bondCount: 0,
                promotedFrom: 255,  // Never promoted
                lastDecayAt: now,
                createdAt: now
            )

            self.entries[memoryId] = entry

            // Update type index
            if self.typeIndex[memoryType] == nil {
                self.typeIndex[memoryType] = [memoryId]
            } else {
                self.typeIndex[memoryType]!.append(memoryId)
            }

            self.totalCognitiveEntries = self.totalCognitiveEntries + 1

            emit CognitiveMemoryStored(
                memoryId: memoryId,
                memoryType: memoryType,
                importance: importance,
                owner: self.owner!.address
            )
        }

        // ---------------------------------------------------------------
        // Bond: Create a typed bond between two memories
        // ---------------------------------------------------------------
        access(Bond) fun createBond(
            fromMemoryId: UInt64,
            toMemoryId: UInt64,
            bondType: UInt8,
            strength: UFix64
        ) {
            pre {
                self.entries[fromMemoryId] != nil: "Source memory not in cognitive vault"
                self.entries[toMemoryId] != nil: "Target memory not in cognitive vault"
            }

            let now = getCurrentBlock().timestamp

            let bond = MemoryBond(
                fromMemoryId: fromMemoryId,
                toMemoryId: toMemoryId,
                bondType: bondType,
                strength: strength,
                createdAt: now
            )

            // Forward bond
            if self.bonds[fromMemoryId] == nil {
                self.bonds[fromMemoryId] = [bond]
            } else {
                // Check max bonds per memory (10, as recommended)
                if self.bonds[fromMemoryId]!.length < 10 {
                    self.bonds[fromMemoryId]!.append(bond)
                }
            }

            // Reverse index
            if self.reverseBonds[toMemoryId] == nil {
                self.reverseBonds[toMemoryId] = [fromMemoryId]
            } else {
                self.reverseBonds[toMemoryId]!.append(fromMemoryId)
            }

            // Update bond counts on cognitive entries
            if let fromEntry = self.entries[fromMemoryId] {
                self.entries[fromMemoryId] = CognitiveEntry(
                    memoryId: fromEntry.memoryId,
                    memoryType: fromEntry.memoryType,
                    importance: fromEntry.importance,
                    strength: fromEntry.strength,
                    emotionalWeight: fromEntry.emotionalWeight,
                    moleculeId: fromEntry.moleculeId,
                    bondCount: fromEntry.bondCount + 1,
                    promotedFrom: fromEntry.promotedFrom,
                    lastDecayAt: fromEntry.lastDecayAt,
                    createdAt: fromEntry.createdAt
                )
            }

            self.totalBonds = self.totalBonds + 1

            emit BondCreated(
                fromMemoryId: fromMemoryId,
                toMemoryId: toMemoryId,
                bondType: bondType,
                strength: strength
            )
        }

        // ---------------------------------------------------------------
        // Molecular Retrieval: traverse bonds from a seed memory
        // Returns the molecule cluster — semantically coherent group
        // O(k) where k = avg bonds per memory (~3-5)
        // ---------------------------------------------------------------
        access(Introspect) fun getMolecularCluster(
            seedMemoryId: UInt64,
            maxDepth: UInt8
        ): [UInt64] {
            var visited: {UInt64: Bool} = {}
            var result: [UInt64] = []
            var queue: [UInt64] = [seedMemoryId]
            var depth: UInt8 = 0

            while queue.length > 0 && depth < maxDepth {
                var nextQueue: [UInt64] = []

                for memId in queue {
                    if visited[memId] != nil {
                        continue
                    }
                    visited[memId] = true
                    result.append(memId)

                    // Traverse forward bonds
                    if let memBonds = self.bonds[memId] {
                        for bond in memBonds {
                            if visited[bond.toMemoryId] == nil {
                                nextQueue.append(bond.toMemoryId)
                            }
                        }
                    }

                    // Traverse reverse bonds
                    if let revBonds = self.reverseBonds[memId] {
                        for fromId in revBonds {
                            if visited[fromId] == nil {
                                nextQueue.append(fromId)
                            }
                        }
                    }
                }

                queue = nextQueue
                depth = depth + 1
            }

            return result
        }

        // ---------------------------------------------------------------
        // Introspect: Read cognitive metadata
        // ---------------------------------------------------------------
        access(Introspect) fun getCognitive(memoryId: UInt64): CognitiveEntry? {
            return self.entries[memoryId]
        }

        access(Introspect) fun getByType(memoryType: UInt8): [UInt64] {
            return self.typeIndex[memoryType] ?? []
        }

        access(Introspect) fun getBonds(memoryId: UInt64): [MemoryBond] {
            return self.bonds[memoryId] ?? []
        }

        access(Introspect) fun getMolecule(moleculeId: UInt64): Molecule? {
            return self.molecules[moleculeId]
        }

        access(Introspect) fun getAllMolecules(): [Molecule] {
            var result: [Molecule] = []
            for id in self.molecules.keys {
                if let mol = self.molecules[id] {
                    result.append(mol)
                }
            }
            return result
        }

        access(Introspect) fun getAllCognitiveEntries(): [CognitiveEntry] {
            var result: [CognitiveEntry] = []
            for id in self.entries.keys {
                if let entry = self.entries[id] {
                    result.append(entry)
                }
            }
            return result
        }

        access(Introspect) fun getDreamHistory(): [DreamCycleResult] {
            return self.dreamHistory
        }

        // ---------------------------------------------------------------
        // Dream Cycle: Consolidation, decay, promotion, pruning
        // This is the "sleep" phase — called periodically to maintain
        // memory health. On Flow, this can be triggered by scheduled tx.
        // ---------------------------------------------------------------
        access(Dream) fun runDreamCycle(
            decayThreshold: UFix64,
            promotionThreshold: UInt64
        ): DreamCycleResult {
            let now = getCurrentBlock().timestamp
            var consolidated: UInt64 = 0
            var bondsCreated: UInt64 = 0
            var pruned: UInt64 = 0
            var moleculesFormed: UInt64 = 0
            var promotions: UInt64 = 0

            // --- Phase 1: Decay ---
            // Apply time-based decay to all memories based on type
            let memoryIds = self.entries.keys
            var toRemove: [UInt64] = []

            for memId in memoryIds {
                if let entry = self.entries[memId] {
                    let decayRate = CognitiveMemory.getDecayRate(entry.memoryType)
                    let daysSinceLastDecay = (now - entry.lastDecayAt) / 86400.0

                    if daysSinceLastDecay > 0.0 {
                        // Apply decay: strength = strength * (1 - decayRate)^days
                        // Simplified on-chain: strength -= decayRate * days
                        var newStrength = entry.strength - (decayRate * daysSinceLastDecay)

                        // Bond-based retention: connected memories decay slower
                        // Each bond adds 10% decay resistance
                        if entry.bondCount > 0 {
                            let bondBonus = UFix64(entry.bondCount) * 0.1
                            let retained = decayRate * daysSinceLastDecay * (bondBonus > 1.0 ? 1.0 : bondBonus)
                            newStrength = newStrength + retained
                        }

                        // Importance-based retention
                        if entry.importance >= 8 {
                            newStrength = newStrength + (decayRate * daysSinceLastDecay * 0.5)
                        }

                        // Clamp
                        if newStrength < 0.0 {
                            newStrength = 0.0
                        }
                        if newStrength > 1.0 {
                            newStrength = 1.0
                        }

                        // Update entry
                        self.entries[memId] = CognitiveEntry(
                            memoryId: entry.memoryId,
                            memoryType: entry.memoryType,
                            importance: entry.importance,
                            strength: newStrength,
                            emotionalWeight: entry.emotionalWeight,
                            moleculeId: entry.moleculeId,
                            bondCount: entry.bondCount,
                            promotedFrom: entry.promotedFrom,
                            lastDecayAt: now,
                            createdAt: entry.createdAt
                        )

                        consolidated = consolidated + 1

                        // Mark for pruning if below threshold and isolated
                        if newStrength < decayThreshold && entry.bondCount == 0 {
                            toRemove.append(memId)
                        }

                        emit MemoryDecayed(memoryId: memId, newStrength: newStrength)
                    }
                }
            }

            // --- Phase 2: Prune isolated weak memories ---
            for memId in toRemove {
                if let entry = self.entries[memId] {
                    // Remove from type index
                    if var typeIds = self.typeIndex[entry.memoryType] {
                        var newIds: [UInt64] = []
                        for id in typeIds {
                            if id != memId {
                                newIds.append(id)
                            }
                        }
                        self.typeIndex[entry.memoryType] = newIds
                    }
                    self.entries.remove(key: memId)
                    self.totalCognitiveEntries = self.totalCognitiveEntries - 1
                    pruned = pruned + 1
                }
            }

            // --- Phase 3: Auto-molecule detection ---
            // Find densely connected memory clusters that aren't yet in a molecule
            for memId in self.entries.keys {
                if let entry = self.entries[memId] {
                    if entry.moleculeId == 0 && entry.bondCount >= 2 {
                        // This memory has bonds but no molecule — try to form one
                        let cluster = self.getMolecularCluster(seedMemoryId: memId, maxDepth: 2)
                        if cluster.length >= 3 {
                            // Form a new molecule
                            self.moleculeCounter = self.moleculeCounter + 1
                            let molId = self.moleculeCounter

                            // Count internal bonds
                            var internalBonds: UInt64 = 0
                            for atomId in cluster {
                                if let atomBonds = self.bonds[atomId] {
                                    for bond in atomBonds {
                                        // Check if target is in cluster
                                        for targetId in cluster {
                                            if bond.toMemoryId == targetId {
                                                internalBonds = internalBonds + 1
                                            }
                                        }
                                    }
                                }
                            }

                            // Stability = internal bonds / (atoms * max_bonds_per_atom)
                            let maxPossible = UFix64(cluster.length) * 10.0
                            let stability = maxPossible > 0.0
                                ? UFix64(internalBonds) / maxPossible
                                : 0.0

                            let molecule = Molecule(
                                id: molId,
                                atomIds: cluster,
                                stability: stability > 1.0 ? 1.0 : stability,
                                topic: "",  // Set by relay after analysis
                                bondCount: internalBonds,
                                createdAt: now,
                                lastConsolidatedAt: now
                            )

                            self.molecules[molId] = molecule
                            self.totalMolecules = self.totalMolecules + 1
                            moleculesFormed = moleculesFormed + 1

                            // Assign molecule ID to all atoms
                            for atomId in cluster {
                                if let atom = self.entries[atomId] {
                                    self.entries[atomId] = CognitiveEntry(
                                        memoryId: atom.memoryId,
                                        memoryType: atom.memoryType,
                                        importance: atom.importance,
                                        strength: atom.strength,
                                        emotionalWeight: atom.emotionalWeight,
                                        moleculeId: molId,
                                        bondCount: atom.bondCount,
                                        promotedFrom: atom.promotedFrom,
                                        lastDecayAt: atom.lastDecayAt,
                                        createdAt: atom.createdAt
                                    )
                                }
                            }

                            emit MoleculeFormed(
                                moleculeId: molId,
                                atomCount: UInt64(cluster.length),
                                stability: stability > 1.0 ? 1.0 : stability,
                                owner: self.owner!.address
                            )
                        }
                    }
                }
            }

            // --- Phase 4: Promotion detection ---
            // If multiple episodic memories share tags/keys, promote to semantic
            // (This is done primarily in the relay with LLM analysis,
            //  but we track the promotion on-chain)

            let result = DreamCycleResult(
                memoriesConsolidated: consolidated,
                bondsCreated: bondsCreated,
                memoriesPruned: pruned,
                moleculesFormed: moleculesFormed,
                promotions: promotions,
                timestamp: now
            )

            self.dreamHistory.append(result)
            self.lastDreamCycleAt = now

            emit DreamCycleCompleted(
                memoriesConsolidated: consolidated,
                bondsCreated: bondsCreated,
                memoriesPruned: pruned,
                owner: self.owner!.address
            )

            return result
        }

        // ---------------------------------------------------------------
        // Promote: Change a memory's type (episodic → semantic, etc.)
        // Called by relay when patterns are detected
        // ---------------------------------------------------------------
        access(Dream) fun promoteMemory(
            memoryId: UInt64,
            newType: UInt8,
            newImportance: UInt8
        ) {
            pre {
                self.entries[memoryId] != nil: "Memory not found"
                newType <= 3: "Invalid memory type"
            }

            if let entry = self.entries[memoryId] {
                let oldType = entry.memoryType

                // Remove from old type index
                if var typeIds = self.typeIndex[oldType] {
                    var newIds: [UInt64] = []
                    for id in typeIds {
                        if id != memoryId {
                            newIds.append(id)
                        }
                    }
                    self.typeIndex[oldType] = newIds
                }

                // Add to new type index
                if self.typeIndex[newType] == nil {
                    self.typeIndex[newType] = [memoryId]
                } else {
                    self.typeIndex[newType]!.append(memoryId)
                }

                // Update entry
                self.entries[memoryId] = CognitiveEntry(
                    memoryId: entry.memoryId,
                    memoryType: newType,
                    importance: newImportance,
                    strength: 1.0,  // Reset strength on promotion
                    emotionalWeight: entry.emotionalWeight,
                    moleculeId: entry.moleculeId,
                    bondCount: entry.bondCount,
                    promotedFrom: oldType,
                    lastDecayAt: getCurrentBlock().timestamp,
                    createdAt: entry.createdAt
                )

                emit MemoryPromoted(
                    memoryId: memoryId,
                    fromType: oldType,
                    toType: newType
                )
            }
        }
    }

    // -----------------------------------------------------------------------
    // Public factory
    // -----------------------------------------------------------------------
    access(all) fun createCognitiveVault(): @CognitiveVault {
        return <- create CognitiveVault()
    }

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    init() {
        self.CognitiveVaultStoragePath = /storage/FlowClawCognitiveVault
    }
}
