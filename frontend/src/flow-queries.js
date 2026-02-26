// FlowClaw — FCL Query Helpers
// Direct on-chain reads via FCL, bypassing relay for faster response.
// These queries are free (no gas) and return real-time data.

import { fcl } from "./flow-config";

/**
 * Query FLOW balance for an address.
 * @param {string} address - Flow address (0x prefixed)
 * @returns {string} UFix64 balance string
 */
export async function queryBalance(address) {
  try {
    const balance = await fcl.query({
      cadence: `
        access(all) fun main(addr: Address): UFix64 {
          let account = getAccount(addr)
          return account.balance
        }
      `,
      args: (arg, t) => [arg(address, t.Address)],
    });
    return balance;
  } catch (err) {
    console.error("queryBalance failed:", err);
    return "0.0";
  }
}

/**
 * Query agent configuration from AgentRegistry.
 * @param {string} address - Owner's Flow address
 * @returns {object|null} Agent config or null
 */
export async function queryAgentConfig(address) {
  try {
    const result = await fcl.query({
      cadence: `
        import AgentRegistry from 0xFlowClaw

        access(all) fun main(addr: Address): {String: AnyStruct}? {
          let cap = getAccount(addr).capabilities
            .borrow<&AgentRegistry.AgentConfig>(/public/FlowClawAgentConfig)
          if cap == nil { return nil }
          return {
            "name": cap!.name,
            "description": cap!.description,
            "provider": cap!.provider,
            "model": cap!.model,
            "totalSessions": cap!.totalSessions,
            "totalInferences": cap!.totalInferences
          }
        }
      `,
      args: (arg, t) => [arg(address, t.Address)],
    });
    return result;
  } catch (err) {
    console.error("queryAgentConfig failed:", err);
    return null;
  }
}

/**
 * Query global FlowClaw contract stats.
 * @returns {object|null} Stats or null
 */
export async function queryGlobalStats() {
  try {
    const result = await fcl.query({
      cadence: `
        import AgentRegistry from 0xFlowClaw

        access(all) fun main(): {String: UInt64} {
          return {
            "totalAgents": AgentRegistry.totalAgents,
            "totalSessions": AgentRegistry.totalSessions,
            "totalInferences": AgentRegistry.totalInferences
          }
        }
      `,
    });
    return result;
  } catch (err) {
    console.error("queryGlobalStats failed:", err);
    return null;
  }
}

/**
 * Query the number of memories stored for an address.
 * @param {string} address - Owner's Flow address
 * @returns {number} Memory count
 */
export async function queryMemoryCount(address) {
  try {
    const result = await fcl.query({
      cadence: `
        import CognitiveMemory from 0xFlowClaw

        access(all) fun main(addr: Address): Int {
          let cap = getAccount(addr).capabilities
            .borrow<&CognitiveMemory.MemoryStore>(/public/FlowClawCognitiveMemory)
          if cap == nil { return 0 }
          return cap!.getMemoryCount()
        }
      `,
      args: (arg, t) => [arg(address, t.Address)],
    });
    return parseInt(result) || 0;
  } catch (err) {
    console.error("queryMemoryCount failed:", err);
    return 0;
  }
}

/**
 * Check if an account has FlowClaw resources initialized.
 * @param {string} address - Flow address
 * @returns {boolean}
 */
export async function isAccountInitialized(address) {
  try {
    const result = await fcl.query({
      cadence: `
        import AgentRegistry from 0xFlowClaw

        access(all) fun main(addr: Address): Bool {
          return getAccount(addr).capabilities
            .borrow<&AgentRegistry.AgentConfig>(/public/FlowClawAgentConfig) != nil
        }
      `,
      args: (arg, t) => [arg(address, t.Address)],
    });
    return result === true;
  } catch {
    return false;
  }
}

/**
 * Execute an arbitrary read-only Cadence script via FCL.
 * @param {string} cadenceCode - Cadence script source
 * @param {Array} args - FCL args function
 * @returns {any} Result
 */
export async function executeScript(cadenceCode, args = []) {
  return fcl.query({
    cadence: cadenceCode,
    args: args.length > 0 ? (arg, t) => args.map(a => arg(a.value, t[a.type])) : undefined,
  });
}
