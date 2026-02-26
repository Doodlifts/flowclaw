// get_molecular_cluster.cdc
// Traverses memory bonds from a seed memory to return a coherent molecule cluster.
// This is the core of O(k) molecular retrieval.

import CognitiveMemory from "../contracts/CognitiveMemory.cdc"

access(all) struct ClusterResult {
    access(all) let seedMemoryId: UInt64
    access(all) let memoryIds: [UInt64]
    access(all) let entries: [CognitiveMemory.CognitiveEntry]
    access(all) let bonds: [CognitiveMemory.MemoryBond]
    access(all) let clusterSize: Int

    init(
        seedMemoryId: UInt64,
        memoryIds: [UInt64],
        entries: [CognitiveMemory.CognitiveEntry],
        bonds: [CognitiveMemory.MemoryBond],
        clusterSize: Int
    ) {
        self.seedMemoryId = seedMemoryId
        self.memoryIds = memoryIds
        self.entries = entries
        self.bonds = bonds
        self.clusterSize = clusterSize
    }
}

access(all) fun main(address: Address, seedMemoryId: UInt64, maxDepth: UInt8): ClusterResult {
    let account = getAccount(address)

    if let vault = account.storage.borrow<auth(CognitiveMemory.Introspect) &CognitiveMemory.CognitiveVault>(
        from: CognitiveMemory.CognitiveVaultStoragePath
    ) {
        let clusterIds = vault.getMolecularCluster(seedMemoryId: seedMemoryId, maxDepth: maxDepth)

        var entries: [CognitiveMemory.CognitiveEntry] = []
        var allBonds: [CognitiveMemory.MemoryBond] = []

        for memId in clusterIds {
            if let entry = vault.getCognitive(memoryId: memId) {
                entries.append(entry)
            }
            let memBonds = vault.getBonds(memoryId: memId)
            for bond in memBonds {
                allBonds.append(bond)
            }
        }

        return ClusterResult(
            seedMemoryId: seedMemoryId,
            memoryIds: clusterIds,
            entries: entries,
            bonds: allBonds,
            clusterSize: clusterIds.length
        )
    }

    return ClusterResult(
        seedMemoryId: seedMemoryId,
        memoryIds: [],
        entries: [],
        bonds: [],
        clusterSize: 0
    )
}
