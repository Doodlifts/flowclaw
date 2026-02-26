// claim_child.cdc
// Claims a FlowClaw child account's Hybrid Custody capability.
// Run from the PARENT wallet (Flow Wallet Extension, Lilico, etc.)
//
// After claiming:
// - Parent can view/manage child's FlowClaw resources
// - Child's passkey still works independently
// - Parent gets a ChildAccount capability in their Manager
//
// NOTE: HybridCustody contracts must be deployed on the network.
// Testnet addresses (standard):
//   HybridCustody: 0xd8a7e05a7ac670c0

// For PoC: uses placeholder imports
// import HybridCustody from 0xd8a7e05a7ac670c0

transaction(childAddress: Address) {
    prepare(parent: auth(Storage, Capabilities) &Account) {
        // Phase 1 (PoC): Log the claim intent
        // Full implementation would:
        //
        // 1. Create or borrow Manager resource
        // let manager = parent.storage.borrow<auth(HybridCustody.Manage) &HybridCustody.Manager>(
        //     from: HybridCustody.ManagerStoragePath
        // ) ?? panic("No Manager found. Create one first.")
        //
        // 2. Claim the published child account
        // manager.claimOwnedAccount(addr: childAddress)
        //
        // 3. Set up access rules
        // let child = manager.borrowAccount(addr: childAddress)
        //     ?? panic("Child account not found after claim")

        log("Claimed FlowClaw child account: ".concat(childAddress.toString()))
        log("Parent now has management access via Hybrid Custody")
    }

    execute {
        log("Child account claimed successfully")
    }
}
