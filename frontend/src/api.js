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

// Maps off-chain relay session IDs → on-chain session IDs.
// On-chain IDs come from the SessionCreated event after create_session.cdc runs.
const onChainSessionMap = {};

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
    const result = await handleResponse(res);

    // Store message on-chain via multi-party signing (best-effort, non-blocking)
    const address = localStorage.getItem('flowclaw_address');
    if (address && hasSigningKey(address)) {
      // Fire and forget — don't block the chat UX
      this._storeMessageOnChain(sessionId, content).catch(err => {
        console.error('On-chain message storage failed:', err.message);
      });
    }

    return result;
  },

  // Encrypt content via the relay's encryption key
  async encryptContent(content) {
    const res = await fetch(`${API_BASE}/encrypt`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ content }),
    });
    return handleResponse(res);
  },

  // Internal: store a message on-chain (non-blocking)
  // Content is ALWAYS encrypted via the relay before being sent to the chain.
  // Block explorers only see ciphertext — never plaintext.
  async _storeMessageOnChain(sessionId, content) {
    // Resolve the on-chain session ID (off-chain and on-chain IDs differ)
    const onChainId = onChainSessionMap[sessionId];
    if (onChainId === undefined) {
      console.warn('No on-chain session ID mapped for off-chain session', sessionId, '— skipping on-chain storage');
      return;
    }

    // Step 1: Encrypt content via relay (relay holds the encryption key)
    const enc = await this.encryptContent(content);

    // Step 2: Submit encrypted payload on-chain via multi-party signing
    await this.signAndSubmitTransaction(
      'cadence/transactions/send_message.cdc',
      [
        { type: 'UInt64', value: String(onChainId) },
        { type: 'String', value: enc.ciphertext },             // encrypted content
        { type: 'String', value: enc.nonce },                   // encryption nonce
        { type: 'String', value: enc.plaintextHash },           // SHA-256 of plaintext
        { type: 'String', value: enc.keyFingerprint || '' },    // key fingerprint
        { type: 'UInt8', value: String(enc.algorithm || 0) },   // algorithm ID
        { type: 'UInt64', value: String(enc.plaintextLength) }, // original length
      ]
    );
  },

  async createSession(maxContextMessages = 4096) {
    // Always create the off-chain session for immediate use
    const res = await fetch(`${API_BASE}/chat/create-session`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({ maxContextMessages }),
    });
    const sessionData = await handleResponse(res);

    // Also create on-chain session via multi-party signing (if signing key exists)
    const address = localStorage.getItem('flowclaw_address');
    if (address && hasSigningKey(address)) {
      try {
        const txResult = await this.signAndSubmitTransaction(
          'cadence/transactions/create_session.cdc',
          [{ type: 'UInt64', value: String(maxContextMessages) }]
        );
        sessionData.txResult = txResult;
        sessionData.onChain = true;

        // Extract on-chain session ID from SessionCreated event.
        // Flow event format: { type: "A.<addr>.AgentSession.SessionCreated",
        //   payload: { value: { fields: [{ name: "sessionId", value: { value: "1" } }, ...] } } }
        if (txResult.events && Array.isArray(txResult.events)) {
          const sessionEvent = txResult.events.find(e =>
            e.type && e.type.includes('SessionCreated')
          );
          if (sessionEvent) {
            let onChainId = null;
            // Try payload.value.fields (JSON-CDC decoded format)
            const fields = sessionEvent.payload?.value?.fields;
            if (Array.isArray(fields)) {
              const sidField = fields.find(f => f.name === 'sessionId');
              if (sidField) onChainId = parseInt(sidField.value?.value, 10);
            }
            // Fallback: direct value (if relay pre-decoded)
            if (onChainId == null && sessionEvent.payload?.sessionId != null) {
              onChainId = parseInt(sessionEvent.payload.sessionId, 10);
            }
            if (onChainId != null && !isNaN(onChainId)) {
              onChainSessionMap[sessionData.sessionId] = onChainId;
              sessionData.onChainSessionId = onChainId;
              console.log(`Session mapped: off-chain ${sessionData.sessionId} → on-chain ${onChainId}`);
            }
          }
        }
      } catch (err) {
        // Surface the error — don't silently pretend we're on-chain
        console.error('On-chain session creation failed:', err.message);
        sessionData.onChainError = err.message;
        sessionData.onChain = false;
      }
    } else {
      sessionData.onChain = false;
    }

    return sessionData;
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
    // Create in relay cache (handles local state + LLM routing)
    const res = await fetch(`${API_BASE}/agents/create`, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify(agent),
    });
    const result = await handleResponse(res);

    // Also create on-chain via multi-party signing
    const address = localStorage.getItem('flowclaw_address');
    if (address && hasSigningKey(address)) {
      try {
        const txResult = await this.signAndSubmitTransaction(
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
        result.txResult = txResult;
        result.onChain = true;
      } catch (err) {
        console.error('On-chain agent creation failed:', err.message);
        result.onChainError = err.message;
        result.onChain = false;
      }
    } else {
      result.onChain = false;
    }

    return result;
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

  async getProviderModels(providerName) {
    const res = await fetch(`${API_BASE}/account/providers/${encodeURIComponent(providerName)}/models`, {
      headers: getAuthHeaders(),
    });
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
