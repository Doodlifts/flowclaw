import { useState, useEffect, useRef } from "react";
import {
  Shield, Cpu, MessageSquare, LayoutDashboard, Puzzle, Clock, Brain,
  Send, Plus, Trash2, Play, Pause, Settings, ChevronRight, Search,
  Zap, Lock, Unlock, AlertTriangle, CheckCircle, XCircle, RefreshCw,
  Activity, Database, Globe, Terminal, ArrowUpRight, Download, Upload,
  Hash, Tag, Calendar, BarChart3, Layers, Box, Eye, EyeOff, Power,
  Wallet, LogOut, Copy, ExternalLink, Star, TrendingUp, ChevronDown
} from "lucide-react";

// ============================================================
// MOCK DATA — mirrors the actual Cadence contract structures
// ============================================================
const MOCK_AGENT = {
  id: 1, name: "FlowClaw Agent", description: "Personal AI assistant on Flow",
  owner: "0x1a2b3c4d5e6f7890", isActive: true, totalSessions: 12,
  totalInferences: 847, createdAt: "2026-02-10T08:00:00Z",
  config: { provider: "anthropic", model: "claude-sonnet-4-5-20250929", maxTokens: 4096, temperature: 0.7 },
  security: { autonomyLevel: 1, maxActionsPerHour: 100, maxCostPerDay: 10.0, allowedTools: ["memory_store","memory_recall","web_fetch","flow_query"], deniedTools: ["shell_exec"] }
};

const MOCK_MESSAGES = [
  { id: 1, role: "system", content: "You are a FlowClaw agent running on the Flow blockchain.", timestamp: "2026-02-17T09:00:00Z" },
  { id: 2, role: "user", content: "What's the current FLOW token price?", timestamp: "2026-02-17T09:01:00Z" },
  { id: 3, role: "assistant", content: "I'll check the current FLOW price for you. Based on my latest data, FLOW is trading at approximately $0.83 USD, up 2.4% in the last 24 hours. The 24h volume is around $45M across major exchanges.\n\nWould you like me to set up a recurring price alert?", timestamp: "2026-02-17T09:01:05Z", tokensUsed: 156 },
  { id: 4, role: "user", content: "Yes, alert me if it goes above $1.00", timestamp: "2026-02-17T09:02:00Z" },
  { id: 5, role: "assistant", content: "Done! I've created a scheduled task that checks the FLOW price every 15 minutes. You'll get a notification when it crosses $1.00.\n\n**Task details:**\n- Check interval: 15 minutes\n- Condition: FLOW > $1.00 USD\n- Task ID: #7 (on-chain, validator-executed)\n\nThis runs via Flow's scheduled transactions, so it'll fire even if your computer is off.", timestamp: "2026-02-17T09:02:08Z", tokensUsed: 203 }
];

const MOCK_SESSIONS = [
  { id: 1, agentId: 1, isOpen: true, messageCount: 47, totalTokens: 12840, createdAt: "2026-02-17T09:00:00Z", label: "DeFi Research" },
  { id: 2, agentId: 1, isOpen: true, messageCount: 12, totalTokens: 3200, createdAt: "2026-02-16T14:30:00Z", label: "Code Review" },
  { id: 3, agentId: 1, isOpen: false, messageCount: 89, totalTokens: 24100, createdAt: "2026-02-15T08:00:00Z", label: "Weekly Planning" },
];

const MOCK_EXTENSIONS = [
  { id: 1, name: "sentiment-guard", description: "Analyzes agent responses for sentiment before sending. Blocks negative or harmful messages.", version: "1.0.0", author: "0xaaa111bbb222", category: "hook", tags: ["safety","moderation","guardrail"], installCount: 342, isAudited: true, installed: true, enabled: true },
  { id: 2, name: "flow-defi-tools", description: "DeFi tools for Flow: token swaps, balance checks, pool stats, and price alerts.", version: "1.0.0", author: "0xccc333ddd444", category: "tool", tags: ["defi","trading","swap","tokens"], installCount: 1205, isAudited: true, installed: true, enabled: true },
  { id: 3, name: "conversation-summarizer", description: "Auto-summarizes long conversations and stores them in memory for context continuity.", version: "1.0.0", author: "0xeee555fff666", category: "composite", tags: ["memory","summarization","productivity"], installCount: 891, isAudited: true, installed: false, enabled: false },
  { id: 4, name: "telegram-channel", description: "Telegram bot channel adapter for FlowClaw agents.", version: "0.9.0", author: "0x777888999aaa", category: "channel", tags: ["telegram","messaging","channel"], installCount: 567, isAudited: false, installed: false, enabled: false },
  { id: 5, name: "nft-tools", description: "Mint, transfer, and query NFTs on Flow directly from your agent.", version: "1.2.0", author: "0xbbb111ccc222", category: "tool", tags: ["nft","flow","collectibles"], installCount: 423, isAudited: true, installed: false, enabled: false },
  { id: 6, name: "code-sandbox", description: "Sandboxed code execution environment for your agent. Supports Python, JS, and Cadence.", version: "0.8.0", author: "0xddd333eee444", category: "tool", tags: ["code","sandbox","execution"], installCount: 298, isAudited: false, installed: false, enabled: false },
];

