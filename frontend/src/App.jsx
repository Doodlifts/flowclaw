import { useState, useEffect, useRef } from "react";
import {
  Shield, Cpu, MessageSquare, LayoutDashboard, Puzzle, Clock, Brain,
  Send, Plus, Trash2, Play, Pause, Settings, ChevronRight, Search,
  Zap, Lock, Unlock, AlertTriangle, CheckCircle, XCircle, RefreshCw,
  Activity, Database, Globe, Terminal, ArrowUpRight, Download, Upload,
  Hash, Tag, Calendar, BarChart3, Layers, Box, Eye, EyeOff, Power,
  Wallet, LogOut, Copy, ExternalLink, Star, TrendingUp, ChevronDown,
  Loader2, WifiOff, Wifi, HelpCircle, X, Info, Sparkles, Users, GitBranch
} from "lucide-react";
import { api } from "./api";
import { AuthProvider, useAuth } from "./AuthContext";
import { hasSigningKey, loadSigningKey } from "./transactionSigner";
import { getExplorerUrl, NETWORK } from "./flow-config";
import LandingPage from "./LandingPage";
import AgentCanvas from "./AgentCanvas";
import MarkdownText from "./MarkdownText";

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

const Spinner = () => (
  <Loader2 size={16} className="animate-spin text-zinc-400" />
);


// Transaction status toast
const TxToast = ({ status, txId, onClose }) => {
  if (!status) return null;
  const isSealed = status === "sealed";
  const isPending = status === "pending" || status === "sending";
  return (
    <div className={`fixed bottom-20 right-4 z-50 flex items-center gap-3 px-4 py-3 rounded-xl border shadow-xl backdrop-blur text-sm ${
      isSealed ? "bg-emerald-950/90 border-emerald-800/50 text-emerald-200" :
      isPending ? "bg-blue-950/90 border-blue-800/50 text-blue-200" :
      "bg-red-950/90 border-red-800/50 text-red-200"
    }`}>
      {isPending && <Loader2 size={14} className="animate-spin" />}
      {isSealed && <CheckCircle size={14} />}
      <span>{isPending ? "Sending to Flow..." : isSealed ? "Sealed on-chain" : "Transaction failed"}</span>
      {txId && isSealed && (
        <a href={getExplorerUrl("tx", txId)} target="_blank" rel="noopener"
          className="flex items-center gap-1 text-xs underline opacity-80 hover:opacity-100">
          FlowScan <ExternalLink size={10} />
        </a>
      )}
      {onClose && <button onClick={onClose} className="ml-2 opacity-60 hover:opacity-100"><X size={12} /></button>}
    </div>
  );
};

