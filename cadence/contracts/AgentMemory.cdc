// AgentMemory.cdc
// Per-account persistent memory for AI agents on Flow.
// Implements a key-value store with tagging and search support.
// Memory is private by default — only the account owner can read/write.
// Supports hybrid search: exact key lookup + tag-based filtering.

access(all) contract AgentMemory {

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    access(all) event MemoryStored(memoryId: UInt64, key: String, owner: Address)
    access(all) event MemoryUpdated(memoryId: UInt64, key: String)
    access(all) event MemoryDeleted(memoryId: UInt64, key: String)
    access(all) event MemorySearched(owner: Address, query: String, resultsCount: UInt64)

    // -----------------------------------------------------------------------
    // Paths
    // -----------------------------------------------------------------------
    access(all) let MemoryVaultStoragePath: StoragePath

    // -----------------------------------------------------------------------
    // Entitlements
    // -----------------------------------------------------------------------
    access(all) entitlement Store
    access(all) entitlement Recall
    access(all) entitlement Forget

    // -----------------------------------------------------------------------
    // MemoryEntry — a single piece of stored knowledge
    // -----------------------------------------------------------------------
    access(all) struct MemoryEntry {
        access(all) let id: UInt64
        access(all) let key: String            // Topic/identifier
        access(all) let content: String        // The actual memory content
        access(all) let contentHash: String    // SHA-256 for verification
        access(all) let tags: [String]         // Categorization tags
        access(all) let source: String         // Where this memory came from (session, manual, etc.)
        access(all) let createdAt: UFix64
        access(all) let updatedAt: UFix64
        access(all) let accessCount: UInt64    // How many times recalled

        init(
            id: UInt64,
            key: String,
            content: String,
            contentHash: String,
            tags: [String],
            source: String,
            createdAt: UFix64,
            updatedAt: UFix64,
            accessCount: UInt64
        ) {
            self.id = id
            self.key = key
            self.content = content
            self.contentHash = contentHash
            self.tags = tags
            self.source = source
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.accessCount = accessCount
        }
    }

    // -----------------------------------------------------------------------
    // MemoryVault — the per-account memory store
    // -----------------------------------------------------------------------
    access(all) resource MemoryVault {
        access(self) var entries: {UInt64: MemoryEntry}
        access(self) var keyIndex: {String: UInt64}       // key -> memoryId
        access(self) var tagIndex: {String: [UInt64]}     // tag -> [memoryIds]
        access(self) var entryCounter: UInt64
        access(all) var totalEntries: UInt64

        init() {
            self.entries = {}
            self.keyIndex = {}
            self.tagIndex = {}
            self.entryCounter = 0
            self.totalEntries = 0
        }

        // --- Store: add/update memories ---
        access(Store) fun store(
            key: String,
            content: String,
            contentHash: String,
            tags: [String],
            source: String
        ): UInt64 {
            let now = getCurrentBlock().timestamp

            // Update existing entry if key exists
            if let existingId = self.keyIndex[key] {
                if let existing = self.entries[existingId] {
                    let updated = MemoryEntry(
                        id: existingId,
                        key: key,
                        content: content,
                        contentHash: contentHash,
                        tags: tags,
                        source: source,
                        createdAt: existing.createdAt,
                        updatedAt: now,
                        accessCount: existing.accessCount
                    )
                    self.entries[existingId] = updated
                    // Update tag index
                    self.removeFromTagIndex(memoryId: existingId, tags: existing.tags)
                    self.addToTagIndex(memoryId: existingId, tags: tags)
                    emit MemoryUpdated(memoryId: existingId, key: key)
                    return existingId
                }
            }

            // Create new entry
            self.entryCounter = self.entryCounter + 1
            let memoryId = self.entryCounter

            let entry = MemoryEntry(
                id: memoryId,
                key: key,
                content: content,
                contentHash: contentHash,
                tags: tags,
                source: source,
                createdAt: now,
                updatedAt: now,
                accessCount: 0
            )

            self.entries[memoryId] = entry
            self.keyIndex[key] = memoryId
            self.addToTagIndex(memoryId: memoryId, tags: tags)
            self.totalEntries = self.totalEntries + 1

            emit MemoryStored(memoryId: memoryId, key: key, owner: self.owner!.address)
            return memoryId
        }

        // --- Recall: search and retrieve memories ---
        access(Recall) fun getByKey(key: String): MemoryEntry? {
            if let memoryId = self.keyIndex[key] {
                if let entry = self.entries[memoryId] {
                    // Increment access count
                    let updated = MemoryEntry(
                        id: entry.id,
                        key: entry.key,
                        content: entry.content,
                        contentHash: entry.contentHash,
                        tags: entry.tags,
                        source: entry.source,
                        createdAt: entry.createdAt,
                        updatedAt: entry.updatedAt,
                        accessCount: entry.accessCount + 1
                    )
                    self.entries[memoryId] = updated
                    return updated
                }
            }
            return nil
        }

        access(Recall) fun getByTag(tag: String): [MemoryEntry] {
            var results: [MemoryEntry] = []
            if let memoryIds = self.tagIndex[tag] {
                for id in memoryIds {
                    if let entry = self.entries[id] {
                        results.append(entry)
                    }
                }
            }
            emit MemorySearched(
                owner: self.owner!.address,
                query: "tag:".concat(tag),
                resultsCount: UInt64(results.length)
            )
            return results
        }

        access(Recall) fun getById(memoryId: UInt64): MemoryEntry? {
            return self.entries[memoryId]
        }

        access(Recall) fun getAllKeys(): [String] {
            return self.keyIndex.keys
        }

        access(Recall) fun getAllTags(): [String] {
            return self.tagIndex.keys
        }

        access(Recall) fun getRecent(limit: Int): [MemoryEntry] {
            // Return most recent entries (by updatedAt)
            var allEntries: [MemoryEntry] = []
            for id in self.entries.keys {
                if let entry = self.entries[id] {
                    allEntries.append(entry)
                }
            }
            // Simple sort by updatedAt descending (bubble sort for on-chain simplicity)
            var i = 0
            while i < allEntries.length {
                var j = 0
                while j < allEntries.length - 1 - i {
                    if allEntries[j].updatedAt < allEntries[j + 1].updatedAt {
                        let temp = allEntries[j]
                        allEntries[j] = allEntries[j + 1]
                        allEntries[j + 1] = temp
                    }
                    j = j + 1
                }
                i = i + 1
            }
            if allEntries.length <= limit {
                return allEntries
            }
            return allEntries.slice(from: 0, upTo: limit)
        }

        // --- Forget: delete memories ---
        access(Forget) fun deleteByKey(key: String): Bool {
            if let memoryId = self.keyIndex[key] {
                if let entry = self.entries[memoryId] {
                    self.removeFromTagIndex(memoryId: memoryId, tags: entry.tags)
                    self.entries.remove(key: memoryId)
                    self.keyIndex.remove(key: key)
                    self.totalEntries = self.totalEntries - 1
                    emit MemoryDeleted(memoryId: memoryId, key: key)
                    return true
                }
            }
            return false
        }

        access(Forget) fun deleteById(memoryId: UInt64): Bool {
            if let entry = self.entries[memoryId] {
                self.removeFromTagIndex(memoryId: memoryId, tags: entry.tags)
                self.keyIndex.remove(key: entry.key)
                self.entries.remove(key: memoryId)
                self.totalEntries = self.totalEntries - 1
                emit MemoryDeleted(memoryId: memoryId, key: entry.key)
                return true
            }
            return false
        }

        // --- Internal helpers ---
        access(self) fun addToTagIndex(memoryId: UInt64, tags: [String]) {
            for tag in tags {
                if self.tagIndex[tag] == nil {
                    self.tagIndex[tag] = [memoryId]
                } else {
                    self.tagIndex[tag]!.append(memoryId)
                }
            }
        }

        access(self) fun removeFromTagIndex(memoryId: UInt64, tags: [String]) {
            for tag in tags {
                if var ids = self.tagIndex[tag] {
                    var newIds: [UInt64] = []
                    for id in ids {
                        if id != memoryId {
                            newIds.append(id)
                        }
                    }
                    if newIds.length == 0 {
                        self.tagIndex.remove(key: tag)
                    } else {
                        self.tagIndex[tag] = newIds
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Public factory
    // -----------------------------------------------------------------------
    access(all) fun createMemoryVault(): @MemoryVault {
        return <- create MemoryVault()
    }

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    init() {
        self.MemoryVaultStoragePath = /storage/FlowClawMemoryVault
    }
}
