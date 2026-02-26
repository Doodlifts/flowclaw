// FlowDeFiTools.cdc
// EXAMPLE EXTENSION: Adds DeFi-specific tools to the agent.
//
// This demonstrates how someone in the Flow DeFi ecosystem can publish
// tools that any FlowClaw agent can install — without touching the base
// ToolRegistry contract.
//
// Tools added:
//   - swap_tokens: Execute a token swap via a DEX aggregator
//   - check_balance: Check FLOW/FT balances for any account
//   - get_pool_stats: Get liquidity pool statistics
//   - set_price_alert: Register a price alert (uses AgentScheduler)
//
// REQUIRED ENTITLEMENTS:
//   - Tools: ManageTools (to register new tools)
//   - Agent: Execute (to send transactions on behalf of the agent)
//   - Scheduler: Schedule (for price alerts)
//
// The extension CANNOT:
//   - Read other accounts' data
//   - Modify agent identity or security policy
//   - Access memory or sessions
//
// SECURITY NOTE: The swap_tokens tool has requiresApproval=true,
// meaning in supervised mode the user must confirm before execution.
// This is enforced by the base ToolRegistry contract, not by this extension.

import ToolRegistry from "../../contracts/ToolRegistry.cdc"
import AgentExtensions from "../../contracts/AgentExtensions.cdc"
import AgentLifecycleHooks from "../../contracts/AgentLifecycleHooks.cdc"

access(all) contract FlowDeFiTools {

    access(all) let EXTENSION_NAME: String
    access(all) let EXTENSION_VERSION: String

    access(all) fun getToolDefinitions(author: Address): [ToolRegistry.ToolDefinition] {
        return [
            ToolRegistry.ToolDefinition(
                name: "swap_tokens",
                description: "Execute a token swap via IncrementFi or other Flow DEX. Finds the best route and executes the swap.",
                category: "defi",
                parameters: [
                    ToolRegistry.ToolParameter(name: "from_token", description: "Token to swap from (e.g., 'FLOW', 'USDC')", type: "string", required: true, defaultValue: nil),
                    ToolRegistry.ToolParameter(name: "to_token", description: "Token to swap to", type: "string", required: true, defaultValue: nil),
                    ToolRegistry.ToolParameter(name: "amount", description: "Amount to swap", type: "number", required: true, defaultValue: nil),
                    ToolRegistry.ToolParameter(name: "slippage_bps", description: "Max slippage in basis points", type: "number", required: false, defaultValue: "50")
                ],
                returnsDescription: "Transaction ID, tokens received, effective price",
                isAsync: true,
                requiresApproval: true,  // MUST get user approval in supervised mode
                version: 1,
                registeredBy: author
            ),
            ToolRegistry.ToolDefinition(
                name: "check_balance",
                description: "Check FLOW or Fungible Token balance for any Flow account",
                category: "defi",
                parameters: [
                    ToolRegistry.ToolParameter(name: "address", description: "Flow account address", type: "string", required: true, defaultValue: nil),
                    ToolRegistry.ToolParameter(name: "token", description: "Token identifier (default: FLOW)", type: "string", required: false, defaultValue: "\"FLOW\"")
                ],
                returnsDescription: "Token balance as a decimal number",
                isAsync: true,
                requiresApproval: false,  // Read-only, safe
                version: 1,
                registeredBy: author
            ),
            ToolRegistry.ToolDefinition(
                name: "get_pool_stats",
                description: "Get liquidity pool statistics from Flow DEXs",
                category: "defi",
                parameters: [
                    ToolRegistry.ToolParameter(name: "pool", description: "Pool identifier (e.g., 'FLOW/USDC')", type: "string", required: true, defaultValue: nil)
                ],
                returnsDescription: "TVL, 24h volume, APR, token reserves",
                isAsync: true,
                requiresApproval: false,
                version: 1,
                registeredBy: author
            ),
            ToolRegistry.ToolDefinition(
                name: "set_price_alert",
                description: "Set a recurring price alert that checks token price and notifies you",
                category: "defi",
                parameters: [
                    ToolRegistry.ToolParameter(name: "token", description: "Token to monitor", type: "string", required: true, defaultValue: nil),
                    ToolRegistry.ToolParameter(name: "condition", description: "Alert condition: 'above' or 'below'", type: "string", required: true, defaultValue: nil),
                    ToolRegistry.ToolParameter(name: "price", description: "Price threshold", type: "number", required: true, defaultValue: nil),
                    ToolRegistry.ToolParameter(name: "check_interval_minutes", description: "How often to check", type: "number", required: false, defaultValue: "15")
                ],
                returnsDescription: "Scheduled task ID for the price alert",
                isAsync: true,
                requiresApproval: true,  // Creates a recurring task
                version: 1,
                registeredBy: author
            )
        ]
    }

    access(all) fun getMetadata(author: Address): AgentExtensions.ExtensionMetadata {
        return AgentExtensions.ExtensionMetadata(
            extensionId: 0,
            name: self.EXTENSION_NAME,
            description: "DeFi tools for Flow blockchain: token swaps, balance checks, pool stats, and price alerts. Integrates with IncrementFi and other Flow DEXs.",
            version: self.EXTENSION_VERSION,
            author: author,
            category: AgentExtensions.ExtensionCategory.tool,
            sourceHash: "sha256:def456...",
            requiredEntitlements: [
                AgentExtensions.RequiredEntitlement(
                    resource: "Tools",
                    entitlement: "ManageTools",
                    reason: "Register DeFi tools in the agent's tool collection"
                ),
                AgentExtensions.RequiredEntitlement(
                    resource: "Agent",
                    entitlement: "Execute",
                    reason: "Execute Flow transactions for swaps"
                ),
                AgentExtensions.RequiredEntitlement(
                    resource: "Scheduler",
                    entitlement: "Schedule",
                    reason: "Create recurring price alert tasks"
                )
            ],
            dependencies: [],
            tags: ["defi", "trading", "swap", "price", "flow", "tokens"],
            isAudited: false,
            toolDefinitions: self.getToolDefinitions(author: author),
            hookConfigs: []
        )
    }

    init() {
        self.EXTENSION_NAME = "flow-defi-tools"
        self.EXTENSION_VERSION = "1.0.0"
    }
}