// Onboarding overlay for first-time users
const OnboardingTour = ({ onComplete }) => {
  const [step, setStep] = useState(0);
  const steps = [
    { title: "Welcome to FlowClaw!", description: "Your private AI agent running on the Flow blockchain. Every conversation is encrypted and stored on-chain — only you can read it.", icon: Cpu },
    { title: "Chat with your agent", description: "Send messages and get AI-powered responses via LLM. Each message is an on-chain transaction you can verify on FlowScan.", icon: MessageSquare },
    { title: "Schedule automation", description: "Set up recurring tasks — price alerts, summaries, reminders. Your agent works even when you're offline.", icon: Clock },
    { title: "Extend with tools", description: "Browse the permissionless marketplace. Install DeFi tools, memory plugins, notification channels, and more.", icon: Puzzle },
  ];
  const s = steps[step];
  const Icon = s.icon;

  return (
    <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-8 max-w-md w-full text-center">
        <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-emerald-600 to-cyan-600 flex items-center justify-center mx-auto mb-6">
          <Icon size={32} className="text-white" />
        </div>
        <h3 className="text-lg font-bold text-zinc-100 mb-2">{s.title}</h3>
        <p className="text-sm text-zinc-400 leading-relaxed mb-8">{s.description}</p>
        <div className="flex items-center justify-between">
          <div className="flex gap-1.5">
            {steps.map((_, i) => (
              <div key={i} className={`w-2 h-2 rounded-full transition ${i === step ? "bg-emerald-400 w-6" : "bg-zinc-700"}`} />
            ))}
          </div>
          <div className="flex gap-2">
            <button onClick={onComplete} className="px-3 py-1.5 text-xs text-zinc-500 hover:text-zinc-300">Skip</button>
            <button onClick={() => step < steps.length - 1 ? setStep(step + 1) : onComplete()}
              className="px-5 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-sm font-medium transition">
              {step < steps.length - 1 ? "Next" : "Get Started"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

// ============================================================
// CHAT TAB — connected to user's LLM provider via relay API
// ============================================================
const AUTOMATED_SESSION = { id: -1, label: "Automated Tasks", messageCount: 0, totalTokens: 0, isOpen: true, isAutomated: true };

const ChatTab = () => {
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState("");
  const [isTyping, setIsTyping] = useState(false);
  const [activeSession, setActiveSession] = useState(null);
  const [sessions, setSessions] = useState([]);
  const [showSessions, setShowSessions] = useState(true);
  const [error, setError] = useState(null);
  const [automatedCount, setAutomatedCount] = useState(0);
  const [automatedRead, setAutomatedRead] = useState(0);
  const messagesEnd = useRef(null);

  // Create initial session on mount
  useEffect(() => {
    (async () => {
      try {
        const existingSessions = await api.getSessions();
        if (existingSessions.length > 0) {
          setSessions(existingSessions);
          setActiveSession(existingSessions[0]);
          const msgs = await api.getSessionMessages(existingSessions[0].id);
          setMessages(msgs);
        } else {
          // Create first session
          const newSession = await api.createSession();
          const s = { id: newSession.sessionId, label: "New Chat", messageCount: 0, totalTokens: 0, isOpen: true };
          setSessions([s]);
          setActiveSession(s);
        }
      } catch (err) {
        console.warn("Could not load sessions, trying to create one:", err.message);
        try {
          const newSession = await api.createSession();
          const s = { id: newSession.sessionId, label: "New Chat", messageCount: 0, totalTokens: 0, isOpen: true };
          setSessions([s]);
          setActiveSession(s);
        } catch (err2) {
          // Last resort: use session 0 (first on-chain session) instead of random ID
          console.warn("Session creation also failed, using session 0:", err2.message);
          const s = { id: 0, label: "New Chat", messageCount: 0, totalTokens: 0, isOpen: true };
          setSessions([s]);
          setActiveSession(s);
        }
      }

      // Check for automated task results
      try {
        const autoMsgs = await api.getAutomatedMessages();
        setAutomatedCount(autoMsgs.length);
      } catch { /* no automated messages yet */ }
    })();
  }, []);

  // Poll automated messages count every 30s for badge updates
  useEffect(() => {
    const pollAuto = async () => {
      try {
        const autoMsgs = await api.getAutomatedMessages();
        setAutomatedCount(autoMsgs.length);
      } catch { /* ignore */ }
    };
    const interval = setInterval(pollAuto, 30000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => { messagesEnd.current?.scrollIntoView({ behavior: "smooth" }); }, [messages]);

  const createNewSession = async () => {
    try {
      const result = await api.createSession();
      const s = { id: result.sessionId, label: `Chat ${sessions.length + 1}`, messageCount: 0, totalTokens: 0, isOpen: true };
      setSessions(prev => [s, ...prev]);
      setActiveSession(s);
      setMessages([]);
    } catch (err) {
      console.warn("Session creation failed, using local-only session 0:", err.message);
      const s = { id: 0, label: `Chat ${sessions.length + 1}`, messageCount: 0, totalTokens: 0, isOpen: true };
      setSessions(prev => [s, ...prev]);
      setActiveSession(s);
      setMessages([]);
    }
  };

  const switchToSession = async (session) => {
    setActiveSession(session);
    setMessages([]);
    try {
      if (session.isAutomated) {
        const autoMsgs = await api.getAutomatedMessages();
        setMessages(autoMsgs.map((m) => ({
          ...m,
          isAutomated: true,
          // Extract task name from the content header "**[Task: xxx]**"
          taskName: m.content?.match(/\*\*\[Task: (.+?)\]\*\*/)?.[1] || null,
        })));
        setAutomatedRead(autoMsgs.length);
      } else {
        const msgs = await api.getSessionMessages(session.id);
        setMessages(msgs);
      }
    } catch (err) {
      console.warn("Failed to load session messages:", err.message);
    }
  };

  const sendMessage = async () => {
    if (!input.trim() || !activeSession || isTyping) return;
    setError(null);

    const userMsg = { id: messages.length + 1, role: "user", content: input, timestamp: new Date().toISOString() };
    setMessages(prev => [...prev, userMsg]);
    const messageText = input;
    setInput("");
    setIsTyping(true);

    try {
      const response = await api.sendMessage(activeSession.id, messageText);
      setMessages(prev => [...prev, {
        id: prev.length + 1,
        role: "assistant",
        content: response.response,
        timestamp: new Date().toISOString(),
        tokensUsed: response.tokensUsed,
        onChain: response.onChain,
      }]);
    } catch (err) {
      setError(err.message);
      setMessages(prev => [...prev, {
        id: prev.length + 1,
        role: "assistant",
        content: `Connection error: ${err.message}\n\nMake sure the relay API is running (python -m uvicorn relay.api:app --port 8000) and your VENICE_API_KEY is set in .env`,
        timestamp: new Date().toISOString(),
        isError: true,
      }]);
    } finally {
      setIsTyping(false);
    }
  };

  return (
    <div className="flex h-full">
      {/* Session sidebar */}
      <div className={`${showSessions ? "w-64" : "w-0"} transition-all overflow-hidden border-r border-zinc-800 bg-zinc-950 flex flex-col hidden sm:flex`}>
        <div className="p-3 border-b border-zinc-800 flex items-center justify-between">
          <span className="text-sm font-medium text-zinc-300">Sessions</span>
          <button onClick={createNewSession} className="p-1 rounded hover:bg-zinc-800 text-zinc-400"><Plus size={14} /></button>
        </div>
        <div className="flex-1 overflow-y-auto">
          {/* Automated Tasks session — pinned at top */}
          <button onClick={() => switchToSession(AUTOMATED_SESSION)}
            className={`w-full text-left p-3 border-b border-zinc-800/50 hover:bg-zinc-900 transition ${activeSession?.id === -1 ? "bg-zinc-900 border-l-2 border-l-emerald-500" : ""}`}>
            <div className="flex items-center gap-2">
              <Clock size={12} className="text-blue-400" />
              <span className="text-sm text-zinc-200 truncate">Automated Tasks</span>
              {automatedCount > automatedRead && (
                <span className="ml-auto px-1.5 py-0.5 rounded-full text-xs font-bold bg-blue-600 text-white min-w-[18px] text-center">
                  {automatedCount - automatedRead}
                </span>
              )}
            </div>
            <div className="text-xs text-zinc-600 mt-1 ml-5">{automatedCount} result{automatedCount !== 1 ? "s" : ""}</div>
          </button>

          {/* User chat sessions */}
          {sessions.map(s => (
            <button key={s.id} onClick={() => switchToSession(s)}
              className={`w-full text-left p-3 border-b border-zinc-800/50 hover:bg-zinc-900 transition ${activeSession?.id === s.id ? "bg-zinc-900 border-l-2 border-l-emerald-500" : ""}`}>
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
        <div className="h-12 border-b border-zinc-800 flex items-center px-4 gap-3 bg-zinc-950/50">
          <button onClick={() => setShowSessions(!showSessions)} className="p-1 rounded hover:bg-zinc-800 text-zinc-400">
            <MessageSquare size={16} />
          </button>
          <div className="flex-1">
            <span className="text-sm font-medium text-zinc-200">{activeSession?.label || "No Session"}</span>
            <span className="text-xs text-zinc-600 ml-2">#{activeSession?.id}</span>
          </div>
          {activeSession?.isAutomated ? (
            <Badge variant="info">Scheduled Outputs</Badge>
          ) : (
            <>
              <Badge variant="info">LLM</Badge>
              <Badge variant="success">BYOK</Badge>
            </>
          )}
        </div>

        {/* Messages */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {messages.length === 0 && !activeSession?.isAutomated && (
            <div className="flex flex-col items-center justify-center h-full text-center">
              <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-emerald-600 to-cyan-600 flex items-center justify-center mb-4">
                <Cpu size={32} className="text-white" />
              </div>
              <h3 className="text-lg font-medium text-zinc-200 mb-2">FlowClaw Agent</h3>
              <p className="text-sm text-zinc-500 max-w-md mb-4">
                Your private AI agent on the Flow blockchain. Every message is encrypted
                and stored on-chain — only you can read it.
              </p>
              <div className="flex flex-wrap items-center justify-center gap-2 mb-4">
                <span className="flex items-center gap-1.5 px-3 py-1.5 bg-zinc-900 border border-zinc-800 rounded-full text-xs text-zinc-400">
                  <Lock size={10} className="text-emerald-400" /> E2E encrypted
                </span>
                <span className="flex items-center gap-1.5 px-3 py-1.5 bg-zinc-900 border border-zinc-800 rounded-full text-xs text-zinc-400">
                  <Zap size={10} className="text-blue-400" /> LLM
                </span>
                <span className="flex items-center gap-1.5 px-3 py-1.5 bg-zinc-900 border border-zinc-800 rounded-full text-xs text-zinc-400">
                  <Database size={10} className="text-purple-400" /> On-chain storage
                </span>
              </div>
              <p className="text-xs text-zinc-600">Type a message to begin...</p>
            </div>
          )}
          {messages.length === 0 && activeSession?.isAutomated && (
            <div className="flex flex-col items-center justify-center h-full text-center">
              <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-blue-600 to-purple-600 flex items-center justify-center mb-4">
                <Clock size={32} className="text-white" />
              </div>
              <h3 className="text-lg font-medium text-zinc-200 mb-2">Automated Task Results</h3>
              <p className="text-sm text-zinc-500 max-w-md mb-4">
                Outputs from your scheduled tasks appear here. When a recurring task runs,
                the agent's response is posted to this session automatically.
              </p>
              <p className="text-xs text-zinc-600">No results yet — schedule a task in the Scheduler tab.</p>
            </div>
          )}
          {messages.map(msg => (
            <div key={msg.id} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
              <div className={`max-w-2xl rounded-2xl px-4 py-3 ${
                msg.role === "user"
                  ? "bg-emerald-600/20 border border-emerald-800/40 text-zinc-100"
                  : msg.isError
                    ? "bg-red-950/30 border border-red-800/40 text-red-200"
                  : msg.isAutomated
                    ? "bg-blue-950/30 border border-blue-800/40 text-zinc-200"
                    : "bg-zinc-900 border border-zinc-800 text-zinc-200"
              }`}>
                {msg.isAutomated && msg.taskName && (
                  <div className="flex items-center gap-1.5 mb-2 pb-1.5 border-b border-blue-800/30">
                    <Clock size={10} className="text-blue-400" />
                    <span className="text-xs font-medium text-blue-300">{msg.taskName}</span>
                  </div>
                )}
                <div className="text-sm"><MarkdownText>{msg.content}</MarkdownText></div>
                <div className="flex items-center gap-2 mt-2 text-xs text-zinc-600">
                  <span>{new Date(msg.timestamp).toLocaleTimeString()}</span>
                  {msg.tokensUsed && (
                    <>
                      <span className="text-zinc-700">|</span>
                      <span>{msg.tokensUsed} tokens</span>
                    </>
                  )}
                  {msg.role === "assistant" && !msg.isError && (
                    <>
                      <span className="text-zinc-700">|</span>
                      {msg.onChain ? (
                        <a href={getExplorerUrl("account", "0x91d0a5b7c9832a8b")} target="_blank" rel="noopener"
                          className="flex items-center gap-0.5 text-emerald-600 hover:text-emerald-400 transition">
                          <Lock size={9} /> on-chain <ExternalLink size={8} />
                        </a>
                      ) : (
                        <span className="flex items-center gap-0.5 text-zinc-600">
                          <Database size={9} /> local
                        </span>
                      )}
                    </>
                  )}
                </div>
              </div>
            </div>
          ))}
          {isTyping && (
            <div className="flex justify-start">
              <div className="bg-zinc-900 border border-zinc-800 rounded-2xl px-4 py-3">
                <div className="flex items-center gap-2 text-xs text-zinc-400">
                  <Loader2 size={12} className="animate-spin" />
                  <span>Thinking via LLM...</span>
                </div>
              </div>
            </div>
          )}
          <div ref={messagesEnd} />
        </div>

        {/* Input */}
        <div className="p-4 border-t border-zinc-800 bg-zinc-950/50">
          {activeSession?.isAutomated ? (
            <div className="flex items-center gap-2 bg-zinc-900/50 border border-zinc-800 rounded-xl px-4 py-3 text-xs text-zinc-500">
              <Clock size={12} className="text-blue-400" />
              <span>This is a read-only feed of automated task outputs. Schedule tasks in the Scheduler tab.</span>
            </div>
          ) : (
            <>
              {error && (
                <div className="mb-2 p-2 bg-red-950/30 border border-red-800/40 rounded-lg text-xs text-red-300 flex items-center gap-2">
                  <AlertTriangle size={12} />
                  {error}
                  <button onClick={() => setError(null)} className="ml-auto text-red-400 hover:text-red-300"><XCircle size={12} /></button>
                </div>
              )}
              <div className="flex items-center gap-2 bg-zinc-900 border border-zinc-800 rounded-xl px-4 py-2 focus-within:border-emerald-700 transition">
                <input
                  type="text" value={input} onChange={e => setInput(e.target.value)}
                  onKeyDown={e => e.key === "Enter" && !e.shiftKey && sendMessage()}
                  placeholder="Message your agent..."
                  disabled={isTyping}
                  className="flex-1 bg-transparent text-sm text-zinc-100 placeholder-zinc-600 outline-none disabled:opacity-50"
                />
                <button onClick={sendMessage} disabled={isTyping || !input.trim()}
                  className={`p-2 rounded-lg transition ${input.trim() && !isTyping ? "bg-emerald-600 text-white hover:bg-emerald-500" : "bg-zinc-800 text-zinc-600"}`}>
                  {isTyping ? <Loader2 size={14} className="animate-spin" /> : <Send size={14} />}
                </button>
              </div>
              <div className="flex items-center gap-3 mt-2 px-1 text-xs text-zinc-600">
                <span className="flex items-center gap-1"><Lock size={9} /> E2E encrypted on-chain</span>
                <span className="flex items-center gap-1"><Zap size={9} /> LLM</span>
                <span className="flex items-center gap-1"><Hash size={9} /> Content hashed</span>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

// ============================================================
// DASHBOARD TAB — shows real relay + on-chain state
// ============================================================
const DashboardTab = () => {
  const [status, setStatus] = useState(null);
  const [stats, setStats] = useState(null);
  const [cogStats, setCogStats] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const [s, g, c] = await Promise.all([
          api.getStatus(),
          api.getGlobalStats(),
          api.getCognitiveStats().catch(() => null),
        ]);
        setStatus(s);
        setStats(g);
        setCogStats(c);
      } catch (err) {
        console.error("Dashboard load failed:", err);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  if (loading) return <div className="p-6 flex items-center gap-2 text-zinc-400"><Spinner /> Loading dashboard...</div>;

  return (
    <div className="p-6 space-y-6 overflow-y-auto h-full">
      {/* Agent header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-emerald-600 to-cyan-600 flex items-center justify-center">
            <Cpu size={24} className="text-white" />
          </div>
          <div>
            <h2 className="text-xl font-bold text-zinc-100">FlowClaw Agent</h2>
            <div className="flex items-center gap-2 mt-0.5">
              <Badge variant={status?.connected ? "success" : "danger"}>
                {status?.connected ? "Connected" : "Disconnected"}
              </Badge>
              <span className="text-xs text-zinc-500">Your provider</span>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <div className="text-right mr-3">
            <div className="text-xs text-zinc-500">Account</div>
            <div className="text-sm text-zinc-300 font-mono">
              {status?.accountAddress ? `${status.accountAddress.slice(0,8)}...${status.accountAddress.slice(-4)}` : "—"}
            </div>
          </div>
          <button onClick={() => window.location.reload()} className="p-2 rounded-lg bg-zinc-900 border border-zinc-800 hover:bg-zinc-800 text-zinc-400 transition">
            <RefreshCw size={16} />
          </button>
        </div>
      </div>

      {/* Stats grid */}
      <div className="grid grid-cols-5 gap-3">
        <StatCard icon={Zap} label="Inferences" value={stats?.totalInferenceRequests ?? 0} sub="on-chain total" />
        <StatCard icon={MessageSquare} label="Sessions" value={stats?.totalSessions ?? 0} sub="on-chain total" color="text-blue-400" />
        <StatCard icon={Database} label="Messages" value={stats?.totalMessages ?? 0} sub="on-chain total" color="text-purple-400" />
        <StatCard icon={Activity} label="Accounts" value={stats?.totalAccounts ?? 0} sub="registered" color="text-amber-400" />
        <StatCard icon={Shield} label="Encryption" value={status?.encryptionEnabled ? "ON" : "OFF"} sub="XChaCha20" color={status?.encryptionEnabled ? "text-emerald-400" : "text-red-400"} />
      </div>

      {/* Connection details */}
      <div className="grid grid-cols-2 gap-4">
        <div className="bg-zinc-900 rounded-xl border border-zinc-800 p-4">
          <h3 className="text-sm font-medium text-zinc-300 mb-3 flex items-center gap-2">
            {status?.connected ? <Wifi size={14} className="text-emerald-400" /> : <WifiOff size={14} className="text-red-400" />}
            Relay Status
          </h3>
          <div className="space-y-2">
            <div className="flex justify-between text-sm">
              <span className="text-zinc-500">Network</span>
              <span className="text-zinc-300">{status?.network || "emulator"}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-zinc-500">Providers</span>
              <span className="text-zinc-300">{status?.availableProviders?.join(", ") || "none"}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-zinc-500">Uptime</span>
              <span className="text-zinc-300">{status?.uptime ? `${Math.round(status.uptime)}s` : "—"}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-zinc-500">Encryption</span>
              <Badge variant={status?.encryptionEnabled ? "success" : "warning"}>
                {status?.encryptionEnabled ? "Enabled" : "Disabled"}
              </Badge>
            </div>
          </div>
        </div>

        <div className="bg-zinc-900 rounded-xl border border-zinc-800 p-4">
          <h3 className="text-sm font-medium text-zinc-300 mb-3 flex items-center gap-2"><Database size={14} /> On-Chain State</h3>
          <div className="space-y-2">
            <div className="flex justify-between text-sm">
              <span className="text-zinc-500">Version</span>
              <span className="text-zinc-300">{stats?.version || "0.1.0-alpha"}</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-zinc-500">Agents</span>
              <span className="text-zinc-300">{stats?.totalAgents ?? 0} registered</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-zinc-500">Memory</span>
              <span className="text-zinc-300">{cogStats?.totalMemories ?? 0} memories ({cogStats?.totalBonds ?? 0} bonds)</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-zinc-500">Chain</span>
              <Badge variant={status?.network === "testnet" ? "warning" : status?.network === "mainnet" ? "success" : "info"}>
                {status?.network === "testnet" ? "Testnet" : status?.network === "mainnet" ? "Mainnet" : status?.network || "Emulator"}
              </Badge>
            </div>
          </div>
        </div>
      </div>

      {/* Architecture diagram */}
      <div className="bg-emerald-950/30 border border-emerald-900/50 rounded-xl p-4">
        <h4 className="text-sm font-medium text-emerald-300 mb-3">Live Architecture</h4>
        <div className="grid grid-cols-4 gap-4 text-xs text-zinc-400">
          <div className="flex items-start gap-2">
            <div className="w-5 h-5 rounded-full bg-emerald-900/50 flex items-center justify-center shrink-0 mt-0.5">
              <span className="text-emerald-400 text-xs font-bold">1</span>
            </div>
            <span>You type a message in this UI (React + Vite)</span>
          </div>
          <div className="flex items-start gap-2">
            <div className="w-5 h-5 rounded-full bg-emerald-900/50 flex items-center justify-center shrink-0 mt-0.5">
              <span className="text-emerald-400 text-xs font-bold">2</span>
            </div>
            <span>Relay API sends message on-chain via Flow CLI</span>
          </div>
          <div className="flex items-start gap-2">
            <div className="w-5 h-5 rounded-full bg-emerald-900/50 flex items-center justify-center shrink-0 mt-0.5">
              <span className="text-emerald-400 text-xs font-bold">3</span>
            </div>
            <span>LLM generates a response</span>
          </div>
          <div className="flex items-start gap-2">
            <div className="w-5 h-5 rounded-full bg-emerald-900/50 flex items-center justify-center shrink-0 mt-0.5">
              <span className="text-emerald-400 text-xs font-bold">4</span>
            </div>
            <span>Response encrypted and posted on-chain</span>
          </div>
        </div>
      </div>

      {/* Cognitive Memory Stats */}
      {cogStats && cogStats.totalMemories > 0 && (
        <div className="bg-purple-950/20 border border-purple-900/40 rounded-xl p-4">
          <h4 className="text-sm font-medium text-purple-300 mb-3 flex items-center gap-2"><Brain size={14} /> Cognitive Memory</h4>
          <div className="grid grid-cols-4 gap-3">
            <div className="text-center">
              <div className="text-xl font-bold text-zinc-100">{cogStats.totalMemories}</div>
              <div className="text-xs text-zinc-500">Total Memories</div>
            </div>
            <div className="text-center">
              <div className="text-xl font-bold text-cyan-400">{cogStats.totalBonds}</div>
              <div className="text-xs text-zinc-500">Molecular Bonds</div>
            </div>
            <div className="text-center">
              <div className="text-xl font-bold text-purple-400">{cogStats.totalMolecules}</div>
              <div className="text-xs text-zinc-500">Molecules</div>
            </div>
            <div className="text-center">
              <div className="text-xl font-bold text-emerald-400">{Math.round((cogStats.avgStrength || 0) * 100)}%</div>
              <div className="text-xs text-zinc-500">Avg Strength</div>
            </div>
          </div>
          <div className="flex items-center gap-4 mt-3 text-xs text-zinc-500">
            <span className="text-blue-400">●</span> Episodic: {cogStats.typeCounts?.episodic || 0}
            <span className="text-green-400">●</span> Semantic: {cogStats.typeCounts?.semantic || 0}
            <span className="text-amber-400">●</span> Procedural: {cogStats.typeCounts?.procedural || 0}
            <span className="text-purple-400">●</span> Identity: {cogStats.typeCounts?.self_model || 0}
            {cogStats.dreamCycleCount > 0 && <span className="ml-auto">Dream cycles: {cogStats.dreamCycleCount}</span>}
          </div>
        </div>
      )}
    </div>
  );
};

// ============================================================
// EXTENSIONS TAB — real on-chain extensions
// ============================================================
const ExtensionsTab = () => {
  const [view, setView] = useState("installed"); // "installed" or "marketplace"
  const [search, setSearch] = useState("");
  const [installed, setInstalled] = useState([]);
  const [marketplace, setMarketplace] = useState([]);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(null);
  const [error, setError] = useState(null);
  const [showPublish, setShowPublish] = useState(false);
  const [publishForm, setPublishForm] = useState({ name: "", description: "", version: "1.0.0", category: 0, sourceHash: "", tags: "" });

  useEffect(() => { loadExtensions(); }, []);

  const loadExtensions = async () => {
    try {
      const data = await api.getExtensions();
      const all = data || [];
      setInstalled(all.filter(e => e.installed || e.isInstalled));
      setMarketplace(all.filter(e => !e.installed && !e.isInstalled));
    } catch (err) {
      console.warn("Failed to load extensions:", err.message);
      setInstalled([]);
      setMarketplace([]);
    } finally {
      setLoading(false);
    }
  };

  const handleInstall = async (id) => {
    setActionLoading(id);
    setError(null);
    try {
      await api.installExtension(id);
      await loadExtensions();
    } catch (err) {
      setError(`Install failed: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handleUninstall = async (id) => {
    setActionLoading(id);
    setError(null);
    try {
      await api.uninstallExtension(id);
      await loadExtensions();
    } catch (err) {
      setError(`Uninstall failed: ${err.message}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handlePublish = async () => {
    setError(null);
    try {
      await api.publishExtension({
        name: publishForm.name,
        description: publishForm.description,
        version: publishForm.version,
        category: publishForm.category,
        sourceHash: publishForm.sourceHash || "0x" + Array.from({length: 64}, () => Math.floor(Math.random()*16).toString(16)).join(""),
        tags: publishForm.tags.split(",").map(t => t.trim()).filter(Boolean),
      });
      setShowPublish(false);
      setPublishForm({ name: "", description: "", version: "1.0.0", category: 0, sourceHash: "", tags: "" });
      await loadExtensions();
    } catch (err) {
      setError(`Publish failed: ${err.message}`);
    }
  };

  const categoryLabels = { 0: "tool", 1: "hook", 2: "composite", 3: "channel" };
  const activeList = view === "installed" ? installed : marketplace;
  const filtered = activeList.filter(e => {
    if (!search) return true;
    return e.name?.toLowerCase().includes(search.toLowerCase()) || e.description?.toLowerCase().includes(search.toLowerCase());
  });

  const ExtensionCard = ({ ext }) => {
    const isInstalled = ext.installed || ext.isInstalled;
    const cat = typeof ext.category === "number" ? (categoryLabels[ext.category] || "tool") : ext.category;
    return (
      <div className={`bg-zinc-900 rounded-xl border p-4 transition ${isInstalled ? "border-emerald-800/50" : "border-zinc-800"}`}>
        <div className="flex items-start justify-between mb-2">
          <div className="flex items-center gap-2">
            <div className={`w-8 h-8 rounded-lg flex items-center justify-center ${isInstalled ? "bg-emerald-900/50 text-emerald-400" : "bg-zinc-800 text-zinc-500"}`}>
              <CategoryIcon category={cat} />
            </div>
            <div>
              <div className="text-sm font-medium text-zinc-200">{ext.name}</div>
              <div className="text-xs text-zinc-600">v{ext.version} {ext.author ? `by ${ext.author.slice(0,8)}...` : ""}</div>
            </div>
          </div>
          {ext.isAudited && <Badge variant="success">Audited</Badge>}
        </div>
        <p className="text-xs text-zinc-400 mb-3 leading-relaxed">{ext.description}</p>
        <div className="flex items-center gap-2 mb-3 flex-wrap">
          {(ext.tags || []).map(t => <Badge key={t}>{t}</Badge>)}
        </div>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3 text-xs text-zinc-600">
            {ext.installCount !== undefined && <span className="flex items-center gap-1"><Download size={10} /> {ext.installCount}</span>}
            <Badge variant={cat === "tool" ? "info" : cat === "hook" ? "purple" : "cyan"}>{cat}</Badge>
          </div>
          <button
            onClick={() => isInstalled ? handleUninstall(ext.id) : handleInstall(ext.id)}
            disabled={actionLoading === ext.id}
            className={`px-3 py-1.5 rounded-lg text-xs font-medium transition ${
              isInstalled
                ? "bg-zinc-800 text-zinc-400 hover:bg-red-900/30 hover:text-red-400"
                : "bg-emerald-600/20 text-emerald-400 hover:bg-emerald-600/30 border border-emerald-800/50"
            } disabled:opacity-50`}>
            {actionLoading === ext.id ? <Loader2 size={12} className="animate-spin" /> : isInstalled ? "Uninstall" : "Install"}
          </button>
        </div>
      </div>
    );
  };

  return (
    <div className="p-6 space-y-5 overflow-y-auto h-full">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-bold text-zinc-100">Extensions</h2>
          <p className="text-xs text-zinc-500 mt-0.5">On-chain extensions auto-detected from your wallet and the global registry.</p>
        </div>
        <button onClick={() => setShowPublish(!showPublish)} className="flex items-center gap-2 px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-sm font-medium transition">
          <Upload size={14} /> Publish
        </button>
      </div>

      {error && (
        <div className="p-3 bg-red-950/30 border border-red-800/40 rounded-lg text-xs text-red-300 flex items-center gap-2">
          <AlertTriangle size={12} /> {error}
          <button onClick={() => setError(null)} className="ml-auto"><XCircle size={12} /></button>
        </div>
      )}

      {showPublish && (
        <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-4 space-y-3">
          <h3 className="text-sm font-medium text-zinc-200">Publish New Extension</h3>
          <div className="grid grid-cols-2 gap-3">
            <input type="text" placeholder="Extension name" value={publishForm.name} onChange={e => setPublishForm(p => ({...p, name: e.target.value}))} className="bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none" />
            <input type="text" placeholder="Version (e.g. 1.0.0)" value={publishForm.version} onChange={e => setPublishForm(p => ({...p, version: e.target.value}))} className="bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none" />
          </div>
          <input type="text" placeholder="Description" value={publishForm.description} onChange={e => setPublishForm(p => ({...p, description: e.target.value}))} className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none" />
          <div className="grid grid-cols-2 gap-3">
            <select value={publishForm.category} onChange={e => setPublishForm(p => ({...p, category: parseInt(e.target.value)}))} className="bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 outline-none">
              <option value={0}>Tool</option><option value={1}>Hook</option><option value={2}>Composite</option><option value={3}>Channel</option>
              <option value={4}>Memory Backend</option><option value={5}>Scheduler</option><option value={6}>Behavior</option><option value={7}>Integration</option>
            </select>
            <input type="text" placeholder="Tags (comma separated)" value={publishForm.tags} onChange={e => setPublishForm(p => ({...p, tags: e.target.value}))} className="bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none" />
          </div>
          <div className="flex justify-end gap-2">
            <button onClick={() => setShowPublish(false)} className="px-3 py-1.5 text-xs text-zinc-400 hover:text-zinc-200">Cancel</button>
            <button onClick={handlePublish} disabled={!publishForm.name || !publishForm.description} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-xs font-medium disabled:opacity-50">Publish On-Chain</button>
          </div>
        </div>
      )}

      {/* Installed / Marketplace toggle */}
      <div className="flex items-center gap-3">
        <div className="flex gap-1 bg-zinc-900 border border-zinc-800 rounded-lg p-1">
          <button onClick={() => setView("installed")}
            className={`px-4 py-1.5 text-xs rounded-md transition ${view === "installed" ? "bg-zinc-700 text-zinc-100" : "text-zinc-500 hover:text-zinc-300"}`}>
            Installed ({installed.length})
          </button>
          <button onClick={() => setView("marketplace")}
            className={`px-4 py-1.5 text-xs rounded-md transition ${view === "marketplace" ? "bg-zinc-700 text-zinc-100" : "text-zinc-500 hover:text-zinc-300"}`}>
            Marketplace ({marketplace.length})
          </button>
        </div>
        <div className="flex-1 relative">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-zinc-600" />
          <input type="text" value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Search extensions..." className="w-full bg-zinc-900 border border-zinc-800 rounded-lg pl-9 pr-4 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none focus:border-zinc-700" />
        </div>
      </div>

      {loading ? (
        <div className="flex items-center gap-2 text-zinc-400"><Spinner /> Loading extensions...</div>
      ) : filtered.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-center">
          <Puzzle size={32} className="text-zinc-700 mb-3" />
          {view === "installed" ? (
            <>
              <p className="text-sm text-zinc-400 mb-1">No extensions installed</p>
              <p className="text-xs text-zinc-600">Browse the marketplace to add capabilities to your agent, or publish your own.</p>
              <button onClick={() => setView("marketplace")} className="mt-3 text-xs text-teal-400 hover:text-teal-300 transition">Browse Marketplace</button>
            </>
          ) : (
            <>
              <p className="text-sm text-zinc-400 mb-1">No extensions in the marketplace yet</p>
              <p className="text-xs text-zinc-600">Be the first to publish an on-chain extension for FlowClaw agents.</p>
              <button onClick={() => setShowPublish(true)} className="mt-3 text-xs text-teal-400 hover:text-teal-300 transition">Publish an Extension</button>
            </>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-2 gap-4">
          {filtered.map(ext => <ExtensionCard key={ext.id} ext={ext} />)}
        </div>
      )}
    </div>
  );
};

// ============================================================
// SCHEDULER TAB — real on-chain tasks
// ============================================================
const SchedulerTab = () => {
  const [tasks, setTasks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showNew, setShowNew] = useState(false);
  const [error, setError] = useState(null);
  const [actionLoading, setActionLoading] = useState(false);
  const [taskForm, setTaskForm] = useState({ name: "", description: "", category: 0, prompt: "", maxTurns: 10, priority: 0, isRecurring: false, intervalSeconds: 3600, maxExecutions: 10 });
  const [expandedTask, setExpandedTask] = useState(null);
  const [taskResultsMap, setTaskResultsMap] = useState({});

  const loadTaskResults = async (taskId) => {
    if (expandedTask === taskId) { setExpandedTask(null); return; }
    setExpandedTask(taskId);
    try {
      const results = await api.getTaskResults(taskId);
      setTaskResultsMap(prev => ({ ...prev, [taskId]: results }));
    } catch (err) {
      setTaskResultsMap(prev => ({ ...prev, [taskId]: [] }));
    }
  };

  useEffect(() => {
    (async () => {
      try {
        const data = await api.getTasks();
        setTasks(data);
      } catch (err) {
        console.warn("Failed to load tasks:", err.message);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const handleSchedule = async () => {
    setActionLoading(true);
    setError(null);
    try {
      const payload = {
        name: taskForm.name,
        description: taskForm.description,
        category: taskForm.category,
        prompt: taskForm.prompt,
        maxTurns: taskForm.maxTurns,
        priority: taskForm.priority,
        executeAt: Math.floor(Date.now() / 1000) + 60,
        isRecurring: taskForm.isRecurring,
      };
      if (taskForm.isRecurring) {
        payload.intervalSeconds = taskForm.intervalSeconds;
        payload.maxExecutions = taskForm.maxExecutions;
      }
      const result = await api.scheduleTask(payload);
      setTasks(prev => [...prev, {
        id: result.taskId, name: taskForm.name, description: taskForm.description,
        category: taskForm.category, prompt: taskForm.prompt, priority: taskForm.priority,
        isRecurring: taskForm.isRecurring, isActive: true, executionCount: 0,
        intervalSeconds: taskForm.isRecurring ? taskForm.intervalSeconds : null,
        maxExecutions: taskForm.isRecurring ? taskForm.maxExecutions : null,
      }]);
      setShowNew(false);
      setTaskForm({ name: "", description: "", category: 0, prompt: "", maxTurns: 10, priority: 0, isRecurring: false, intervalSeconds: 3600, maxExecutions: 10 });
    } catch (err) {
      setError(`Schedule failed: ${err.message}`);
    } finally {
      setActionLoading(false);
    }
  };

  const handleCancel = async (taskId) => {
    try {
      await api.cancelTask(taskId);
      setTasks(prev => prev.map(t => t.id === taskId ? { ...t, isActive: false } : t));
    } catch (err) {
      setError(`Cancel failed: ${err.message}`);
    }
  };

  const priorityLabels = { 0: "low", 1: "medium", 2: "high" };

  return (
    <div className="p-6 space-y-5 overflow-y-auto h-full">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-bold text-zinc-100">Scheduled Tasks</h2>
          <p className="text-xs text-zinc-500 mt-0.5">On-chain automation. Runs even when your machine is off.</p>
        </div>
        <button onClick={() => setShowNew(!showNew)} className="flex items-center gap-2 px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-sm font-medium transition">
          <Plus size={14} /> New Task
        </button>
      </div>

      {error && (
        <div className="p-3 bg-red-950/30 border border-red-800/40 rounded-lg text-xs text-red-300 flex items-center gap-2">
          <AlertTriangle size={12} /> {error}
          <button onClick={() => setError(null)} className="ml-auto"><XCircle size={12} /></button>
        </div>
      )}

      {showNew && (
        <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-4 space-y-3">
          <h3 className="text-sm font-medium text-zinc-200">Schedule New Task</h3>
          <div className="grid grid-cols-2 gap-3">
            <input type="text" placeholder="Task name" value={taskForm.name} onChange={e => setTaskForm(p => ({...p, name: e.target.value}))} className="bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none" />
            <select value={taskForm.priority} onChange={e => setTaskForm(p => ({...p, priority: parseInt(e.target.value)}))} className="bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 outline-none">
              <option value={0}>Low Priority</option><option value={1}>Medium Priority</option><option value={2}>High Priority</option>
            </select>
          </div>
          <input type="text" placeholder="Description" value={taskForm.description} onChange={e => setTaskForm(p => ({...p, description: e.target.value}))} className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none" />
          <textarea placeholder="Agent prompt (what should the agent do?)" value={taskForm.prompt} onChange={e => setTaskForm(p => ({...p, prompt: e.target.value}))} rows={3} className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none resize-none" />
          <div className="flex items-center gap-4">
            <label className="flex items-center gap-2 text-xs text-zinc-400">
              <input type="checkbox" checked={taskForm.isRecurring} onChange={e => setTaskForm(p => ({...p, isRecurring: e.target.checked}))} className="accent-emerald-500" />
              Recurring task
            </label>
          </div>
          {taskForm.isRecurring && (
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-zinc-500 mb-1 block">Run every</label>
                <select value={taskForm.intervalSeconds} onChange={e => setTaskForm(p => ({...p, intervalSeconds: parseInt(e.target.value)}))} className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 outline-none">
                  <option value={300}>5 minutes</option>
                  <option value={900}>15 minutes</option>
                  <option value={1800}>30 minutes</option>
                  <option value={3600}>1 hour</option>
                  <option value={14400}>4 hours</option>
                  <option value={43200}>12 hours</option>
                  <option value={86400}>Daily</option>
                  <option value={604800}>Weekly</option>
                </select>
              </div>
              <div>
                <label className="text-xs text-zinc-500 mb-1 block">Max executions</label>
                <input type="number" min={1} max={1000} value={taskForm.maxExecutions} onChange={e => setTaskForm(p => ({...p, maxExecutions: parseInt(e.target.value) || 10}))} className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 outline-none" />
              </div>
            </div>
          )}
          <div className="flex justify-end gap-2">
            <button onClick={() => setShowNew(false)} className="px-3 py-1.5 text-xs text-zinc-400 hover:text-zinc-200">Cancel</button>
            <button onClick={handleSchedule} disabled={!taskForm.name || !taskForm.prompt || actionLoading} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-xs font-medium disabled:opacity-50 flex items-center gap-2">
              {actionLoading && <Loader2 size={12} className="animate-spin" />} Schedule On-Chain
            </button>
          </div>
        </div>
      )}

      {loading ? (
        <div className="flex items-center gap-2 text-zinc-400"><Spinner /> Loading tasks...</div>
      ) : tasks.length === 0 ? (
        <div className="bg-zinc-900 rounded-xl border border-zinc-800 p-8 text-center">
          <Clock size={32} className="text-zinc-700 mx-auto mb-3" />
          <p className="text-sm text-zinc-400">No scheduled tasks yet</p>
          <p className="text-xs text-zinc-600 mt-1">Click "New Task" to schedule your first on-chain task</p>
        </div>
      ) : (
        <div className="space-y-3">
          {tasks.map((task) => (
            <div key={task.id} className={`bg-zinc-900 rounded-xl border ${task.isActive ? "border-zinc-800" : "border-zinc-800/50 opacity-60"}`}>
              <div className="p-4">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-3">
                    <PriorityDot priority={priorityLabels[task.priority] || "low"} />
                    <span className="text-sm font-medium text-zinc-200">{task.name}</span>
                    {task.isRecurring && <Badge variant="info">Recurring{task.intervalSeconds ? ` · ${task.intervalSeconds >= 86400 ? `${Math.round(task.intervalSeconds/86400)}d` : task.intervalSeconds >= 3600 ? `${Math.round(task.intervalSeconds/3600)}h` : `${Math.round(task.intervalSeconds/60)}m`}` : ""}</Badge>}
                    {task.maxExecutions && <Badge>max {task.maxExecutions}</Badge>}
                    <Badge variant={task.isActive ? "success" : "danger"}>{task.isActive ? "Active" : "Cancelled"}</Badge>
                  </div>
                  <div className="flex items-center gap-2">
                    <button onClick={() => loadTaskResults(task.id)}
                      className={`flex items-center gap-1 px-2 py-1 text-xs rounded transition ${expandedTask === task.id ? "bg-emerald-900/30 text-emerald-400" : "text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800"}`}>
                      <Activity size={12} />
                      <span>Results</span>
                      <ChevronDown size={12} className={`transition-transform ${expandedTask === task.id ? "rotate-180" : ""}`} />
                    </button>
                    {task.isActive && (
                      <button onClick={() => handleCancel(task.id)} className="px-2 py-1 text-xs text-zinc-500 hover:text-red-400 hover:bg-red-900/20 rounded transition">
                        <XCircle size={14} />
                      </button>
                    )}
                  </div>
                </div>
                {task.description && <p className="text-xs text-zinc-400 mb-1">{task.description}</p>}
                {task.prompt && <p className="text-xs text-zinc-500 italic">"{task.prompt}"</p>}
              </div>

              {/* Expandable results section */}
              {expandedTask === task.id && (
                <div className="border-t border-zinc-800 px-4 py-3 bg-zinc-950/50 rounded-b-xl">
                  <h4 className="text-xs font-medium text-zinc-400 mb-2 flex items-center gap-1.5">
                    <Terminal size={10} /> Execution Results
                  </h4>
                  {!taskResultsMap[task.id] ? (
                    <div className="flex items-center gap-2 text-xs text-zinc-500 py-2"><Loader2 size={12} className="animate-spin" /> Loading results...</div>
                  ) : taskResultsMap[task.id].length === 0 ? (
                    <p className="text-xs text-zinc-600 py-2">No executions yet. The relay will run this task when it's due.</p>
                  ) : (
                    <div className="space-y-2 max-h-64 overflow-y-auto">
                      {taskResultsMap[task.id].map((result, idx) => (
                        <div key={idx} className="bg-zinc-900 border border-zinc-800 rounded-lg p-3">
                          <div className="flex items-center justify-between mb-1.5">
                            <div className="flex items-center gap-2">
                              <Badge variant={result.success !== false ? "success" : "danger"}>
                                {result.success !== false ? "Success" : "Failed"}
                              </Badge>
                              <span className="text-xs text-zinc-500">Run #{idx + 1}</span>
                            </div>
                            <span className="text-xs text-zinc-600">
                              {(result.executedAt || result.timestamp) ? new Date(result.executedAt || result.timestamp).toLocaleString() : "—"}
                            </span>
                          </div>
                          <div className="text-xs text-zinc-300 bg-zinc-950/50 rounded p-2 mt-1 max-h-32 overflow-y-auto">
                            <MarkdownText>{result.result || result.response || result.content || result.error || "No output"}</MarkdownText>
                          </div>
                          {result.tokensUsed && (
                            <div className="text-xs text-zinc-600 mt-1">{result.tokensUsed} tokens</div>
                          )}
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {/* How it works */}
      <div className="bg-emerald-950/30 border border-emerald-900/50 rounded-xl p-4">
        <h4 className="text-sm font-medium text-emerald-300 mb-2">How Scheduled Tasks Work</h4>
        <div className="grid grid-cols-4 gap-4 text-xs text-zinc-400">
          {[
            "You schedule a task on-chain via Cadence transaction",
            "Flow validators execute the handler at the scheduled time",
            "Your local relay picks up the event and runs inference",
            "Recurring tasks re-schedule themselves automatically"
          ].map((text, i) => (
            <div key={i} className="flex items-start gap-2">
              <div className="w-5 h-5 rounded-full bg-emerald-900/50 flex items-center justify-center shrink-0 mt-0.5">
                <span className="text-emerald-400 text-xs font-bold">{i + 1}</span>
              </div>
              <span>{text}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

// ============================================================
// MEMORY TAB — Cognitive Memory with molecular bonds
// ============================================================
const MEMORY_TYPE_STYLES = {
  episodic: { color: "text-blue-400", bg: "bg-blue-900/30", border: "border-blue-800/40", label: "Episodic", icon: Calendar },
  semantic: { color: "text-green-400", bg: "bg-green-900/30", border: "border-green-800/40", label: "Semantic", icon: Database },
  procedural: { color: "text-amber-400", bg: "bg-amber-900/30", border: "border-amber-800/40", label: "Procedural", icon: Terminal },
  "self-model": { color: "text-purple-400", bg: "bg-purple-900/30", border: "border-purple-800/40", label: "Identity", icon: Star },
};

const StrengthBar = ({ strength }) => {
  const filled = Math.round((strength || 0) * 5);
  return (
    <span className="font-mono text-xs" title={`Strength: ${Math.round((strength || 0) * 100)}%`}>
      {"●".repeat(filled)}{"○".repeat(5 - filled)}
    </span>
  );
};

const MemoryCard = ({ mem, typeKey, style, TypeIcon, isSubAgent, contentPreview, isLong }) => {
  const [expanded, setExpanded] = useState(false);
  return (
    <div className={`bg-zinc-900 rounded-xl border transition-all ${mem.onChain ? "border-emerald-800/40" : "border-zinc-800"} ${expanded ? "p-4" : "px-4 py-3"}`}>
      <div className="flex items-center gap-3 cursor-pointer" onClick={() => isLong && setExpanded(!expanded)}>
        <div className={`w-7 h-7 rounded-lg flex items-center justify-center shrink-0 ${
          typeKey === "episodic" ? "bg-blue-500/10" : typeKey === "semantic" ? "bg-green-500/10" : typeKey === "procedural" ? "bg-amber-500/10" : "bg-purple-500/10"
        }`}>
          {isSubAgent ? <GitBranch size={13} className={style.color} /> : <TypeIcon size={13} className={style.color} />}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="text-xs font-medium text-zinc-200 truncate">{(mem.key || "").replace(/-/g, " ").replace(/^sub agent result \d+ /, "")}</span>
            <Badge variant={typeKey === "episodic" ? "info" : typeKey === "semantic" ? "success" : typeKey === "procedural" ? "warning" : "purple"}>
              {style.label}
            </Badge>
            {mem.onChain && <Badge variant="success"><Lock size={7} className="inline mr-0.5" />Chain</Badge>}
            {isSubAgent && <Badge variant="warning">Sub-Agent</Badge>}
          </div>
          {!expanded && <p className="text-[11px] text-zinc-500 mt-0.5 truncate">{contentPreview}</p>}
        </div>
        <div className="flex items-center gap-2 shrink-0">
          {mem.importance && (
            <span className={`text-[10px] font-mono ${mem.importance >= 8 ? "text-red-400" : mem.importance >= 5 ? "text-amber-400" : "text-zinc-600"}`}>
              {"★".repeat(Math.min(3, Math.ceil(mem.importance / 3)))}
            </span>
          )}
          {mem.strength !== undefined && <StrengthBar strength={mem.strength} />}
          {mem.bondCount > 0 && <span className="text-[10px] text-cyan-500">{mem.bondCount}b</span>}
          {isLong && (
            <ChevronRight size={12} className={`text-zinc-600 transition-transform ${expanded ? "rotate-90" : ""}`} />
          )}
        </div>
      </div>
      {expanded && (
        <div className="mt-3 pl-10">
          <div className="text-xs text-zinc-400 leading-relaxed whitespace-pre-wrap max-h-64 overflow-y-auto bg-zinc-950/50 rounded-lg p-3 border border-zinc-800/50">
            <MarkdownText>{mem.content}</MarkdownText>
          </div>
          {(mem.tags || []).length > 0 && (
            <div className="flex items-center gap-1.5 mt-2 flex-wrap">
              {mem.tags.map(t => <Badge key={t} variant="info">{t}</Badge>)}
            </div>
          )}
        </div>
      )}
    </div>
  );
};

const MemoryTab = () => {
  const [memories, setMemories] = useState([]);
  const [cogStats, setCogStats] = useState(null);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [typeFilter, setTypeFilter] = useState("all");
  const [showStore, setShowStore] = useState(false);
  const [error, setError] = useState(null);
  const [actionLoading, setActionLoading] = useState(false);
  const [dreamLoading, setDreamLoading] = useState(false);
  const [memForm, setMemForm] = useState({ key: "", content: "", tags: "", source: "frontend" });

  useEffect(() => {
    (async () => {
      try {
        const [data, stats] = await Promise.all([
          api.getMemory(),
          api.getCognitiveStats().catch(() => null),
        ]);
        setMemories(data);
        setCogStats(stats);
      } catch (err) {
        console.warn("Failed to load memory:", err.message);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const handleStore = async () => {
    setActionLoading(true);
    setError(null);
    try {
      const result = await api.storeMemory(
        memForm.key,
        memForm.content,
        memForm.tags.split(",").map(t => t.trim()).filter(Boolean),
        memForm.source
      );
      // Reload to get cognitive metadata
      const data = await api.getMemory();
      setMemories(data);
      setShowStore(false);
      setMemForm({ key: "", content: "", tags: "", source: "frontend" });
    } catch (err) {
      setError(`Store failed: ${err.message}`);
    } finally {
      setActionLoading(false);
    }
  };

  const handleDreamCycle = async () => {
    setDreamLoading(true);
    setError(null);
    try {
      const result = await api.triggerDreamCycle();
      // Reload memories + stats after consolidation
      const [data, stats] = await Promise.all([api.getMemory(), api.getCognitiveStats().catch(() => null)]);
      setMemories(data);
      setCogStats(stats);
    } catch (err) {
      setError(`Dream cycle failed: ${err.message}`);
    } finally {
      setDreamLoading(false);
    }
  };

  const filtered = memories.filter(mem => {
    // Type filter
    if (typeFilter !== "all" && (mem.memoryTypeName || "episodic") !== typeFilter) return false;
    // Search filter
    if (!search) return true;
    const s = search.toLowerCase();
    return (mem.key || "").toLowerCase().includes(s) || (mem.content || "").toLowerCase().includes(s) || (mem.tags || []).some(t => t.toLowerCase().includes(s));
  });

  return (
    <div className="p-6 space-y-5 overflow-y-auto h-full">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-bold text-zinc-100">Cognitive Memory</h2>
          <p className="text-xs text-zinc-500 mt-0.5">Molecular memory with biological decay, bonds, and dream consolidation.</p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={handleDreamCycle} disabled={dreamLoading}
            className="flex items-center gap-2 px-3 py-2 bg-purple-600/20 border border-purple-800/50 hover:bg-purple-600/30 text-purple-300 rounded-lg text-xs font-medium transition disabled:opacity-50">
            {dreamLoading ? <Loader2 size={12} className="animate-spin" /> : <RefreshCw size={12} />} Dream Cycle
          </button>
          <button onClick={() => setShowStore(!showStore)} className="flex items-center gap-2 px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-sm font-medium transition">
            <Plus size={14} /> Store Memory
          </button>
        </div>
      </div>

      {/* Cognitive Stats Bar */}
      {cogStats && (
        <div className="grid grid-cols-6 gap-2">
          <div className="bg-zinc-900 rounded-lg border border-zinc-800 px-3 py-2 text-center">
            <div className="text-lg font-bold text-zinc-100">{cogStats.totalMemories || 0}</div>
            <div className="text-xs text-zinc-500">Memories</div>
          </div>
          <div className="bg-zinc-900 rounded-lg border border-zinc-800 px-3 py-2 text-center">
            <div className="text-lg font-bold text-blue-400">{cogStats.typeCounts?.episodic || 0}</div>
            <div className="text-xs text-zinc-500">Episodic</div>
          </div>
          <div className="bg-zinc-900 rounded-lg border border-zinc-800 px-3 py-2 text-center">
            <div className="text-lg font-bold text-green-400">{cogStats.typeCounts?.semantic || 0}</div>
            <div className="text-xs text-zinc-500">Semantic</div>
          </div>
          <div className="bg-zinc-900 rounded-lg border border-zinc-800 px-3 py-2 text-center">
            <div className="text-lg font-bold text-amber-400">{cogStats.typeCounts?.procedural || 0}</div>
            <div className="text-xs text-zinc-500">Procedural</div>
          </div>
          <div className="bg-zinc-900 rounded-lg border border-zinc-800 px-3 py-2 text-center">
            <div className="text-lg font-bold text-purple-400">{cogStats.typeCounts?.self_model || 0}</div>
            <div className="text-xs text-zinc-500">Identity</div>
          </div>
          <div className="bg-zinc-900 rounded-lg border border-zinc-800 px-3 py-2 text-center">
            <div className="text-lg font-bold text-cyan-400">{cogStats.totalBonds || 0}</div>
            <div className="text-xs text-zinc-500">Bonds</div>
          </div>
        </div>
      )}

      {error && (
        <div className="p-3 bg-red-950/30 border border-red-800/40 rounded-lg text-xs text-red-300 flex items-center gap-2">
          <AlertTriangle size={12} /> {error}
          <button onClick={() => setError(null)} className="ml-auto"><XCircle size={12} /></button>
        </div>
      )}

      {showStore && (
        <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-4 space-y-3">
          <h3 className="text-sm font-medium text-zinc-200">Store New Memory</h3>
          <div className="grid grid-cols-2 gap-3">
            <input type="text" placeholder="Key (e.g. user-preference)" value={memForm.key} onChange={e => setMemForm(p => ({...p, key: e.target.value}))} className="bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none" />
            <input type="text" placeholder="Tags (comma separated)" value={memForm.tags} onChange={e => setMemForm(p => ({...p, tags: e.target.value}))} className="bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none" />
          </div>
          <textarea placeholder="Memory content — will be auto-classified as episodic, semantic, procedural, or self-model based on content" value={memForm.content} onChange={e => setMemForm(p => ({...p, content: e.target.value}))} rows={3} className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none resize-none" />
          <div className="flex justify-end gap-2">
            <button onClick={() => setShowStore(false)} className="px-3 py-1.5 text-xs text-zinc-400 hover:text-zinc-200">Cancel</button>
            <button onClick={handleStore} disabled={!memForm.key || !memForm.content || actionLoading} className="px-4 py-1.5 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-xs font-medium disabled:opacity-50 flex items-center gap-2">
              {actionLoading && <Loader2 size={12} className="animate-spin" />} Store On-Chain
            </button>
          </div>
        </div>
      )}

      {/* Filter + Search */}
      <div className="flex items-center gap-3">
        <div className="flex items-center gap-1 bg-zinc-900 border border-zinc-800 rounded-lg p-1">
          {[
            { id: "all", label: "All" },
            { id: "episodic", label: "Episodic", color: "text-blue-400" },
            { id: "semantic", label: "Semantic", color: "text-green-400" },
            { id: "procedural", label: "Procedural", color: "text-amber-400" },
            { id: "self-model", label: "Identity", color: "text-purple-400" },
          ].map(f => (
            <button key={f.id} onClick={() => setTypeFilter(f.id)}
              className={`px-2.5 py-1 rounded text-xs font-medium transition ${typeFilter === f.id ? `bg-zinc-800 ${f.color || "text-zinc-100"}` : "text-zinc-500 hover:text-zinc-300"}`}>
              {f.label}
            </button>
          ))}
        </div>
        <div className="flex-1 relative">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-zinc-600" />
          <input type="text" value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Search memories..." className="w-full bg-zinc-900 border border-zinc-800 rounded-lg pl-9 pr-4 py-2 text-sm text-zinc-200 placeholder-zinc-600 outline-none focus:border-zinc-700" />
        </div>
      </div>

      {loading ? (
        <div className="flex items-center gap-2 text-zinc-400"><Spinner /> Loading cognitive memory...</div>
      ) : filtered.length === 0 ? (
        <div className="bg-zinc-900 rounded-xl border border-zinc-800 p-8 text-center">
          <Brain size={32} className="text-zinc-700 mx-auto mb-3" />
          <p className="text-sm text-zinc-400">{search || typeFilter !== "all" ? "No matching memories" : "No memories stored yet"}</p>
          <p className="text-xs text-zinc-600 mt-1">Memories are auto-classified, importance-scored, and molecularly bonded</p>
        </div>
      ) : (
        <div className="space-y-2">
          {filtered.map((mem) => {
            const typeKey = mem.memoryTypeName || "episodic";
            const style = MEMORY_TYPE_STYLES[typeKey] || MEMORY_TYPE_STYLES.episodic;
            const TypeIcon = style.icon;
            const isSubAgent = mem.source === "sub-agent" || (mem.key || "").startsWith("sub-agent-result");
            const contentPreview = (mem.content || "").slice(0, 120).replace(/\n/g, " ");
            const isLong = (mem.content || "").length > 120;
            return (
              <MemoryCard key={mem.id} mem={mem} typeKey={typeKey} style={style} TypeIcon={TypeIcon} isSubAgent={isSubAgent} contentPreview={contentPreview} isLong={isLong} />
            );
          })}
        </div>
      )}

      {/* Cognitive Architecture info */}
      <div className="bg-purple-950/20 border border-purple-900/40 rounded-xl p-4">
        <h4 className="text-sm font-medium text-purple-300 mb-2">Cognitive Memory Architecture</h4>
        <div className="grid grid-cols-4 gap-4 text-xs text-zinc-400">
          {[
            { label: "Episodic", desc: "Events and conversations. Decays at 7%/day unless bonded.", color: "text-blue-400" },
            { label: "Semantic", desc: "Facts and knowledge. Promoted from episodic patterns. 2%/day decay.", color: "text-green-400" },
            { label: "Procedural", desc: "Skills and workflows. Strengthens with use. 3%/day decay.", color: "text-amber-400" },
            { label: "Self-Model", desc: "Identity and preferences. Near-permanent at 1%/day decay.", color: "text-purple-400" },
          ].map((type, i) => (
            <div key={i}>
              <div className={`text-xs font-medium ${type.color} mb-1`}>{type.label}</div>
              <span>{type.desc}</span>
            </div>
          ))}
        </div>
        <p className="text-xs text-zinc-500 mt-3">
          Memories form molecular bonds (semantic, causal, temporal, contradictory) enabling O(k) retrieval.
          Dream cycles consolidate: decay weak memories, promote patterns, form molecule clusters.
          Only high-importance memories are committed on-chain with cryptographic receipts.
        </p>
      </div>
    </div>
  );
};

// ============================================================
// SETTINGS TAB — LLM Provider Management (BYOK)
// ============================================================

const PROVIDER_PRESETS = {
  venice:    { type: "openai-compatible", base_url: "https://api.venice.ai/api/v1", hint: "Get key at venice.ai" },
  openai:    { type: "openai-compatible", base_url: "https://api.openai.com/v1", hint: "Get key at platform.openai.com" },
  anthropic: { type: "anthropic",         base_url: "https://api.anthropic.com", hint: "Get key at console.anthropic.com" },
  openrouter:{ type: "openai-compatible", base_url: "https://openrouter.ai/api/v1", hint: "Get key at openrouter.ai" },
  together:  { type: "openai-compatible", base_url: "https://api.together.xyz/v1", hint: "Get key at together.ai" },
  groq:      { type: "openai-compatible", base_url: "https://api.groq.com/openai/v1", hint: "Get key at console.groq.com" },
  ollama:    { type: "ollama",            base_url: "http://localhost:11434", hint: "Local models — no API key needed" },
  custom:    { type: "openai-compatible", base_url: "",  hint: "Any OpenAI-compatible endpoint" },
};

const SettingsTab = () => {
  const auth = useAuth();
  const [providers, setProviders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showAddForm, setShowAddForm] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [modelsByProvider, setModelsByProvider] = useState({}); // { providerName: [model, ...] }
  const [loadingModels, setLoadingModels] = useState({});

  // Add form state
  const [formPreset, setFormPreset] = useState("venice");
  const [formName, setFormName] = useState("venice");
  const [formType, setFormType] = useState("openai-compatible");
  const [formApiKey, setFormApiKey] = useState("");
  const [formBaseUrl, setFormBaseUrl] = useState("https://api.venice.ai/api/v1");
  const [formDefault, setFormDefault] = useState(false);
  const [showKey, setShowKey] = useState(false);

  const loadProviders = async () => {
    try {
      const data = await api.getProviders();
      setProviders(data.providers || []);
    } catch (e) {
      console.warn("Failed to load providers:", e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { loadProviders(); }, []);

  const loadModelsForProvider = async (providerName) => {
    if (modelsByProvider[providerName] || loadingModels[providerName]) return;
    setLoadingModels(prev => ({ ...prev, [providerName]: true }));
    try {
      const data = await api.getProviderModels(providerName);
      setModelsByProvider(prev => ({ ...prev, [providerName]: data.models || [] }));
    } catch (e) {
      console.warn(`Failed to load models for ${providerName}:`, e);
      setModelsByProvider(prev => ({ ...prev, [providerName]: [] }));
    } finally {
      setLoadingModels(prev => ({ ...prev, [providerName]: false }));
    }
  };

  const handleSetDefaultModel = async (providerName, modelId) => {
    try {
      await api.setDefaultProvider(providerName, modelId);
      setSuccess(`Default model set to "${modelId}"`);
      await loadProviders();
      setTimeout(() => setSuccess(""), 3000);
    } catch (e) {
      setError(e.message);
    }
  };

  const handlePresetChange = (preset) => {
    setFormPreset(preset);
    const p = PROVIDER_PRESETS[preset];
    if (p) {
      setFormName(preset);
      setFormType(p.type);
      setFormBaseUrl(p.base_url);
      if (preset === "ollama") setFormApiKey("");
    }
  };

  const handleSave = async () => {
    if (!formName.trim()) { setError("Provider name is required"); return; }
    if (formType !== "ollama" && !formApiKey.trim()) { setError("API key is required"); return; }
    setSaving(true);
    setError("");
    try {
      await api.saveProvider({
        name: formName.trim(),
        type: formType,
        api_key: formApiKey.trim(),
        base_url: formBaseUrl.trim(),
        is_default: formDefault || providers.length === 0,
      });
      setSuccess(`Provider "${formName}" saved`);
      setShowAddForm(false);
      setFormApiKey("");
      await loadProviders();
      setTimeout(() => setSuccess(""), 3000);
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (name) => {
    try {
      await api.deleteProvider(name);
      await loadProviders();
      setSuccess(`Provider "${name}" removed`);
      setTimeout(() => setSuccess(""), 3000);
    } catch (e) {
      setError(e.message);
    }
  };

  const handleSetDefault = async (name) => {
    try {
      await api.setDefaultProvider(name);
      await loadProviders();
    } catch (e) {
      setError(e.message);
    }
  };

  return (
    <div className="p-4 space-y-6 max-w-2xl mx-auto">
      {/* Account Info */}
      <div className="bg-zinc-900 rounded-lg border border-zinc-800 p-4">
        <h3 className="text-sm font-medium text-zinc-300 mb-3 flex items-center gap-2"><Shield size={14} /> Account</h3>
        <div className="space-y-2 text-sm">
          <div className="flex justify-between">
            <span className="text-zinc-500">Address</span>
            <span className="text-zinc-200 font-mono text-xs">{auth?.address || "—"}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-zinc-500">Auth Method</span>
            <span className="text-zinc-200">{auth?.authMethod || "passkey"}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-zinc-500">Network</span>
            <span className="text-teal-400">{NETWORK || "mainnet"}</span>
          </div>
        </div>
      </div>

      {/* LLM Providers */}
      <div className="bg-zinc-900 rounded-lg border border-zinc-800 p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-medium text-zinc-300 flex items-center gap-2"><Cpu size={14} /> LLM Providers</h3>
          <button
            onClick={() => { setShowAddForm(!showAddForm); setError(""); }}
            className="text-xs px-3 py-1 bg-teal-600 hover:bg-teal-500 rounded-md transition-colors flex items-center gap-1"
          >
            <Plus size={12} /> Add Provider
          </button>
        </div>

        {error && <div className="text-red-400 text-xs bg-red-900/20 rounded p-2 mb-3">{error}</div>}
        {success && <div className="text-teal-400 text-xs bg-teal-900/20 rounded p-2 mb-3">{success}</div>}

        {/* Configured Providers List */}
        {loading ? (
          <div className="text-zinc-500 text-sm py-4 text-center"><Loader2 size={14} className="animate-spin inline mr-2" />Loading...</div>
        ) : providers.length === 0 ? (
          <div className="text-zinc-500 text-sm py-4 text-center border border-dashed border-zinc-700 rounded-lg">
            No LLM providers configured. Add one to start chatting with your agent.
          </div>
        ) : (
          <div className="space-y-2">
            {providers.map((p) => (
              <div key={p.name} className="bg-zinc-800/50 rounded-lg p-3 group">
                <div className="flex items-center justify-between">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium text-zinc-200">{p.name}</span>
                      {p.is_default && <span className="text-[10px] px-1.5 py-0.5 bg-teal-600/30 text-teal-400 rounded">default</span>}
                      <span className="text-[10px] px-1.5 py-0.5 bg-zinc-700 text-zinc-400 rounded">{p.type}</span>
                    </div>
                    <div className="text-xs text-zinc-500 mt-0.5 font-mono">{p.api_key}</div>
                  </div>
                  <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                    {!p.is_default && (
                      <button onClick={() => handleSetDefault(p.name)} className="text-xs px-2 py-1 text-teal-400 hover:bg-teal-600/20 rounded" title="Set as default">
                        <Star size={12} />
                      </button>
                    )}
                    <button onClick={() => handleDelete(p.name)} className="text-xs px-2 py-1 text-red-400 hover:bg-red-600/20 rounded" title="Remove">
                      <Trash2 size={12} />
                    </button>
                  </div>
                </div>
                {/* Model Selection */}
                <div className="mt-2 pt-2 border-t border-zinc-700/50">
                  <div className="flex items-center gap-2">
                    <span className="text-xs text-zinc-500">Model:</span>
                    {p.default_model ? (
                      <span className="text-xs text-zinc-300 font-mono">{p.default_model}</span>
                    ) : (
                      <span className="text-xs text-zinc-600 italic">auto</span>
                    )}
                    <button
                      onClick={() => loadModelsForProvider(p.name)}
                      className="text-xs px-2 py-0.5 text-zinc-400 hover:text-zinc-200 hover:bg-zinc-700 rounded transition-colors ml-auto"
                    >
                      {loadingModels[p.name] ? <Loader2 size={10} className="animate-spin" /> : <ChevronDown size={10} />}
                      <span className="ml-1">Models</span>
                    </button>
                  </div>
                  {modelsByProvider[p.name] && modelsByProvider[p.name].length > 0 && (
                    <div className="mt-2 max-h-40 overflow-y-auto space-y-0.5">
                      {modelsByProvider[p.name].map((m) => {
                        const modelId = typeof m === "string" ? m : m.id || m.name;
                        const isSelected = p.default_model === modelId;
                        return (
                          <button
                            key={modelId}
                            onClick={() => handleSetDefaultModel(p.name, modelId)}
                            className={`w-full text-left text-xs px-2 py-1 rounded transition-colors ${
                              isSelected
                                ? "bg-teal-600/20 text-teal-300 border border-teal-600/30"
                                : "text-zinc-400 hover:bg-zinc-700 hover:text-zinc-200"
                            }`}
                          >
                            <span className="font-mono">{modelId}</span>
                            {isSelected && <CheckCircle size={10} className="inline ml-1" />}
                          </button>
                        );
                      })}
                    </div>
                  )}
                  {modelsByProvider[p.name] && modelsByProvider[p.name].length === 0 && (
                    <div className="mt-1 text-xs text-zinc-600">No models found — check API key and endpoint</div>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Add Provider Form */}
        {showAddForm && (
          <div className="mt-4 bg-zinc-800/50 rounded-lg p-4 border border-zinc-700 space-y-3">
            <div>
              <label className="text-xs text-zinc-400 block mb-1">Provider Preset</label>
              <div className="flex flex-wrap gap-1.5">
                {Object.entries(PROVIDER_PRESETS).map(([key, val]) => (
                  <button
                    key={key}
                    onClick={() => handlePresetChange(key)}
                    className={`text-xs px-2.5 py-1 rounded-md border transition-colors ${
                      formPreset === key
                        ? "border-teal-500 bg-teal-600/20 text-teal-300"
                        : "border-zinc-700 bg-zinc-800 text-zinc-400 hover:border-zinc-600"
                    }`}
                  >
                    {key}
                  </button>
                ))}
              </div>
              {PROVIDER_PRESETS[formPreset]?.hint && (
                <p className="text-[10px] text-zinc-500 mt-1">{PROVIDER_PRESETS[formPreset].hint}</p>
              )}
            </div>

            <div>
              <label className="text-xs text-zinc-400 block mb-1">Name</label>
              <input
                value={formName}
                onChange={e => setFormName(e.target.value)}
                className="w-full bg-zinc-900 border border-zinc-700 rounded px-3 py-1.5 text-sm text-zinc-200 focus:border-teal-500 outline-none"
                placeholder="e.g. my-venice"
              />
            </div>

            {formType !== "ollama" && (
              <div>
                <label className="text-xs text-zinc-400 block mb-1">API Key</label>
                <div className="relative">
                  <input
                    type={showKey ? "text" : "password"}
                    value={formApiKey}
                    onChange={e => setFormApiKey(e.target.value)}
                    className="w-full bg-zinc-900 border border-zinc-700 rounded px-3 py-1.5 text-sm text-zinc-200 focus:border-teal-500 outline-none pr-8"
                    placeholder="sk-..."
                  />
                  <button onClick={() => setShowKey(!showKey)} className="absolute right-2 top-1.5 text-zinc-500 hover:text-zinc-300">
                    {showKey ? <EyeOff size={14} /> : <Eye size={14} />}
                  </button>
                </div>
              </div>
            )}

            <div>
              <label className="text-xs text-zinc-400 block mb-1">Base URL</label>
              <input
                value={formBaseUrl}
                onChange={e => setFormBaseUrl(e.target.value)}
                className="w-full bg-zinc-900 border border-zinc-700 rounded px-3 py-1.5 text-sm text-zinc-200 focus:border-teal-500 outline-none"
                placeholder="https://api.openai.com/v1"
              />
            </div>

            <div className="flex items-center gap-2">
              <input type="checkbox" id="is-default" checked={formDefault} onChange={e => setFormDefault(e.target.checked)} className="accent-teal-500" />
              <label htmlFor="is-default" className="text-xs text-zinc-400">Set as default provider</label>
            </div>

            <div className="flex gap-2 pt-1">
              <button
                onClick={handleSave}
                disabled={saving}
                className="flex-1 text-sm px-4 py-2 bg-teal-600 hover:bg-teal-500 disabled:opacity-50 rounded-md transition-colors flex items-center justify-center gap-2"
              >
                {saving ? <Loader2 size={14} className="animate-spin" /> : <CheckCircle size={14} />}
                {saving ? "Saving..." : "Save Provider"}
              </button>
              <button
                onClick={() => { setShowAddForm(false); setError(""); }}
                className="px-4 py-2 text-sm text-zinc-400 hover:text-zinc-200 border border-zinc-700 rounded-md transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Info */}
      <p className="text-xs text-zinc-500">
        Your API keys are stored on the relay server for your session. Each agent can use a different provider.
        Supports any OpenAI-compatible endpoint (Venice, OpenRouter, Together, Groq) plus Anthropic and local Ollama models.
      </p>

      {/* Account Security Section */}
      {auth.isLoggedIn && auth.authMethod === "passkey" && (
        <div className="mt-6 pt-4 border-t border-zinc-800">
          <h3 className="text-sm font-medium text-zinc-300 flex items-center gap-2 mb-3">
            <Shield size={14} />
            Account Security
          </h3>

          <div className="space-y-2">
            {/* Signing Key Status */}
            <div className="bg-zinc-800/50 rounded-lg p-3">
              <div className="flex items-center justify-between">
                <div>
                  <div className="text-xs text-zinc-400">Transaction Signing Key</div>
                  <div className={`text-xs mt-0.5 ${hasSigningKey(auth.user.addr) ? "text-teal-400" : "text-amber-400"}`}>
                    {hasSigningKey(auth.user.addr) ? "Available — on-chain transactions enabled" : "Missing — on-chain storage disabled"}
                  </div>
                </div>
                {hasSigningKey(auth.user.addr) ? (
                  <CheckCircle size={14} className="text-teal-500" />
                ) : (
                  <AlertTriangle size={14} className="text-amber-500" />
                )}
              </div>
            </div>

            {/* Export Signing Key */}
            {hasSigningKey(auth.user.addr) && (
              <button
                onClick={() => {
                  const jwk = loadSigningKey(auth.user.addr);
                  if (!jwk) return;
                  const blob = new Blob([JSON.stringify(jwk, null, 2)], { type: "application/json" });
                  const url = URL.createObjectURL(blob);
                  const a = document.createElement("a");
                  a.href = url;
                  a.download = `flowclaw-signing-key-${auth.user.addr}.json`;
                  a.click();
                  URL.revokeObjectURL(url);
                  setSuccess("Signing key exported. Store this file securely — it controls your on-chain account.");
                }}
                className="w-full text-left bg-zinc-800/50 rounded-lg p-3 hover:bg-zinc-700/50 transition-colors group"
              >
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-xs text-zinc-300 group-hover:text-zinc-100">Export Signing Key</div>
                    <div className="text-xs text-zinc-500 mt-0.5">Download a backup of your transaction signing key (JWK format)</div>
                  </div>
                  <Download size={14} className="text-zinc-500 group-hover:text-zinc-300" />
                </div>
              </button>
            )}

            {/* Account Address */}
            <div className="bg-zinc-800/50 rounded-lg p-3">
              <div className="text-xs text-zinc-400">Flow Account</div>
              <div className="text-xs font-mono text-zinc-300 mt-0.5 flex items-center gap-2">
                {auth.user.addr}
                <button
                  onClick={() => { navigator.clipboard.writeText(auth.user.addr); setSuccess("Address copied"); }}
                  className="text-zinc-500 hover:text-zinc-300"
                >
                  <Copy size={10} />
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};


// ============================================================
// MAIN APP — with auth, landing page, onboarding
// ============================================================
const TABS = [
  { id: "canvas", label: "Canvas", icon: Sparkles },
  { id: "chat", label: "Chat", icon: MessageSquare },
  { id: "dashboard", label: "Dashboard", icon: LayoutDashboard },
  { id: "extensions", label: "Extensions", icon: Puzzle },
  { id: "scheduler", label: "Scheduler", icon: Clock },
  { id: "memory", label: "Memory", icon: Brain },
  { id: "settings", label: "Settings", icon: Settings },
];

function FlowClawDashboard() {
  const [activeTab, setActiveTab] = useState("canvas"); // Default to canvas
  const [relayConnected, setRelayConnected] = useState(false);
  const [accountAddress, setAccountAddress] = useState("");
  const [networkName, setNetworkName] = useState("");
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [txToast, setTxToast] = useState(null);
  const auth = useAuth();

  // Multi-agent state
  const [agents, setAgents] = useState([]);
  const [activeAgentId, setActiveAgentId] = useState(null);
  const [showAgentMenu, setShowAgentMenu] = useState(false);
  const [showCreateAgent, setShowCreateAgent] = useState(false);
  const [newAgentName, setNewAgentName] = useState("");
  const [newAgentDesc, setNewAgentDesc] = useState("");
  const [newAgentPrompt, setNewAgentPrompt] = useState("");
  const [newAgentProvider, setNewAgentProvider] = useState("");
  const [newAgentModel, setNewAgentModel] = useState("");

  // Check if first visit
  useEffect(() => {
    const visited = localStorage.getItem("flowclaw_visited");
    if (!visited) {
      setShowOnboarding(true);
    }
  }, []);

  const handleOnboardingComplete = () => {
    setShowOnboarding(false);
    localStorage.setItem("flowclaw_visited", "true");
  };

  // Check relay status on mount and periodically
  useEffect(() => {
    const checkStatus = async () => {
      try {
        const status = await api.getStatus();
        setRelayConnected(status.connected);
        setAccountAddress(auth.address || "");
        setNetworkName(status.network || "");
      } catch {
        setRelayConnected(false);
      }
    };
    checkStatus();
    const interval = setInterval(checkStatus, 10000);
    return () => clearInterval(interval);
  }, [auth.address]);

  // Fetch agents
  useEffect(() => {
    const fetchAgents = async () => {
      try {
        const data = await api.getAgents();
        setAgents(data);
        if (!activeAgentId && data.length > 0) {
          const defaultAgent = data.find(a => a.isDefault) || data[0];
          setActiveAgentId(defaultAgent.id);
        }
      } catch (e) {
        // No agents available — user needs to create one
        setAgents([]);
      }
    };
    fetchAgents();
    const interval = setInterval(fetchAgents, 30000);
    return () => clearInterval(interval);
  }, []);

  const handleCreateAgent = async () => {
    if (!newAgentName.trim()) return;
    try {
      const result = await api.createAgent({
        name: newAgentName.trim(),
        description: newAgentDesc.trim(),
        systemPrompt: newAgentPrompt.trim(),
        provider: newAgentProvider.trim() || undefined,
        model: newAgentModel.trim() || undefined,
      });
      if (result.agentId) {
        setActiveAgentId(result.agentId);
        await api.selectAgent(result.agentId);
        const data = await api.getAgents();
        setAgents(data);
      }
      setShowCreateAgent(false);
      setNewAgentName("");
      setNewAgentDesc("");
      setNewAgentPrompt("");
      setNewAgentProvider("");
      setNewAgentModel("");
    } catch (e) {
      console.error("Failed to create agent:", e);
    }
  };

  const handleSelectAgent = async (agentId) => {
    setActiveAgentId(agentId);
    try { await api.selectAgent(agentId); } catch {}
    setShowAgentMenu(false);
  };

  const activeAgent = agents.find(a => a.id === activeAgentId) || agents[0] || { name: "Agent" };

  // Close agent menu on click outside
  useEffect(() => {
    if (!showAgentMenu) return;
    const handler = (e) => {
      if (!e.target.closest('.agent-switcher')) setShowAgentMenu(false);
    };
    document.addEventListener('click', handler);
    return () => document.removeEventListener('click', handler);
  }, [showAgentMenu]);

  const TabContent = { canvas: AgentCanvas, chat: ChatTab, dashboard: DashboardTab, extensions: ExtensionsTab, scheduler: SchedulerTab, memory: MemoryTab, settings: SettingsTab };
  const Active = TabContent[activeTab];

  return (
    <div className="h-screen w-full bg-zinc-950 text-zinc-100 flex flex-col" style={{ fontFamily: "'Inter', system-ui, sans-serif" }}>
      {showOnboarding && <OnboardingTour onComplete={handleOnboardingComplete} />}

      {/* Create Agent Modal */}
      {showCreateAgent && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-zinc-900 border border-zinc-800 rounded-2xl w-full max-w-md p-6">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold text-zinc-200">Create New Agent</h3>
              <button onClick={() => setShowCreateAgent(false)} className="p-1 hover:bg-zinc-800 rounded-lg">
                <X size={14} className="text-zinc-500" />
              </button>
            </div>
            <div className="space-y-3">
              <div>
                <label className="text-xs text-zinc-500 mb-1 block">Name</label>
                <input value={newAgentName} onChange={e => setNewAgentName(e.target.value)}
                  placeholder="e.g., Research Agent, DeFi Assistant..."
                  className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:border-emerald-500 focus:outline-none" />
              </div>
              <div>
                <label className="text-xs text-zinc-500 mb-1 block">Description</label>
                <input value={newAgentDesc} onChange={e => setNewAgentDesc(e.target.value)}
                  placeholder="What does this agent specialize in?"
                  className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:border-emerald-500 focus:outline-none" />
              </div>
              <div>
                <label className="text-xs text-zinc-500 mb-1 block">System Prompt (personality)</label>
                <textarea value={newAgentPrompt} onChange={e => setNewAgentPrompt(e.target.value)}
                  placeholder="Give this agent a unique personality or specialized instructions..."
                  rows={3}
                  className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:border-emerald-500 focus:outline-none resize-none" />
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="text-xs text-zinc-500 mb-1 block">Provider</label>
                  <input value={newAgentProvider} onChange={e => setNewAgentProvider(e.target.value)}
                    placeholder="e.g. venice, openai"
                    className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:border-emerald-500 focus:outline-none" />
                </div>
                <div>
                  <label className="text-xs text-zinc-500 mb-1 block">Model</label>
                  <input value={newAgentModel} onChange={e => setNewAgentModel(e.target.value)}
                    placeholder="e.g. gpt-4o, claude-sonnet-4-6"
                    className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:border-emerald-500 focus:outline-none" />
                </div>
              </div>
              <p className="text-[10px] text-zinc-600">Leave blank to use your default provider from Settings.</p>
              <div className="flex gap-2 pt-2">
                <button onClick={() => setShowCreateAgent(false)}
                  className="flex-1 px-4 py-2 bg-zinc-800 text-zinc-400 rounded-lg text-xs hover:bg-zinc-700 transition">
                  Cancel
                </button>
                <button onClick={handleCreateAgent} disabled={!newAgentName.trim()}
                  className="flex-1 px-4 py-2 bg-emerald-600 text-white rounded-lg text-xs hover:bg-emerald-500 transition disabled:opacity-40 disabled:cursor-not-allowed">
                  Create Agent
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Top bar */}
      <div className="h-12 border-b border-zinc-800 flex items-center justify-between px-2 sm:px-4 bg-zinc-950 shrink-0">
        <div className="flex items-center gap-2 sm:gap-3">
          <div className="w-7 h-7 rounded-lg bg-gradient-to-br from-emerald-500 to-cyan-500 flex items-center justify-center">
            <Cpu size={15} className="text-white" />
          </div>
          <span className="font-bold text-sm tracking-tight hidden sm:inline">FlowClaw</span>
          <Badge variant={networkName === "testnet" ? "warning" : networkName === "mainnet" ? "success" : "default"}>
            {networkName || "alpha"}
          </Badge>

          {/* Agent Switcher */}
          <div className="relative ml-2 agent-switcher">
            <button onClick={() => setShowAgentMenu(!showAgentMenu)}
              className="flex items-center gap-1.5 px-2.5 py-1 bg-zinc-900 border border-zinc-800 rounded-lg hover:border-zinc-700 transition text-xs">
              <div className="w-4 h-4 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 flex items-center justify-center">
                <Cpu size={8} className="text-white" />
              </div>
              <span className="text-zinc-300 max-w-[100px] truncate">{activeAgent?.name || "Agent"}</span>
              <ChevronDown size={10} className={`text-zinc-500 transition-transform ${showAgentMenu ? "rotate-180" : ""}`} />
              {agents.length > 1 && (
                <span className="text-[10px] text-zinc-600 bg-zinc-800 px-1 rounded">{agents.length}</span>
              )}
            </button>

            {showAgentMenu && (
              <div className="absolute top-full left-0 mt-1 w-64 bg-zinc-900 border border-zinc-800 rounded-xl shadow-xl z-50 overflow-hidden">
                <div className="p-2 border-b border-zinc-800 flex items-center justify-between">
                  <span className="text-xs text-zinc-500 font-medium">Agents</span>
                  <button onClick={() => { setShowCreateAgent(true); setShowAgentMenu(false); }}
                    className="text-xs text-emerald-400 hover:text-emerald-300 flex items-center gap-1">
                    <Plus size={10} /> New
                  </button>
                </div>
                <div className="max-h-60 overflow-y-auto">
                  {agents.map(agent => (
                    <button key={agent.id} onClick={() => handleSelectAgent(agent.id)}
                      className={`w-full flex items-center gap-2 px-3 py-2 text-left hover:bg-zinc-800 transition ${
                        agent.id === activeAgentId ? "bg-zinc-800/60" : ""
                      }`}>
                      <div className={`w-6 h-6 rounded-full flex items-center justify-center text-white text-[10px] font-bold ${
                        agent.isSubAgent ? "bg-gradient-to-br from-amber-500 to-orange-500" : "bg-gradient-to-br from-purple-500 to-pink-500"
                      }`}>
                        {agent.isSubAgent ? "S" : agent.name?.charAt(0)?.toUpperCase() || "A"}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="text-xs text-zinc-200 truncate">{agent.name}</div>
                        <div className="text-[10px] text-zinc-500 truncate">
                          {agent.isSubAgent ? `Sub-agent of #${agent.parentAgentId}` :
                           agent.isDefault ? "Default" : `Agent #${agent.id}`}
                        </div>
                      </div>
                      {agent.id === activeAgentId && (
                        <CheckCircle size={12} className="text-emerald-400 shrink-0" />
                      )}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>

        <div className="flex items-center gap-0.5 sm:gap-1 overflow-x-auto">
          {TABS.map(tab => (
            <button key={tab.id} onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-1 sm:gap-2 px-2 sm:px-3 py-1.5 rounded-lg text-xs font-medium transition whitespace-nowrap ${
                activeTab === tab.id ? "bg-zinc-800 text-zinc-100" : "text-zinc-500 hover:text-zinc-300 hover:bg-zinc-900"
              }`}>
              <tab.icon size={13} />
              <span className="hidden sm:inline">{tab.label}</span>
            </button>
          ))}
        </div>

        <div className="flex items-center gap-2 sm:gap-3">
          {accountAddress && (
            <a href={getExplorerUrl("account", accountAddress)} target="_blank" rel="noopener"
              className="hidden sm:flex items-center gap-1.5 px-3 py-1.5 bg-zinc-900 border border-zinc-800 rounded-lg hover:border-zinc-700 transition group">
              <span className={`w-1.5 h-1.5 rounded-full ${relayConnected ? "bg-emerald-400" : "bg-red-400"}`} />
              <span className="text-xs text-zinc-400 font-mono group-hover:text-zinc-300">
                {`${accountAddress.slice(0,6)}...${accountAddress.slice(-4)}`}
              </span>
              <ExternalLink size={10} className="text-zinc-600 group-hover:text-zinc-400" />
            </a>
          )}
          {auth.isLoggedIn && (
            <button onClick={auth.disconnectWallet}
              className="p-1.5 rounded-lg text-zinc-600 hover:text-zinc-300 hover:bg-zinc-800 transition" title="Disconnect">
              <LogOut size={14} />
            </button>
          )}
        </div>
      </div>

      {/* Relay disconnected banner */}
      {!relayConnected && (
        <div className="bg-amber-950/50 border-b border-amber-800/40 px-4 py-2 flex items-center gap-2 text-xs text-amber-300">
          <AlertTriangle size={12} />
          <span>Relay API disconnected. Start it with: <code className="bg-amber-900/50 px-1.5 py-0.5 rounded">python3 -m uvicorn relay.api:app --port 8000 --reload</code></span>
        </div>
      )}

      {/* Content */}
      <div className="flex-1 overflow-hidden">
        <Active />
      </div>

      {/* Transaction toast */}
      {txToast && <TxToast {...txToast} onClose={() => setTxToast(null)} />}
    </div>
  );
}

// Root component — shows landing or dashboard based on auth state
export default function FlowClawApp() {
  return (
    <AuthProvider>
      <AppRouter />
    </AuthProvider>
  );
}

function AppRouter() {
  const auth = useAuth();

  // While loading auth state, show a brief loading screen
  if (auth.loading) {
    return (
      <div className="h-screen w-full bg-zinc-950 flex items-center justify-center" style={{ fontFamily: "'Inter', system-ui, sans-serif" }}>
        <div className="flex flex-col items-center gap-4">
          <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-emerald-500 to-cyan-500 flex items-center justify-center">
            <Cpu size={24} className="text-white" />
          </div>
          <Loader2 size={20} className="animate-spin text-zinc-400" />
        </div>
      </div>
    );
  }

  // Require authentication — no dashboard without an account
  if (!auth.isLoggedIn) {
    return <LandingPage />;
  }

  return <FlowClawDashboard />;
}
