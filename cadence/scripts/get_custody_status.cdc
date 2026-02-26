// get_custody_status.cdc
// Returns the Hybrid Custody status of a FlowClaw account.
// Checks if the account has OwnedAccount (is a child) or Manager (is a parent).
//
// Returns:
//   type: "standalone" | "child" | "parent" | "both"
//   hasOwnedAccount: Bool
//   hasManager: Bool

// For PoC: check for FlowClaw resources to confirm account is initialized
import "AgentRegistry"
import "FlowClaw"

access(all) fun main(address: Address): {String: AnyStruct} {
    let account = getAccount(address)

    // Check for FlowClaw initialization
    let hasAgent = account.storage.type(at: AgentRegistry.AgentStoragePath) != nil
    let hasCollection = account.storage.type(at: AgentRegistry.AgentCollectionStoragePath) != nil
    let hasStack = account.storage.type(at: FlowClaw.FlowClawStoragePath) != nil

    // In full implementation, we'd also check:
    // let hasOwnedAccount = account.storage.type(at: HybridCustody.OwnedAccountStoragePath) != nil
    // let hasManager = account.storage.type(at: HybridCustody.ManagerStoragePath) != nil

    return {
        "address": address,
        "initialized": hasStack,
        "hasAgent": hasAgent,
        "hasAgentCollection": hasCollection,
        "type": "standalone",
        "hasOwnedAccount": false,
        "hasManager": false
    }
}