const MOCK_TASKS = [
  { id: 1, name: "FLOW Price Alert", category: "monitoring", prompt: "Check FLOW price and alert if above $1.00", interval: "15m", nextExecution: "2026-02-17T09:30:00Z", executionCount: 48, status: "active", priority: "high" },
  { id: 2, name: "Daily Inbox Summary", category: "inference", prompt: "Summarize key messages and events from the past 24 hours", interval: "24h", nextExecution: "2026-02-18T09:00:00Z", executionCount: 7, status: "active", priority: "medium" },
  { id: 3, name: "Portfolio Rebalance Check", category: "monitoring", prompt: "Analyze portfolio allocation and suggest rebalancing if drift > 5%", interval: "6h", nextExecution: "2026-02-17T12:00:00Z", executionCount: 28, status: "active", priority: "high" },
  { id: 4, name: "Weekly Session Cleanup", category: "memoryMaintenance", prompt: "Compact old sessions and summarize for long-term memory", interval: "7d", nextExecution: "2026-02-24T00:00:00Z", executionCount: 2, status: "active", priority: "low" },
  { id: 5, name: "Remind: Team Meeting", category: "communication", prompt: "Remind me about the team sync meeting in 10 minutes", interval: null, nextExecution: "2026-02-17T10:50:00Z", executionCount: 0, status: "pending", priority: "high" },
];

const MOCK_MEMORIES = [
  { id: 1, key: "user-preferences", content: "User prefers concise responses. Interested in DeFi and NFTs on Flow. Timezone: EST.", tags: ["preferences","profile"], source: "manual", accessCount: 34, updatedAt: "2026-02-17T08:00:00Z" },
  { id: 2, key: "flow-ecosystem-notes", content: "Key Flow projects: IncrementFi (DEX), Flowty (NFT lending), .find (naming service). Flow uses Cadence language with resource-oriented programming.", tags: ["flow","ecosystem","research"], source: "session-3", accessCount: 12, updatedAt: "2026-02-16T15:30:00Z" },
  { id: 3, key: "meeting-notes-feb-14", content: "Team discussed Q1 roadmap. Key items: launch FlowClaw testnet by March, integration with Telegram by April, mainnet by June.", tags: ["meetings","planning","roadmap"], source: "session-2", accessCount: 5, updatedAt: "2026-02-14T16:00:00Z" },
  { id: 4, key: "portfolio-strategy", content: "Target allocation: 40% FLOW, 25% stablecoins, 20% Flow ecosystem tokens, 15% NFTs. Max single position: 10%. Rebalance threshold: 5% drift.", tags: ["defi","portfolio","strategy"], source: "session-1", accessCount: 28, updatedAt: "2026-02-15T10:00:00Z" },
  { id: 5, key: "conversation-summary-session-3", content: "Session 3 covered weekly planning. Discussed team capacity, sprint goals, and blockers. Key decision: prioritize testnet deployment over new features.", tags: ["conversation-summary","planning"], source: "extension:conversation-summarizer", accessCount: 8, updatedAt: "2026-02-15T17:00:00Z" },
];

const MOCK_ACTIVITY = [
  { type: "inference", message: "Completed inference request #847", time: "2 min ago", icon: "zap" },
  { type: "task", message: "Scheduled task 'FLOW Price Alert' executed", time: "13 min ago", icon: "clock" },
  { type: "memory", message: "Memory updated: portfolio-strategy", time: "1 hr ago", icon: "brain" },
  { type: "extension", message: "Extension 'flow-defi-tools' executed swap_tokens", time: "2 hr ago", icon: "puzzle" },
  { type: "session", message: "Session #1 'DeFi Research' created", time: "3 hr ago", icon: "message" },
  { type: "hook", message: "Hook 'sentiment-guard' passed on message #845", time: "3 hr ago", icon: "shield" },
  { type: "task", message: "Scheduled task 'Daily Inbox Summary' completed", time: "6 hr ago", icon: "clock" },
  { type: "inference", message: "Completed inference request #843 (5 turns)", time: "6 hr ago", icon: "zap" },
];

