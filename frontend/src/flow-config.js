// FlowClaw — FCL Configuration
// Handles wallet connection for both testnet and mainnet

import * as fcl from "@onflow/fcl";

const NETWORK = import.meta.env.VITE_FLOW_NETWORK || "testnet";

const configs = {
  testnet: {
    "accessNode.api": "https://rest-testnet.onflow.org",
    "discovery.wallet": "https://fcl-discovery.onflow.org/testnet/authn",
    "flow.network": "testnet",
    "app.detail.title": "FlowClaw",
    "app.detail.icon": "https://flowclaw.app/icon.png",
    "0xFlowClaw": "0x808983d30a46aee2",
    "0xHybridCustody": "0xd8a7e05a7ac670c0",
    "0xCapabilityFactory": "0xd8a7e05a7ac670c0",
    "0xCapabilityFilter": "0xd8a7e05a7ac670c0",
    "0xFungibleToken": "0x9a0766d93b6608b7",
    "0xFlowToken": "0x7e60df042a9c0868",
  },
  mainnet: {
    "accessNode.api": "https://rest-mainnet.onflow.org",
    "discovery.wallet": "https://fcl-discovery.onflow.org/mainnet/authn",
    "flow.network": "mainnet",
    "app.detail.title": "FlowClaw",
    "app.detail.icon": "https://flowclaw.app/icon.png",
    "0xFlowClaw": "", // Set after mainnet deploy
    "0xHybridCustody": "0xd8a7e05a7ac670c0",
    "0xCapabilityFactory": "0xd8a7e05a7ac670c0",
    "0xCapabilityFilter": "0xd8a7e05a7ac670c0",
    "0xFungibleToken": "0xf233dcee88fe0abe",
    "0xFlowToken": "0x1654653399040a61",
  },
  emulator: {
    "accessNode.api": "http://localhost:8888",
    "discovery.wallet": "http://localhost:8701/fcl/authn",
    "flow.network": "local",
    "app.detail.title": "FlowClaw (Dev)",
    "0xFlowClaw": "0xf8d6e0586b0a20c7",
  },
};

fcl.config(configs[NETWORK] || configs.testnet);

export { fcl, NETWORK };

// Explorer URLs
export const getExplorerUrl = (type, id) => {
  const base = NETWORK === "mainnet"
    ? "https://flowscan.io"
    : "https://testnet.flowscan.io";

  if (type === "tx" || type === "transaction") return `${base}/tx/${id}`;
  if (type === "account") return `${base}/account/${id}`;
  if (type === "contract") return `${base}/contract/${id}`;
  return `${base}/${id}`;
};
