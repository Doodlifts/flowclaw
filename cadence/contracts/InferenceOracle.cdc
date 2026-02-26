// InferenceOracle.cdc
// The bridge between on-chain agent state and off-chain LLM inference.
// Authorized relays listen for InferenceRequested events, call the provider,
// and post results back via completeInference transactions.
// Each account authorizes their own relay keys — nobody else can post to your sessions.

import "AgentRegistry"
import "AgentSession"

access(all) contract InferenceOracle {

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    access(all) event RelayRegistered(relayAddress: Address, owner: Address)
    access(all) event RelayRevoked(relayAddress: Address, owner: Address)
    access(all) event InferenceRelayed(requestId: UInt64, relayAddress: Address)
    access(all) event InferenceFailed(requestId: UInt64, reason: String)
    access(all) event ToolExecutionRequested(
        requestId: UInt64,
        sessionId: UInt64,
        toolName: String,
        inputHash: String,
        owner: Address
    )
    access(all) event ToolExecutionCompleted(
        requestId: UInt64,
        toolName: String,
        outputHash: String
    )

    // -----------------------------------------------------------------------
    // Paths
    // -----------------------------------------------------------------------
    access(all) let OracleConfigStoragePath: StoragePath

    // -----------------------------------------------------------------------
    // Entitlements
    // -----------------------------------------------------------------------
    access(all) entitlement ManageRelays
    access(all) entitlement Relay

    // -----------------------------------------------------------------------
    // RelayAuthorization — proof that a relay is allowed to post for an account
    // -----------------------------------------------------------------------
    access(all) struct RelayAuth {
        access(all) let relayAddress: Address
        access(all) let authorizedAt: UFix64
        access(all) let label: String            // human-readable label
        access(all) var isActive: Bool

        init(relayAddress: Address, label: String) {
            self.relayAddress = relayAddress
            self.authorizedAt = getCurrentBlock().timestamp
            self.label = label
            self.isActive = true
        }
    }

    // -----------------------------------------------------------------------
    // ToolCall — represents a tool invocation from an LLM response
    // -----------------------------------------------------------------------
    access(all) struct ToolCall {
        access(all) let toolCallId: String
        access(all) let toolName: String
        access(all) let input: String          // JSON-encoded input
        access(all) let inputHash: String

        init(toolCallId: String, toolName: String, input: String, inputHash: String) {
            self.toolCallId = toolCallId
            self.toolName = toolName
            self.input = input
            self.inputHash = inputHash
        }
    }

    // -----------------------------------------------------------------------
    // OracleConfig — per-account relay management
    // -----------------------------------------------------------------------
    access(all) resource OracleConfig {
        access(self) var authorizedRelays: {Address: RelayAuth}
        access(self) var completedRequests: {UInt64: Bool}    // dedup tracking

        init() {
            self.authorizedRelays = {}
            self.completedRequests = {}
        }

        // --- Manage relays ---
        access(ManageRelays) fun authorizeRelay(relayAddress: Address, label: String) {
            self.authorizedRelays[relayAddress] = RelayAuth(
                relayAddress: relayAddress,
                label: label
            )
            emit RelayRegistered(relayAddress: relayAddress, owner: self.owner!.address)
        }

        access(ManageRelays) fun revokeRelay(relayAddress: Address) {
            self.authorizedRelays.remove(key: relayAddress)
            emit RelayRevoked(relayAddress: relayAddress, owner: self.owner!.address)
        }

        access(all) fun isRelayAuthorized(relayAddress: Address): Bool {
            if let relayAuth = self.authorizedRelays[relayAddress] {
                return relayAuth.isActive
            }
            return false
        }

        access(all) fun getAuthorizedRelays(): {Address: RelayAuth} {
            return self.authorizedRelays
        }

        // --- Deduplication ---
        access(Relay) fun markRequestCompleted(requestId: UInt64) {
            self.completedRequests[requestId] = true
        }

        access(all) fun isRequestCompleted(requestId: UInt64): Bool {
            return self.completedRequests[requestId] ?? false
        }
    }

    // -----------------------------------------------------------------------
    // Public factory
    // -----------------------------------------------------------------------
    access(all) fun createOracleConfig(): @OracleConfig {
        return <- create OracleConfig()
    }

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    init() {
        self.OracleConfigStoragePath = /storage/FlowClawOracleConfig
    }
}
