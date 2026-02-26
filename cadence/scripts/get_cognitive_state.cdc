// get_cognitive_state.cdc
// Returns full cognitive memory state: entries, bonds, molecules, dream history

import CognitiveMemory from "../contracts/CognitiveMemory.cdc"

access(all) struct CognitiveState {
    access(all) let totalEntries: UInt64
    access(all) let totalBonds: UInt64
    access(all) let totalMolecules: UInt64
    access(all) let lastDreamCycleAt: UFix64
    access(all) let entries: [CognitiveMemory.CognitiveEntry]
    access(all) let molecules: [CognitiveMemory.Molecule]
    access(all) let dreamHistory: [CognitiveMemory.DreamCycleResult]
    access(all) let episodicCount: Int
    access(all) let semanticCount: Int
    access(all) let proceduralCount: Int
    access(all) let selfModelCount: Int

    init(
        totalEntries: UInt64,
        totalBonds: UInt64,
        totalMolecules: UInt64,
        lastDreamCycleAt: UFix64,
        entries: [CognitiveMemory.CognitiveEntry],
        molecules: [CognitiveMemory.Molecule],
        dreamHistory: [CognitiveMemory.DreamCycleResult],
        episodicCount: Int,
        semanticCount: Int,
        proceduralCount: Int,
        selfModelCount: Int
    ) {
        self.totalEntries = totalEntries
        self.totalBonds = totalBonds
        self.totalMolecules = totalMolecules
        self.lastDreamCycleAt = lastDreamCycleAt
        self.entries = entries
        self.molecules = molecules
        self.dreamHistory = dreamHistory
        self.episodicCount = episodicCount
        self.semanticCount = semanticCount
        self.proceduralCount = proceduralCount
        self.selfModelCount = selfModelCount
    }
}

access(all) fun main(address: Address): CognitiveState {
    let account = getAccount(address)

    if let vault = account.storage.borrow<auth(CognitiveMemory.Introspect) &CognitiveMemory.CognitiveVault>(
        from: CognitiveMemory.CognitiveVaultStoragePath
    ) {
        return CognitiveState(
            totalEntries: vault.totalCognitiveEntries,
            totalBonds: vault.totalBonds,
            totalMolecules: vault.totalMolecules,
            lastDreamCycleAt: vault.lastDreamCycleAt,
            entries: vault.getAllCognitiveEntries(),
            molecules: vault.getAllMolecules(),
            dreamHistory: vault.getDreamHistory(),
            episodicCount: vault.getByType(memoryType: 0).length,
            semanticCount: vault.getByType(memoryType: 1).length,
            proceduralCount: vault.getByType(memoryType: 2).length,
            selfModelCount: vault.getByType(memoryType: 3).length
        )
    }

    return CognitiveState(
        totalEntries: 0,
        totalBonds: 0,
        totalMolecules: 0,
        lastDreamCycleAt: 0.0,
        entries: [],
        molecules: [],
        dreamHistory: [],
        episodicCount: 0,
        semanticCount: 0,
        proceduralCount: 0,
        selfModelCount: 0
    )
}