// ============================================================
// UTILITY COMPONENTS
// ============================================================
const Badge = ({ children, variant = "default" }) => {
  const styles = {
    default: "bg-zinc-800 text-zinc-300",
    success: "bg-emerald-900/60 text-emerald-300",
    warning: "bg-amber-900/60 text-amber-300",
    danger: "bg-red-900/60 text-red-300",
    info: "bg-blue-900/60 text-blue-300",
    purple: "bg-purple-900/60 text-purple-300",
    cyan: "bg-cyan-900/60 text-cyan-300",
  };
  return <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${styles[variant]}`}>{children}</span>;
};

const StatCard = ({ icon: Icon, label, value, sub, color = "text-emerald-400" }) => (
  <div className="bg-zinc-900 rounded-xl border border-zinc-800 p-4">
    <div className="flex items-center gap-2 mb-1">
      <Icon size={14} className="text-zinc-500" />
      <span className="text-xs text-zinc-500 uppercase tracking-wider">{label}</span>
    </div>
    <div className={`text-2xl font-bold ${color}`}>{value}</div>
    {sub && <div className="text-xs text-zinc-500 mt-1">{sub}</div>}
  </div>
);

const CategoryIcon = ({ category }) => {
  const icons = { tool: Zap, hook: Shield, composite: Layers, channel: Globe, behavior: Cpu, integration: ArrowUpRight, memory: Brain, scheduler: Clock };
  const Icon = icons[category] || Box;
  return <Icon size={14} />;
};

const PriorityDot = ({ priority }) => {
  const colors = { high: "bg-red-400", medium: "bg-amber-400", low: "bg-blue-400" };
  return <span className={`inline-block w-2 h-2 rounded-full ${colors[priority] || "bg-zinc-500"}`} />;
};

// ============================================================
// CHAT TAB
// ============================================================
const ChatTab = () => {
  const [messages, setMessages] = useState(MOCK_MESSAGES.filter(m => m.role !== "system"));
  const [input, setInput] = useState("");
  const [isTyping, setIsTyping] = useState(false);
  const [activeSession, setActiveSession] = useState(MOCK_SESSIONS[0]);
  const [showSessions, setShowSessions] = useState(false);
  const messagesEnd = useRef(null);

  useEffect(() => { messagesEnd.current?.scrollIntoView({ behavior: "smooth" }); }, [messages]);

  const sendMessage = () => {
    if (!input.trim()) return;
    const userMsg = { id: messages.length + 1, role: "user", content: input, timestamp: new Date().toISOString() };
    setMessages(prev => [...prev, userMsg]);
    setInput("");
    setIsTyping(true);
    setTimeout(() => {
      setMessages(prev => [...prev, {
        id: prev.length + 1, role: "assistant", timestamp: new Date().toISOString(), tokensUsed: 142,
        content: "I've processed your request through the on-chain agent loop. The inference was completed in 2.3 seconds with 142 tokens used. The result has been stored in session #1 on-chain.\n\nIs there anything else you'd like me to help with?"
      }]);
      setIsTyping(false);
    }, 2000);
  };

  return (
    <div className="flex h-full">
      {/* Session sidebar */}
      <div className={`${showSessions ? "w-64" : "w-0"} transition-all overflow-hidden border-r border-zinc-800 bg-zinc-950 flex flex-col`}>
        <div className="p-3 border-b border-zinc-800 flex items-center justify-between">
          <span className="text-sm font-medium text-zinc-300">Sessions</span>
          <button className="p-1 rounded hover:bg-zinc-800 text-zinc-400"><Plus size={14} /></button>
        </div>
        <div className="flex-1 overflow-y-auto">
          {MOCK_SESSIONS.map(s => (
            <button key={s.id} onClick={() => setActiveSession(s)}
              className={`w-full text-left p-3 border-b border-zinc-800/50 hover:bg-zinc-900 transition ${activeSession.id === s.id ? "bg-zinc-900 border-l-2 border-l-emerald-500" : ""}`}>
              <div className="flex items-center gap-2">
                <span className={`w-1.5 h-1.5 rounded-full ${s.isOpen ? "bg-emerald-400" : "bg-zinc-600"}`} />
                <span className="text-sm text-zinc-200 truncate">{s.label}</span>
              </div>
              <div className="text-xs text-zinc-600 mt-1 ml-3.5">{s.messageCount} messages</div>
            </button>
          ))}
        </div>
      </div>

      {/* Main chat area */}
      <div className="flex-1 flex flex-col">
        {/* Chat header */}
        <div className="h-12 border-b border-zinc-800 flex items-center px-4 gap-3 bg-zinc-950/50">
          <button onClick={() => setShowSessions(!showSessions)} className="p-1 rounded hover:bg-zinc-800 text-zinc-400">
            <MessageSquare size={16} />
          </button>
          <div className="flex-1">
            <span className="text-sm font-medium text-zinc-200">{activeSession.label}</span>
            <span className="text-xs text-zinc-600 ml-2">Session #{activeSession.id}</span>
          </div>
          <Badge variant="success">{activeSession.isOpen ? "Live" : "Closed"}</Badge>
          <span className="text-xs text-zinc-600">{activeSession.totalTokens.toLocaleString()} tokens</span>
        </div>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {messages.map(msg => (
            <div key={msg.id} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
              <div className={`max-w-2xl rounded-2xl px-4 py-3 ${
                msg.role === "user"
                  ? "bg-emerald-600/20 border border-emerald-800/40 text-zinc-100"
                  : "bg-zinc-900 border border-zinc-800 text-zinc-200"
              }`}>
                <div className="text-sm whitespace-pre-wrap leading-relaxed">{msg.content}</div>
                <div className="flex items-center gap-2 mt-2 text-xs text-zinc-600">
                  <span>{new Date(msg.timestamp).toLocaleTimeString()}</span>
                  {msg.tokensUsed && (
                    <>
                      <span className="text-zinc-700">|</span>
                      <span>{msg.tokensUsed} tokens</span>
                    </>
                  )}
                  {msg.role === "assistant" && (
                    <>
                      <span className="text-zinc-700">|</span>
                      <span className="text-emerald-600 flex items-center gap-0.5">
                        <Lock size={9} /> on-chain
                      </span>
                    </>
                  )}
                </div>
              </div>
            </div>
          ))}
          {isTyping && (
            <div className="flex justify-start">
              <div className="bg-zinc-900 border border-zinc-800 rounded-2xl px-4 py-3">
                <div className="flex gap-1">
                  <span className="w-2 h-2 bg-zinc-600 rounded-full animate-bounce" style={{animationDelay:"0ms"}} />
                  <span className="w-2 h-2 bg-zinc-600 rounded-full animate-bounce" style={{animationDelay:"150ms"}} />
                  <span className="w-2 h-2 bg-zinc-600 rounded-full animate-bounce" style={{animationDelay:"300ms"}} />
                </div>
              </div>
            </div>
          )}
          <div ref={messagesEnd} />
        </div>

        {/* Input */}
        <div className="p-4 border-t border-zinc-800 bg-zinc-950/50">
          <div className="flex items-center gap-2 bg-zinc-900 border border-zinc-800 rounded-xl px-4 py-2 focus-within:border-emerald-700 transition">
            <input
              type="text" value={input} onChange={e => setInput(e.target.value)}
              onKeyDown={e => e.key === "Enter" && sendMessage()}
              placeholder="Message your agent..."
              className="flex-1 bg-transparent text-sm text-zinc-100 placeholder-zinc-600 outline-none"
            />
            <button onClick={sendMessage}
              className={`p-2 rounded-lg transition ${input.trim() ? "bg-emerald-600 text-white hover:bg-emerald-500" : "bg-zinc-800 text-zinc-600"}`}>
              <Send size={14} />
            </button>
          </div>
          <div className="flex items-center gap-3 mt-2 px-1 text-xs text-zinc-600">
            <span className="flex items-center gap-1"><Lock size={9} /> Messages stored on-chain</span>
            <span className="flex items-center gap-1"><Hash size={9} /> Content hashed for verification</span>
            <span className="flex items-center gap-1"><Shield size={9} /> 2 hooks active</span>
          </div>
        </div>
      </div>
    </div>
  );
};

// ============================================================
// DASHBOARD TAB
// ============================================================
const DashboardTab = () => (
  <div className="p-6 space-y-6 overflow-y-auto h-full">
    {/* Agent header */}
    <div className="flex items-center justify-between">
      <div className="flex items-center gap-4">
        <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-emerald-600 to-cyan-600 flex items-center justify-center">
          <Cpu size={24} className="text-white" />
        </div>
        <div>
          <h2 className="text-xl font-bold text-zinc-100">{MOCK_AGENT.name}</h2>
          <div className="flex items-center gap-2 mt-0.5">
            <Badge variant="success">Active</Badge>
            <span className="text-xs text-zinc-500">{MOCK_AGENT.config.provider}/{MOCK_AGENT.config.model}</span>
          </div>
        </div>
      </div>
      <div className="flex items-center gap-2">
        <div className="text-right mr-3">
          <div className="text-xs text-zinc-500">Owner</div>
          <div className="text-sm text-zinc-300 font-mono">{MOCK_AGENT.owner.slice(0,8)}...{MOCK_AGENT.owner.slice(-4)}</div>
        </div>
        <button className="p-2 rounded-lg bg-zinc-900 border border-zinc-800 hover:bg-zinc-800 text-zinc-400 transition">
          <Settings size={16} />
        </button>
      </div>
    </div>

    {/* Stats grid */}
    <div className="grid grid-cols-5 gap-3">
      <StatCard icon={Zap} label="Inferences" value={MOCK_AGENT.totalInferences.toLocaleString()} sub="12 today" />
      <StatCard icon={MessageSquare} label="Sessions" value={MOCK_AGENT.totalSessions} sub="2 active" color="text-blue-400" />
      <StatCard icon={Clock} label="Scheduled" value={MOCK_TASKS.filter(t=>t.status==="active").length} sub="5 total" color="text-amber-400" />
      <StatCard icon={Brain} label="Memories" value={MOCK_MEMORIES.length} sub="87 accesses" color="text-purple-400" />
      <StatCard icon={Puzzle} label="Extensions" value={MOCK_EXTENSIONS.filter(e=>e.installed).length} sub={`of ${MOCK_EXTENSIONS.length} available`} color="text-cyan-400" />
    </div>

    {/* Security & Config row */}
    <div className="grid grid-cols-2 gap-4">
      <div className="bg-zinc-900 rounded-xl border border-zinc-800 p-4">
        <h3 className="text-sm font-medium text-zinc-300 mb-3 flex items-center gap-2"><Shield size={14} /> Security Policy</h3>
        <div className="space-y-2">
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Autonomy</span>
            <Badge variant="warning">Supervised</Badge>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Rate Limit</span>
            <span className="text-zinc-300">{MOCK_AGENT.security.maxActionsPerHour}/hr</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Cost Cap</span>
            <span className="text-zinc-300">{MOCK_AGENT.security.maxCostPerDay} FLOW/day</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Allowed Tools</span>
            <span className="text-zinc-300">{MOCK_AGENT.security.allowedTools.length} tools</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-zinc-500">Denied Tools</span>
            <span className="text-red-400">{MOCK_AGENT.security.deniedTools.join(", ")}</span>
          </div>
        </div>
      </div>

      <div className="bg-zinc-900 rounded-xl border border-zinc-800 p-4">
        <h3 className="text-sm font-medium text-zinc-300 mb-3 flex items-center gap-2"><Activity size={14} /> Recent Activity</h3>
        <div className="space-y-2 max-h-48 overflow-y-auto">
          {MOCK_ACTIVITY.slice(0, 6).map((a, i) => {
            const icons = { zap: Zap, clock: Clock, brain: Brain, puzzle: Puzzle, message: MessageSquare, shield: Shield };
            const Icon = icons[a.icon] || Activity;
            return (
              <div key={i} className="flex items-center gap-2 text-xs">
                <Icon size={12} className="text-zinc-600 shrink-0" />
                <span className="text-zinc-400 truncate flex-1">{a.message}</span>
                <span className="text-zinc-600 shrink-0">{a.time}</span>
              </div>
            );
          })}
        </div>
      </div>
    </div>

    {/* On-chain info */}
    <div className="bg-zinc-900/50 rounded-xl border border-zinc-800 p-4">
      <h3 className="text-sm font-medium text-zinc-300 mb-3 flex items-center gap-2"><Database size={14} /> On-Chain State</h3>
      <div className="grid grid-cols-4 gap-4 text-xs">
        <div>
          <div className="text-zinc-600 mb-1">Storage Path</div>
          <code className="text-emerald-400 bg-zinc-800 px-2 py-0.5 rounded text-xs">/storage/FlowClawStack</code>
        </div>
        <div>
          <div className="text-zinc-600 mb-1">Network</div>
          <span className="text-zinc-300">Flow Testnet</span>
        </div>
        <div>
          <div className="text-zinc-600 mb-1">Resources</div>
          <span className="text-zinc-300">9 active</span>
        </div>
        <div>
          <div className="text-zinc-600 mb-1">Relay Status</div>
          <Badge variant="success">Connected</Badge>
        </div>
      </div>
    </div>
  </div>
);

// ============================================================
// EXTENSIONS TAB
// ============================================================
const ExtensionsTab = () => {
  const [filter, setFilter] = useState("all");
  const [search, setSearch] = useState("");
  const [extensions, setExtensions] = useState(MOCK_EXTENSIONS);

  const toggleInstall = (id) => {
    setExtensions(prev => prev.map(e =>
      e.id === id ? { ...e, installed: !e.installed, enabled: !e.installed } : e
    ));
  };

  const filtered = extensions.filter(e => {
    if (filter === "installed" && !e.installed) return false;
    if (filter !== "all" && filter !== "installed" && e.category !== filter) return false;
    if (search && !e.name.includes(search) && !e.description.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  return (
    <div className="p-6 space-y-5 overflow-y-auto h-full">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-bold text-zinc-100">Extension Marketplace</h2>
          <p className="text-xs text-zinc-500 mt-0.5">Permissionless. No maintainer approval needed. You control what runs on your agent.</p>
        </div>
        <button className="flex items-center gap-2 px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-sm font-medium transition">
          <Upload size={14} /> Publish Extension
        </button>
      </div>

      <div className="flex items-center gap-3">
        <div className="flex-1 relative">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-zinc-600" />
          <input type="text" value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Search extensions..." className="w-full bg-zinc-900 border border-zinc-800 rounded-lg pl-9 pr-4 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none focus:border-zinc-700" />
        </div>
        <div className="flex gap-1 bg-zinc-900 border border-zinc-800 rounded-lg p-1">
          {["all","installed","tool","hook","composite","channel"].map(f => (
            <button key={f} onClick={() => setFilter(f)}
              className={`px-3 py-1 text-xs rounded-md transition ${filter === f ? "bg-zinc-700 text-zinc-100" : "text-zinc-500 hover:text-zinc-300"}`}>
              {f.charAt(0).toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        {filtered.map(ext => (
          <div key={ext.id} className={`bg-zinc-900 rounded-xl border p-4 transition ${ext.installed ? "border-emerald-800/50" : "border-zinc-800"}`}>
            <div className="flex items-start justify-between mb-2">
              <div className="flex items-center gap-2">
                <div className={`w-8 h-8 rounded-lg flex items-center justify-center ${ext.installed ? "bg-emerald-900/50 text-emerald-400" : "bg-zinc-800 text-zinc-500"}`}>
                  <CategoryIcon category={ext.category} />
                </div>
                <div>
                  <div className="text-sm font-medium text-zinc-200">{ext.name}</div>
                  <div className="text-xs text-zinc-600">v{ext.version} by {ext.author.slice(0,8)}...</div>
                </div>
              </div>
              {ext.isAudited && <Badge variant="success">Audited</Badge>}
            </div>
            <p className="text-xs text-zinc-400 mb-3 leading-relaxed">{ext.description}</p>
            <div className="flex items-center gap-2 mb-3 flex-wrap">
              {ext.tags.slice(0, 4).map(t => <Badge key={t}>{t}</Badge>)}
            </div>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3 text-xs text-zinc-600">
                <span className="flex items-center gap-1"><Download size={10} /> {ext.installCount}</span>
                <Badge variant={ext.category === "tool" ? "info" : ext.category === "hook" ? "purple" : "cyan"}>{ext.category}</Badge>
              </div>
              <button onClick={() => toggleInstall(ext.id)}
                className={`px-3 py-1.5 rounded-lg text-xs font-medium transition ${
                  ext.installed
                    ? "bg-zinc-800 text-zinc-400 hover:bg-red-900/30 hover:text-red-400"
                    : "bg-emerald-600/20 text-emerald-400 hover:bg-emerald-600/30 border border-emerald-800/50"
                }`}>
                {ext.installed ? "Uninstall" : "Install"}
              </button>
            </div>
            {ext.installed && (
              <div className="mt-3 pt-3 border-t border-zinc-800 flex items-center justify-between">
                <span className="text-xs text-zinc-500">Required entitlements:</span>
                <div className="flex gap-1">
                  <Badge variant="warning">Execute</Badge>
                  {ext.category === "hook" && <Badge variant="purple">RegisterHooks</Badge>}
                  {ext.category === "tool" && <Badge variant="info">ManageTools</Badge>}
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
};

// ============================================================
// SCHEDULER TAB
// ============================================================
const SchedulerTab = () => {
  const [showNew, setShowNew] = useState(false);

  return (
    <div className="p-6 space-y-5 overflow-y-auto h-full">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-bold text-zinc-100">Scheduled Tasks</h2>
          <p className="text-xs text-zinc-500 mt-0.5">Validator-executed. Runs even when your machine is off.</p>
        </div>
        <button onClick={() => setShowNew(!showNew)}
          className="flex items-center gap-2 px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-sm font-medium transition">
          <Plus size={14} /> New Task
        </button>
      </div>

      {/* Quick presets */}
      <div className="flex gap-2">
        {[
          { label: "Every hour", icon: RefreshCw },
          { label: "Daily at 9am", icon: Calendar },
          { label: "Weekly report", icon: BarChart3 },
          { label: "One-time reminder", icon: Clock },
        ].map(({ label, icon: Icon }) => (
          <button key={label} className="flex items-center gap-2 px-3 py-2 bg-zinc-900 border border-zinc-800 rounded-lg text-xs text-zinc-400 hover:border-zinc-700 hover:text-zinc-300 transition">
            <Icon size={12} /> {label}
          </button>
        ))}
      </div>

      {/* Tasks list */}
      <div className="space-y-3">
        {MOCK_TASKS.map(task => (
          <div key={task.id} className="bg-zinc-900 rounded-xl border border-zinc-800 p-4">
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-3">
                <PriorityDot priority={task.priority} />
                <span className="text-sm font-medium text-zinc-200">{task.name}</span>
                <Badge variant={task.status === "active" ? "success" : "warning"}>{task.status}</Badge>
                {task.interval && <Badge variant="info">{task.interval}</Badge>}
                {!task.interval && <Badge variant="purple">one-shot</Badge>}
              </div>
              <div className="flex items-center gap-1">
                <button className="p-1.5 rounded hover:bg-zinc-800 text-zinc-500 transition">
                  {task.status === "active" ? <Pause size={14} /> : <Play size={14} />}
                </button>
                <button className="p-1.5 rounded hover:bg-zinc-800 text-zinc-500 hover:text-red-400 transition">
                  <Trash2 size={14} />
                </button>
              </div>
            </div>
            <p className="text-xs text-zinc-500 mb-3 ml-5">{task.prompt}</p>
            <div className="flex items-center gap-4 ml-5 text-xs text-zinc-600">
              <span className="flex items-center gap-1">
                <Clock size={10} /> Next: {new Date(task.nextExecution).toLocaleString()}
              </span>
              <span className="flex items-center gap-1">
                <Activity size={10} /> {task.executionCount} executions
              </span>
              <span className="flex items-center gap-1">
                <Database size={10} /> On-chain #{task.id}
              </span>
            </div>
          </div>
        ))}
      </div>

      {/* How it works callout */}
      <div className="bg-emerald-950/30 border border-emerald-900/50 rounded-xl p-4">
        <h4 className="text-sm font-medium text-emerald-300 mb-2">How Scheduled Tasks Work</h4>
        <div className="grid grid-cols-4 gap-4 text-xs text-zinc-400">
          <div className="flex items-start gap-2">
            <div className="w-5 h-5 rounded-full bg-emerald-900/50 flex items-center justify-center shrink-0 mt-0.5">
              <span className="text-emerald-400 text-xs font-bold">1</span>
            </div>
            <span>You schedule a task on-chain via a Cadence transaction</span>
          </div>
          <div className="flex items-start gap-2">
            <div className="w-5 h-5 rounded-full bg-emerald-900/50 flex items-center justify-center shrink-0 mt-0.5">
              <span className="text-emerald-400 text-xs font-bold">2</span>
            </div>
            <span>Flow validators execute the handler at the scheduled time</span>
          </div>
          <div className="flex items-start gap-2">
            <div className="w-5 h-5 rounded-full bg-emerald-900/50 flex items-center justify-center shrink-0 mt-0.5">
              <span className="text-emerald-400 text-xs font-bold">3</span>
            </div>
            <span>Your local relay picks up the event and runs inference</span>
          </div>
          <div className="flex items-start gap-2">
            <div className="w-5 h-5 rounded-full bg-emerald-900/50 flex items-center justify-center shrink-0 mt-0.5">
              <span className="text-emerald-400 text-xs font-bold">4</span>
            </div>
            <span>Recurring tasks re-schedule themselves automatically</span>
          </div>
        </div>
      </div>
    </div>
  );
};

// ============================================================
// MEMORY TAB
// ============================================================
const MemoryTab = () => {
  const [search, setSearch] = useState("");
  const [selectedTag, setSelectedTag] = useState(null);
  const [expanded, setExpanded] = useState(null);

  const allTags = [...new Set(MOCK_MEMORIES.flatMap(m => m.tags))];
  const filtered = MOCK_MEMORIES.filter(m => {
    if (selectedTag && !m.tags.includes(selectedTag)) return false;
    if (search && !m.key.includes(search) && !m.content.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  return (
    <div className="p-6 space-y-5 overflow-y-auto h-full">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-bold text-zinc-100">Memory Explorer</h2>
          <p className="text-xs text-zinc-500 mt-0.5">On-chain key-value store. Private to your account. Tag-based search.</p>
        </div>
        <button className="flex items-center gap-2 px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-sm font-medium transition">
          <Plus size={14} /> Store Memory
        </button>
      </div>

      <div className="flex items-center gap-3">
        <div className="flex-1 relative">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-zinc-600" />
          <input type="text" value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Search memories..." className="w-full bg-zinc-900 border border-zinc-800 rounded-lg pl-9 pr-4 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none focus:border-zinc-700" />
        </div>
      </div>

      {/* Tags filter */}
      <div className="flex items-center gap-2 flex-wrap">
        <span className="text-xs text-zinc-600">Filter by tag:</span>
        <button onClick={() => setSelectedTag(null)}
          className={`px-2 py-1 rounded text-xs transition ${!selectedTag ? "bg-zinc-700 text-zinc-200" : "bg-zinc-900 text-zinc-500 hover:text-zinc-300"}`}>
          All
        </button>
        {allTags.map(tag => (
          <button key={tag} onClick={() => setSelectedTag(tag === selectedTag ? null : tag)}
            className={`px-2 py-1 rounded text-xs transition ${selectedTag === tag ? "bg-emerald-900/50 text-emerald-300" : "bg-zinc-900 text-zinc-500 hover:text-zinc-300"}`}>
            {tag}
          </button>
        ))}
      </div>

      {/* Memory entries */}
      <div className="space-y-3">
        {filtered.map(mem => (
          <div key={mem.id} className="bg-zinc-900 rounded-xl border border-zinc-800 overflow-hidden">
            <button onClick={() => setExpanded(expanded === mem.id ? null : mem.id)}
              className="w-full text-left p-4 hover:bg-zinc-800/50 transition">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-lg bg-purple-900/30 flex items-center justify-center">
                    <Brain size={14} className="text-purple-400" />
                  </div>
                  <div>
                    <div className="text-sm font-medium text-zinc-200 font-mono">{mem.key}</div>
                    <div className="flex items-center gap-2 mt-0.5">
                      {mem.tags.map(t => <Badge key={t}>{t}</Badge>)}
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-4 text-xs text-zinc-600">
                  <span className="flex items-center gap-1"><Eye size={10} /> {mem.accessCount}</span>
                  <span>{new Date(mem.updatedAt).toLocaleDateString()}</span>
                  <ChevronDown size={14} className={`transition ${expanded === mem.id ? "rotate-180" : ""}`} />
                </div>
              </div>
            </button>
            {expanded === mem.id && (
              <div className="px-4 pb-4 border-t border-zinc-800">
                <div className="mt-3 p-3 bg-zinc-950 rounded-lg text-sm text-zinc-300 leading-relaxed">
                  {mem.content}
                </div>
                <div className="flex items-center justify-between mt-3 text-xs text-zinc-600">
                  <div className="flex items-center gap-4">
                    <span>Source: <span className="text-zinc-400">{mem.source}</span></span>
                    <span>ID: <span className="text-zinc-400 font-mono">#{mem.id}</span></span>
                    <span className="flex items-center gap-1"><Lock size={9} /> Private storage</span>
                  </div>
                  <div className="flex gap-1">
                    <button className="px-2 py-1 rounded bg-zinc-800 text-zinc-400 hover:text-zinc-200 transition">Edit</button>
                    <button className="px-2 py-1 rounded bg-zinc-800 text-zinc-400 hover:text-red-400 transition">Delete</button>
                  </div>
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
};

// ============================================================
// MAIN APP
// ============================================================
const TABS = [
  { id: "chat", label: "Chat", icon: MessageSquare },
  { id: "dashboard", label: "Dashboard", icon: LayoutDashboard },
  { id: "extensions", label: "Extensions", icon: Puzzle },
  { id: "scheduler", label: "Scheduler", icon: Clock },
  { id: "memory", label: "Memory", icon: Brain },
];

export default function FlowClawApp() {
  const [activeTab, setActiveTab] = useState("dashboard");
  const [connected, setConnected] = useState(true);

  const TabContent = { chat: ChatTab, dashboard: DashboardTab, extensions: ExtensionsTab, scheduler: SchedulerTab, memory: MemoryTab };
  const Active = TabContent[activeTab];

  return (
    <div className="h-screen w-full bg-zinc-950 text-zinc-100 flex flex-col" style={{ fontFamily: "'Inter', system-ui, sans-serif" }}>
      {/* Top bar */}
      <div className="h-12 border-b border-zinc-800 flex items-center justify-between px-4 bg-zinc-950 shrink-0">
        <div className="flex items-center gap-3">
          <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-emerald-500 to-cyan-500 flex items-center justify-center">
            <Cpu size={15} className="text-white" />
          </div>
          <span className="font-bold text-sm tracking-tight">FlowClaw</span>
          <Badge>v0.1.0-alpha</Badge>
        </div>

        <div className="flex items-center gap-1">
          {TABS.map(tab => (
            <button key={tab.id} onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium transition ${
                activeTab === tab.id ? "bg-zinc-800 text-zinc-100" : "text-zinc-500 hover:text-zinc-300 hover:bg-zinc-900"
              }`}>
              <tab.icon size={13} />
              {tab.label}
            </button>
          ))}
        </div>

        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 px-3 py-1.5 bg-zinc-900 border border-zinc-800 rounded-lg">
            <span className={`w-1.5 h-1.5 rounded-full ${connected ? "bg-emerald-400" : "bg-red-400"}`} />
            <span className="text-xs text-zinc-400 font-mono">0x1a2b...7890</span>
          </div>
          <button onClick={() => setConnected(!connected)}
            className="p-1.5 rounded-lg hover:bg-zinc-800 text-zinc-500 transition">
            {connected ? <Wallet size={15} /> : <LogOut size={15} />}
          </button>
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-hidden">
        <Active />
      </div>
    </div>
  );
}
