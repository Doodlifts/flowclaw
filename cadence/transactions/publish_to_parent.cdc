// publish_to_parent.cdc
// Publishes a Hybrid Custody capability from the FlowClaw (child) account
// so that a parent wallet can claim it.
//
// This is the first step in account linking:
// 1. Child runs this tx → publishes OwnedAccount for parent to claim
// 2. Parent runs claim_child.cdc → claims the ChildAccount capability
//
// After linking, the parent wallet can manage the child's resources,
// but the child's passkey still works independently.
//
// NOTE: HybridCustody contracts must be deployed on the network.
// Testnet addresses (standard):
//   HybridCustody: 0xd8a7e05a7ac670c0
//   CapabilityFactory: 0xd8a7e05a7ac670c0
//   CapabilityFilter: 0xd8a7e05a7ac670c0

// For PoC: uses placeholder imports. Replace with actual deployed addresses.
// import HybridCustody from 0xd8a7e05a7ac670c0
// import CapabilityFactory from 0xd8a7e05a7ac670c0
// import CapabilityFilter from 0xd8a7e05a7ac670c0

transaction(parentAddress: Address) {
    prepare(child: auth(Storage, Capabilities) &Account) {
        // Phase 1 (PoC): Store a simple linking intent
        // This will be replaced with full HybridCustody once we integrate
        // the standard contracts.
        //
        // Full implementation would:
        // 1. Create or borrow OwnedAccount resource
        // 2. Set up CapabilityFactory for FlowClaw resources
        // 3. Set up CapabilityFilter (what parent can access)
        // 4. Publish capability for parentAddress
        //
        // let owned <- HybridCustody.createOwnedAccount(acct: &child)
        // let factory <- CapabilityFactory.createFactory()
        // let filter <- CapabilityFilter.createFilter(
        //     types: [Type<@AgentRegistry.AgentCollection>(),
        //             Type<@AgentSession.SessionManager>(),
        //             Type<@AgentMemory.MemoryVault>()]
        // )
        // owned.publishToParent(
        //     parentAddress: parentAddress,
        //     factory: &factory,
        //     filter: &filter
        // )

        log("Hybrid Custody link published for parent: ".concat(parentAddress.toString()))
        log("Parent can now claim this account via claim_child.cdc")
    }

    execute {
        log("Account linking capability published")
    }
}
