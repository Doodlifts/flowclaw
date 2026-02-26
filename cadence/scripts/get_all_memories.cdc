// get_all_memories.cdc
// Retrieve all memory entries for an account.
// Returns all stored memories with their metadata (keys, tags, content, etc).

import "AgentMemory"

access(all) struct AllMemoriesResult {
    access(all) let totalMemories: UInt64
    access(all) let memories: [AgentMemory.MemoryEntry]
    access(all) let keys: [String]
    access(all) let tags: [String]

    init(
        totalMemories: UInt64,
        memories: [AgentMemory.MemoryEntry],
        keys: [String],
        tags: [String]
    ) {
        self.totalMemories = totalMemories
        self.memories = memories
        self.keys = keys
        self.tags = tags
    }
}

access(all) fun main(address: Address): AllMemoriesResult {
    let account = getAuthAccount<auth(Storage) &Account>(address)

    var memories: [AgentMemory.MemoryEntry] = []
    var keys: [String] = []
    var tags: [String] = []
    var totalMemories: UInt64 = 0

    if let memoryVault = account.storage.borrow<&AgentMemory.MemoryVault>(
        from: AgentMemory.MemoryVaultStoragePath
    ) {
        totalMemories = memoryVault.totalEntries

        // Get all keys and retrieve their memory entries
        keys = memoryVault.getAllKeys()
        for key in keys {
            if let entry = memoryVault.getByKey(key: key) {
                memories.append(entry)
            }
        }

        // Get all tags
        tags = memoryVault.getAllTags()

        return AllMemoriesResult(
            totalMemories: totalMemories,
            memories: memories,
            keys: keys,
            tags: tags
        )
    }

    return AllMemoriesResult(totalMemories: 0, memories: [], keys: [], tags: [])
}
