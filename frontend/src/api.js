// FlowClaw API Client
// Connects to the relay API server

const API_BASE = window.location.hostname === 'localhost'
  ? 'http://localhost:8000'
  : 'https://web-production-9784a.up.railway.app';

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
  async sendMessage(sessionId, content, provider = 'venice', model = 'claude-sonnet-4-6') {
    const res = await fetch(`${API_BASE}/chat/send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId, content, provider, model }),
    });
    return handleResponse(res);
  },

  async createSession(maxContextMessages = 4096) {
    const res = await fetch(`${API_BASE}/chat/create-session`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
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
    const res = await fetch(`${API_BASE}/agents/create`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
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
};
