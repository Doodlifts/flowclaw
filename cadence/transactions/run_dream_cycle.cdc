// run_dream_cycle.cdc
// Triggers the dream cycle consolidation on the cognitive memory vault.
// Can be called manually or via Flow scheduled transactions.
// Performs: decay, pruning, auto-molecule formation, promotion tracking.

import CognitiveMemory from "../contracts/CognitiveMemory.cdc"

transaction(
    decayThreshold: UFix64,
    promotionThreshold: UInt64
) {
    let cognitiveVault: auth(CognitiveMemory.Dream, CognitiveMemory.Introspect) &CognitiveMemory.CognitiveVault

    prepare(signer: auth(BorrowValue) &Account) {
        self.cognitiveVault = signer.storage.borrow<auth(CognitiveMemory.Dream, CognitiveMemory.Introspect) &CognitiveMemory.CognitiveVault>(
            from: CognitiveMemory.CognitiveVaultStoragePath
        ) ?? panic("Could not borrow CognitiveVault with Dream entitlement")
    }

    execute {
        let result = self.cognitiveVault.runDreamCycle(
            decayThreshold: decayThreshold,
            promotionThreshold: promotionThreshold
        )

        log("Dream Cycle Complete:")
        log("  Memories consolidated: ".concat(result.memoriesConsolidated.toString()))
        log("  Bonds created: ".concat(result.bondsCreated.toString()))
        log("  Memories pruned: ".concat(result.memoriesPruned.toString()))
        log("  Molecules formed: ".concat(result.moleculesFormed.toString()))
        log("  Promotions: ".concat(result.promotions.toString()))
    }
}
