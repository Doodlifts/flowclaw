// FlowClaw API Client
// Connects to the relay API server

import { signFlowPayload, hasSigningKey } from './transactionSigner';
import { fcl } from './flow-config';
import * as fclTypes from '@onflow/types';

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
    const onChainToken = localStorage.getItem('flowclaw_session_token');
    if (address && onChainToken && hasSigningKey(address)) {
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

  // Internal: ensure an on-chain session exists for the given off-chain session.
  // Creates it lazily on first message rather than during mount (avoids auth race).
  async _ensureOnChainSession(sessionId) {
    if (onChainSessionMap[sessionId] !== undefined) return onChainSessionMap[sessionId];

    try {
      const txResult = await this.signAndSubmitTransaction(
        'cadence/transactions/create_session.cdc',
        [{ type: 'UInt64', value: '4096' }]
      );

      // Extract on-chain session ID from SessionCreated event
      if (txResult.events && Array.isArray(txResult.events)) {
        const sessionEvent = txResult.events.find(e =>
          e.type && e.type.includes('SessionCreated')
        );
        if (sessionEvent) {
          let onChainId = null;
          const fields = sessionEvent.payload?.value?.fields;
          if (Array.isArray(fields)) {
            const sidField = fields.find(f => f.name === 'sessionId');
            if (sidField) onChainId = parseInt(sidField.value?.value, 10);
          }
          if (onChainId == null && sessionEvent.payload?.sessionId != null) {
            onChainId = parseInt(sessionEvent.payload.sessionId, 10);
          }
          if (onChainId != null && !isNaN(onChainId)) {
            onChainSessionMap[sessionId] = onChainId;
            console.log(`Session mapped: off-chain ${sessionId} → on-chain ${onChainId}`);
            return onChainId;
          }
        }
      }
    } catch (err) {
      console.error('On-chain session creation failed:', err.message);
    }
    return null;
  },

  // Internal: store a message on-chain (non-blocking)
  // Content is ALWAYS encrypted via the relay before being sent to the chain.
  // Block explorers only see ciphertext — never plaintext.
  async _storeMessageOnChain(sessionId, content) {
    // Ensure on-chain session exists (lazy creation on first message)
    const onChainId = await this._ensureOnChainSession(sessionId);
    if (onChainId == null) {
      console.warn('Could not create on-chain session for off-chain session', sessionId, '— skipping on-chain storage');
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

    // On-chain session creation is now LAZY — it happens on the first message
    // in _storeMessageOnChain via _ensureOnChainSession. This avoids the auth
    // race condition where createSession fires before the token is established.
    sessionData.onChain = false;

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
    const headers = getAuthHeaders();

    const res = await fetch(`${API_BASE}/memory/store`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ key, content, tags, source }),
    });
    const data = await handleResponse(res);

    // If relay returned a pending multi-party build, sign and submit it
    if (data.pendingSign && data.txBuildId && data.payloadHex) {
      const address = localStorage.getItem('flowclaw_address');

      if (address && hasSigningKey(address)) {
        // Passkey: sign the relay-built payload locally
        try {
          const userSignature = await signFlowPayload(data.payloadHex, address);
          const submitRes = await fetch(`${API_BASE}/transaction/submit`, {
            method: 'POST',
            headers,
            body: JSON.stringify({
              txBuildId: data.txBuildId,
              userSignature,
            }),
          });
          const submitData = await handleResponse(submitRes);
          return { ...data, txResult: submitData, onChain: true };
        } catch (signErr) {
          console.warn('Memory multi-party signing failed, stored locally:', signErr);
        }
      }
    }

    return data;
  },

  // Poll and sign pending background transactions (auto-memory, sub-agents)
  async signPendingTransactions() {
    const address = localStorage.getItem('flowclaw_address');
    if (!address || !hasSigningKey(address)) return [];

    const headers = getAuthHeaders();
    if (!headers['Authorization']) return [];

    try {
      const res = await fetch(`${API_BASE}/transaction/pending`, { headers });
      const data = await handleResponse(res);
      const results = [];

      for (const pending of (data.pending || [])) {
        try {
          const userSignature = await signFlowPayload(pending.payloadHex, address);
          const submitRes = await fetch(`${API_BASE}/transaction/submit`, {
            method: 'POST',
            headers,
            body: JSON.stringify({
              txBuildId: pending.txBuildId,
              userSignature,
            }),
          });
          const submitData = await handleResponse(submitRes);
          results.push({ ...pending, result: submitData, success: true });
        } catch (err) {
          console.warn(`Failed to sign pending tx ${pending.txBuildId}:`, err);
          results.push({ ...pending, error: err.message, success: false });
        }
      }

      return results;
    } catch (err) {
      console.warn('Failed to fetch pending transactions:', err);
      return [];
    }
  },

  // Tasks
  async scheduleTask(task) {
    // Try multi-party signing first (user = authorizer, sponsor = payer)
    const address = localStorage.getItem('flowclaw_address');
    const token = localStorage.getItem('flowclaw_session_token');
    if (address && token && hasSigningKey(address)) {
      try {
        // Build Cadence-typed arguments for schedule_task.cdc
        const executeAtStr = (task.executeAt || Math.floor(Date.now() / 1000) + 60).toFixed(8);
        const args = [
          { type: 'String', value: task.name },
          { type: 'String', value: task.description || '' },
          { type: 'UInt8', value: String(task.category || 0) },
          { type: 'String', value: task.prompt },
          { type: 'UInt64', value: String(task.maxTurns || 10) },
          { type: 'UInt8', value: String(task.priority || 0) },
          { type: 'UFix64', value: executeAtStr },
          { type: 'Bool', value: task.isRecurring || false },
          task.intervalSeconds
            ? { type: 'Optional', value: { type: 'UFix64', value: task.intervalSeconds.toFixed(8) } }
            : { type: 'Optional', value: null },
          task.maxExecutions
            ? { type: 'Optional', value: { type: 'UInt64', value: String(task.maxExecutions) } }
            : { type: 'Optional', value: null },
        ];

        const txResult = await this.signAndSubmitTransaction(
          'cadence/transactions/schedule_task.cdc',
          args
        );

        // Extract task ID from event if available
        let taskId = null;
        if (txResult.events && Array.isArray(txResult.events)) {
          const taskEvent = txResult.events.find(e =>
            e.type && e.type.includes('TaskScheduled')
          );
          if (taskEvent?.payload?.value?.fields) {
            const idField = taskEvent.payload.value.fields.find(f => f.name === 'taskId');
            if (idField) taskId = parseInt(idField.value?.value, 10);
          }
        }

        // Also notify relay cache so the scheduler page shows the task
        try {
          await fetch(`${API_BASE}/tasks/schedule`, {
            method: 'POST',
            headers: getAuthHeaders(),
            body: JSON.stringify(task),
          });
        } catch (_) {
          // Cache sync is best-effort; the task is already on-chain
        }

        return { taskId: taskId ?? 0, success: true, onChain: true, txId: txResult.txId };
      } catch (err) {
        console.warn('Multi-party schedule_task failed, falling back to relay:', err.message);
      }
    }

    // Fallback: relay-only submission (sponsor acts as all roles)
    const res = await fetch(`${API_BASE}/tasks/schedule`, {
      method: 'POST',
      headers: getAuthHeaders(),
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
      headers: getAuthHeaders(),
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
   * Detects auth method and routes accordingly:
   *   - Passkey users: SubtleCrypto local signing (no popup)
   *   - Wallet users: FCL mutate with wallet popup for approval
   *
   * @param {string} txPath - Path to .cdc file (relative to project dir)
   * @param {Array} args - Cadence arguments [{"type": "...", "value": "..."}]
   * @returns {Object} Transaction result { txId, status, sealed, events }
   */
  async signAndSubmitTransaction(txPath, args = []) {
    const address = localStorage.getItem('flowclaw_address');
    if (!address) throw new Error('Not logged in');

    // Wallet signing disabled — will return with Hybrid Custody
    // For now, all users sign via passkey (SubtleCrypto)
    return this._signAndSubmitPasskey(txPath, args, address);
  },

  /**
   * Passkey signing: relay builds tx, browser signs with SubtleCrypto, relay submits.
   */
  async _signAndSubmitPasskey(txPath, args, address) {
    if (!hasSigningKey(address)) {
      throw new Error('No signing key found. Please create a new account.');
    }

    const headers = getAuthHeaders();
    if (!headers['Authorization']) {
      throw new Error('No session token available. Please sign in again.');
    }

    // Step 1: Ask relay to build the unsigned transaction
    const buildRes = await fetch(`${API_BASE}/transaction/build`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ transactionPath: txPath, arguments: args }),
    });
    const buildData = await handleResponse(buildRes);

    // Step 2: Sign the payload locally with SubtleCrypto
    const userSignature = await signFlowPayload(buildData.payloadHex, address);

    // Step 3: Submit the signed transaction back to relay
    const submitRes = await fetch(`${API_BASE}/transaction/submit`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        txBuildId: buildData.txBuildId,
        userSignature: userSignature,
      }),
    });
    return handleResponse(submitRes);
  },

  /**
   * Wallet signing: FCL mutate with wallet popup.
   * User signs as proposer+authorizer (wallet popup), relay signs as payer.
   */
  async _signAndSubmitWallet(txPath, args) {
    const headers = getAuthHeaders();
    if (!headers['Authorization']) {
      throw new Error('No session token available. Please sign in again.');
    }

    // Step 1: Fetch Cadence source (with resolved imports)
    const cadenceRes = await fetch(
      `${API_BASE}/transaction/cadence?path=${encodeURIComponent(txPath)}`,
      { headers }
    );
    const cadenceData = await handleResponse(cadenceRes);

    // Step 2: Fetch sponsor info for payer authorization
    const sponsorRes = await fetch(`${API_BASE}/sponsor-info`);
    const sponsor = await handleResponse(sponsorRes);

    // Step 3: Build the payer authorization function
    // The relay signs the envelope as payer when FCL calls this function
    const payerAuthz = async (account) => ({
      ...account,
      tempId: `${sponsor.address}-${sponsor.keyIndex}`,
      addr: fcl.sansPrefix(sponsor.address),
      keyId: sponsor.keyIndex,
      signingFunction: async (signable) => {
        const signRes = await fetch(`${API_BASE}/transaction/sign-envelope`, {
          method: 'POST',
          headers,
          body: JSON.stringify({ message: signable.message }),
        });
        const signData = await handleResponse(signRes);
        return {
          addr: fcl.sansPrefix(sponsor.address),
          keyId: sponsor.keyIndex,
          signature: signData.signature,
        };
      },
    });

    // Step 4: Convert args to FCL format and execute via fcl.mutate()
    const fclArgs = args.length > 0
      ? (arg, t) => args.map(a => convertToFclArg(a, arg, t))
      : undefined;

    const txId = await fcl.mutate({
      cadence: cadenceData.cadence,
      args: fclArgs,
      proposer: fcl.authz,          // Current wallet user proposes
      authorizations: [fcl.authz],   // Current wallet user authorizes
      payer: payerAuthz,             // Relay pays
      limit: 9999,
    });

    // Step 5: Wait for transaction to seal
    const txResult = await fcl.tx(txId).onceSealed();

    return {
      txId,
      status: txResult.statusString || 'SEALED',
      sealed: txResult.status === 4,
      events: (txResult.events || []).map(e => ({
        type: e.type,
        data: e.data,
      })),
    };
  },
};


