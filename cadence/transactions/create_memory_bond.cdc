// create_memory_bond.cdc
// Creates a typed molecular bond between two memories.
// Bond types: 0=causal, 1=semantic, 2=temporal, 3=contradictory

import CognitiveMemory from "../contracts/CognitiveMemory.cdc"

transaction(
    fromMemoryId: UInt64,
    toMemoryId: UInt64,
    bondType: UInt8,
    strength: UFix64
) {
    let cognitiveVault: auth(CognitiveMemory.Bond) &CognitiveMemory.CognitiveVault

    prepare(signer: auth(BorrowValue, SaveValue) &Account) {
        if signer.storage.borrow<&CognitiveMemory.CognitiveVault>(from: CognitiveMemory.CognitiveVaultStoragePath) == nil {
            signer.storage.save(<- CognitiveMemory.createCognitiveVault(), to: CognitiveMemory.CognitiveVaultStoragePath)
        }
        self.cognitiveVault = signer.storage.borrow<auth(CognitiveMemory.Bond) &CognitiveMemory.CognitiveVault>(
            from: CognitiveMemory.CognitiveVaultStoragePath
        ) ?? panic("Could not borrow CognitiveVault")
    }

    execute {
        self.cognitiveVault.createBond(
            fromMemoryId: fromMemoryId,
            toMemoryId: toMemoryId,
            bondType: bondType,
            strength: strength
        )
    }
}
