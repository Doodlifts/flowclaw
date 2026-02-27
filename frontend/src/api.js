// FlowClaw API Client
// Connects to the relay API server

import { signFlowPayload, hasSigningKey } from './transactionSigner';

const API_BASE = window.location.hostname === 'localhost'
  ? 'http://localhost:8000'
  : 'https://web-production-9784a.up.railway.app';

function getAuthHeaders() {
  const token = localStorage.getItem('flowclaw_session_token');
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  return headers;
}

async function handleResponse(res) {
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `HTTP ${res.status}`);
  }
  return res.json();
}

export const api = {
  // Relay status
  async getStatus() {
    const res = await fetch(`${API_BASE}/status`);
    return handleResponse(res);
  },

  // Chat
  async sendMessage(sessionId, content, provider = '', model = '') {
    const res = await fetch(`${API_BASE}/chat/send`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ sessionId, content, provider, model }),
    });
    return handleResponse(res);
  },

  async createSession(maxContextMessages = 4096) {
    // Use multi-party signing if user has a signing key (on-chain session)
    const address = localStorage.getItem('flowclaw_address');
    if (address && hasSigningKey(address)) {
      try {
        const txResult = await this.signAndSubmitTransaction(
          'cadence/transactions/create_session.cdc',
          [{ type: 'UInt64', value: String(maxContextMessages) }]
        );
        // Also create the off-chain session for immediate use
        const res = await fetch(`${API_BASE}/chat/create-session`, {
          method: 'POST',
          headers: getAuthHeaders(),
          body: JSON.stringify({ maxContextMessages }),
        });
        const sessionData = await handleResponse(res);
        sessionData.txResult = txResult;
        return sessionData;
      } catch (err) {
        console.warn('On-chain session creation failed, falling back to off-chain:', err.message);
      }
    }

    // Fallback: off-chain only
    const res = await fetch(`${API_BASE}/chat/create-session`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ maxContextMessages }),
    });
    return handleResponse(res);
  },

  // Sessions
  async getSessions() {
    const res = await fetch(`${API_BASE}/sessions`);
    return handleResponse(res);
  },

  async getSessionMessages(sessionId) {
    const res = await fetch(`${API_BASE}/session/${sessionId}/messages`);
    return handleResponse(res);
  },

  // On-chain state
  async getGlobalStats() {
    const res = await fetch(`${API_BASE}/global-stats`);
    return handleResponse(res);
  },

  async getMemory() {
    const res = await fetch(`${API_BASE}/memory`);
    return handleResponse(res);
  },

  async getTasks() {
    const res = await fetch(`${API_BASE}/tasks`);
    return handleResponse(res);
  },

  async getHooks() {
    const res = await fetch(`${API_BASE}/hooks`);
    return handleResponse(res);
  },

  // Memory
  async storeMemory(key, content, tags = [], source = 'frontend') {
    const res = await fetch(`${API_BASE}/memory/store`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key, content, tags, source }),
    });
    return handleResponse(res);
  },

  // Tasks
  async scheduleTask(task) {
    const res = await fetch(`${API_BASE}/tasks/schedule`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(task),
    });
    return handleResponse(res);
  },

  async cancelTask(taskId) {
    const res = await fetch(`${API_BASE}/tasks/${taskId}/cancel`, {
      method: 'POST',
    });
    return handleResponse(res);
  },

  // Extensions
  async getExtensions() {
    const res = await fetch(`${API_BASE}/extensions`);
    return handleResponse(res);
  },

  async publishExtension(ext) {
    const res = await fetch(`${API_BASE}/extensions/publish`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(ext),
    });
    return handleResponse(res);
  },

  async installExtension(extensionId, config = {}) {
    const res = await fetch(`${API_BASE}/extensions/${extensionId}/install`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ config }),
    });
    return handleResponse(res);
  },

  async uninstallExtension(extensionId) {
    const res = await fetch(`${API_BASE}/extensions/${extensionId}/uninstall`, {
      method: 'POST',
    });
    return handleResponse(res);
  },

  // Multi-Agent
  async getAgents() {
    const res = await fetch(`${API_BASE}/agents`);
    return handleResponse(res);
  },

  async createAgent(agent) {
    // Use multi-party signing for on-chain agent creation if signing key exists
    const address = localStorage.getItem('flowclaw_address');
    if (address && hasSigningKey(address)) {
      try {
        await this.signAndSubmitTransaction(
          'cadence/transactions/create_agent_in_collection.cdc',
          [
            { type: 'String', value: agent.name || '' },
            { type: 'String', value: agent.description || '' },
            { type: 'String', value: agent.provider || '' },
            { type: 'String', value: agent.model || '' },
            { type: 'String', value: '' },  // apiKeyHash
            { type: 'UInt64', value: '4096' },  // maxTokens
            { type: 'UFix64', value: '0.70000000' },  // temperature
            { type: 'String', value: agent.systemPrompt || `You are ${agent.name}, an AI agent on Flow blockchain.` },
            { type: 'UInt8', value: String(agent.autonomyLevel || 1) },
            { type: 'UInt64', value: String(agent.maxActionsPerHour || 100) },
            { type: 'UFix64', value: (agent.maxCostPerDay || 5.0).toFixed(8) },
          ]
        );
      } catch (err) {
        console.warn('On-chain agent creation failed, proceeding with off-chain:', err.message);
      }
    }

    // Always create in relay cache too (handles local state)
    const res = await fetch(`${API_BASE}/agents/create`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify(agent),
    });
    return handleResponse(res);
  },

  async spawnSubAgent(parentAgentId, subAgent) {
    const res = await fetch(`${API_BASE}/agents/${parentAgentId}/spawn`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(subAgent),
    });
    return handleResponse(res);
  },

  async selectAgent(agentId) {
    const res = await fetch(`${API_BASE}/agents/${agentId}/select`, {
      method: 'POST',
    });
    return handleResponse(res);
  },

  async deleteAgent(agentId) {
    const res = await fetch(`${API_BASE}/agents/${agentId}`, {
      method: 'DELETE',
    });
    return handleResponse(res);
  },

  // Cognitive Memory
  async getCognitiveState() {
    const res = await fetch(`${API_BASE}/cognitive/state`);
    return handleResponse(res);
  },

  async getCognitiveStats() {
    const res = await fetch(`${API_BASE}/cognitive/stats`);
    return handleResponse(res);
  },

  async cognitiveRetrieve(query, maxResults = 10) {
    const res = await fetch(`${API_BASE}/cognitive/retrieve?query=${encodeURIComponent(query)}&max_results=${maxResults}`);
    return handleResponse(res);
  },

  async triggerDreamCycle() {
    const res = await fetch(`${API_BASE}/cognitive/dream`, { method: 'POST' });
    return handleResponse(res);
  },

  // Task results
  async getTaskResults(taskId) {
    const res = await fetch(`${API_BASE}/tasks/${taskId}/results`);
    return handleResponse(res);
  },

  // Automated session (task execution outputs)
  async getAutomatedMessages() {
    const res = await fetch(`${API_BASE}/session/-1/messages`);
    return handleResponse(res);
  },

  // ----- LLM Provider Management (BYOK) -----

  async getProviders() {
    const res = await fetch(`${API_BASE}/account/providers`, {
      headers: getAuthHeaders(),
    });
    return handleResponse(res);
  },

  async saveProvider({ name, type, api_key, base_url, is_default }) {
    const res = await fetch(`${API_BASE}/account/providers`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ name, type, api_key, base_url, is_default }),
    });
    return handleResponse(res);
  },

  async deleteProvider(providerName) {
    const res = await fetch(`${API_BASE}/account/providers/${encodeURIComponent(providerName)}`, {
      method: 'DELETE',
      headers: getAuthHeaders(),
    });
    return handleResponse(res);
  },

  async setDefaultProvider(providerName, model = '') {
    const res = await fetch(`${API_BASE}/account/default-provider`, {
      method: 'PUT',
      headers: getAuthHeaders(),
      body: JSON.stringify({ provider_name: providerName, model }),
    });
    return handleResponse(res);
  },

  async getProviderPresets() {
    const res = await fetch(`${API_BASE}/account/provider-presets`);
    return handleResponse(res);
  },

  // ----- Multi-Party Transaction Signing -----

  /**
   * Build, sign, and submit a transaction using multi-party signing.
   * User signs as proposer/authorizer, sponsor signs as payer.
   *
   * @param {string} txPath - Path to .cdc file (relative to project dir)
   * @param {Array} args - Cadence arguments [{"type": "...", "value": "..."}]
   * @returns {Object} Transaction result { txId, status, sealed, events }
   */
  async signAndSubmitTransaction(txPath, args = []) {
    const address = localStorage.getItem('flowclaw_address');
    if (!address) throw new Error('Not logged in');
    if (!hasSigningKey(address)) {
      throw new Error('No signing key found. Please create a new account.');
    }

    // Step 1: Ask relay to build the unsigned transaction
    const buildRes = await fetch(`${API_BASE}/transaction/build`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ transactionPath: txPath, arguments: args }),
    });
    const buildData = await handleResponse(buildRes);

    // Step 2: Sign the payload locally with SubtleCrypto
    const userSignature = await signFlowPayload(buildData.payloadHex, address);

    // Step 3: Submit the signed transaction back to relay
    const submitRes = await fetch(`${API_BASE}/transaction/submit`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({
        txBuildId: buildData.txBuildId,
        userSignature: userSignature,
      }),
    });
    return handleResponse(submitRes);
  },
};