/**
 * Convert a Cadence-typed argument to FCL arg format.
 * Input:  { type: "String", value: "hello" }
 * Output: arg("hello", t.String)
 */
function convertToFclArg(cadenceArg, arg, t) {
  const { type, value } = cadenceArg;

  switch (type) {
    case 'String':
      return arg(value, t.String);
    case 'UInt8':
      return arg(String(value), t.UInt8);
    case 'UInt16':
      return arg(String(value), t.UInt16);
    case 'UInt32':
      return arg(String(value), t.UInt32);
    case 'UInt64':
      return arg(String(value), t.UInt64);
    case 'Int':
      return arg(String(value), t.Int);
    case 'Int8':
      return arg(String(value), t.Int8);
    case 'Int32':
      return arg(String(value), t.Int32);
    case 'UFix64':
      return arg(String(value), t.UFix64);
    case 'Fix64':
      return arg(String(value), t.Fix64);
    case 'Bool':
      return arg(value, t.Bool);
    case 'Address':
      return arg(value, t.Address);
    case 'Array':
      // Arrays of typed values: [{ type: "String", value: "..." }, ...]
      if (Array.isArray(value) && value.length > 0 && value[0]?.type) {
        const innerType = fclTypes[value[0].type] || t.String;
        return arg(
          value.map(v => v.value),
          fclTypes.Array(innerType)
        );
      }
      return arg(value || [], fclTypes.Array(fclTypes.String));
    case 'Optional':
      if (value === null || value === undefined) {
        return arg(null, fclTypes.Optional(fclTypes.String));
      }
      if (value?.type) {
        const innerType = fclTypes[value.type] || fclTypes.String;
        return arg(value.value, fclTypes.Optional(innerType));
      }
      return arg(value, fclTypes.Optional(fclTypes.String));
    default:
      // Fallback: try as string
      return arg(String(value), t.String);
  }
}
