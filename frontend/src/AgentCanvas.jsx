// FlowClaw — Agent Canvas
// Spatial view of agents as cards on a canvas, with a unified chat sidebar.
// Users can select agents, see their status/activity, and chat via the sidebar.

import { useState, useEffect, useRef, useCallback } from "react";
import {
  Cpu, Send, Plus, Trash2, MessageSquare, Activity, Star,
  Loader2, CheckCircle, X, ChevronRight, Zap, Lock, Database,
  ExternalLink, AlertTriangle, Hash, Clock, Brain, Globe,
  Terminal, Settings, Power, GitBranch, Maximize2, Minimize2,
  Move, Eye, Users, ArrowRight, Sparkles, MoreHorizontal
} from "lucide-react";
import { api } from "./api";
import { getExplorerUrl } from "./flow-config";
import MarkdownText from "./MarkdownText";

// ─── Agent Card on the Canvas ───────────────────────────────────────────────

const AGENT_COLORS = [
  { from: "from-purple-500", to: "to-pink-500", ring: "ring-purple-500/30", bg: "bg-purple-500/10", text: "text-purple-400", border: "border-purple-800/50" },
  { from: "from-emerald-500", to: "to-cyan-500", ring: "ring-emerald-500/30", bg: "bg-emerald-500/10", text: "text-emerald-400", border: "border-emerald-800/50" },
  { from: "from-blue-500", to: "to-indigo-500", ring: "ring-blue-500/30", bg: "bg-blue-500/10", text: "text-blue-400", border: "border-blue-800/50" },
  { from: "from-amber-500", to: "to-orange-500", ring: "ring-amber-500/30", bg: "bg-amber-500/10", text: "text-amber-400", border: "border-amber-800/50" },
  { from: "from-rose-500", to: "to-red-500", ring: "ring-rose-500/30", bg: "bg-rose-500/10", text: "text-rose-400", border: "border-rose-800/50" },
  { from: "from-cyan-500", to: "to-teal-500", ring: "ring-cyan-500/30", bg: "bg-cyan-500/10", text: "text-cyan-400", border: "border-cyan-800/50" },
];

const getAgentColor = (id) => AGENT_COLORS[(id - 1) % AGENT_COLORS.length];

const AgentCard = ({ agent, isSelected, isActive, onSelect, onDelete, latestMessage, color }) => {
  const [showMenu, setShowMenu] = useState(false);

  return (
    <div
      onClick={() => onSelect(agent.id)}
      className={`
        relative cursor-pointer rounded-2xl border p-4 transition-all duration-200
        ${isSelected
          ? `bg-zinc-900 ${color.border} ring-2 ${color.ring} shadow-lg shadow-black/20`
          : "bg-zinc-900/70 border-zinc-800 hover:border-zinc-700 hover:bg-zinc-900"
        }
        ${agent.isSubAgent ? "ml-8" : ""}
      `}
    >
      {/* Sub-agent connector line */}
      {agent.isSubAgent && (
        <div className="absolute -left-6 top-1/2 w-6 border-t border-dashed border-zinc-700" />
      )}

      {/* Header */}
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2.5">
          <div className={`w-9 h-9 rounded-xl bg-gradient-to-br ${color.from} ${color.to} flex items-center justify-center shadow-lg`}>
            {agent.isSubAgent ? (
              <GitBranch size={16} className="text-white" />
            ) : (
              <Cpu size={16} className="text-white" />
            )}
          </div>
          <div>
            <div className="flex items-center gap-1.5">
              <span className="text-sm font-semibold text-zinc-100">{agent.name}</span>
              {agent.isDefault && <Star size={10} className="text-amber-400" />}
            </div>
            <div className="text-[10px] text-zinc-500 mt-0.5">
              {agent.isSubAgent ? `Sub-agent of #${agent.parentAgentId}` : `Agent #${agent.id}`}
            </div>
          </div>
        </div>

        <div className="flex items-center gap-1">
          {/* Status dot */}
          <span className={`w-2 h-2 rounded-full ${agent.isActive !== false ? "bg-emerald-400 animate-pulse" : "bg-zinc-600"}`} />

          {/* Menu */}
          <div className="relative">
            <button
              onClick={(e) => { e.stopPropagation(); setShowMenu(!showMenu); }}
              className="p-1 rounded-lg hover:bg-zinc-800 text-zinc-500 hover:text-zinc-300 transition"
            >
              <MoreHorizontal size={14} />
            </button>
            {showMenu && (
              <div className="absolute right-0 top-full mt-1 w-36 bg-zinc-800 border border-zinc-700 rounded-lg shadow-xl z-10 overflow-hidden">
                {!agent.isDefault && (
                  <button
                    onClick={(e) => { e.stopPropagation(); onDelete(agent.id); setShowMenu(false); }}
                    className="w-full text-left px-3 py-2 text-xs text-red-400 hover:bg-zinc-700 transition flex items-center gap-2"
                  >
                    <Trash2 size={11} /> Delete Agent
                  </button>
                )}
                <button
                  onClick={(e) => { e.stopPropagation(); setShowMenu(false); }}
                  className="w-full text-left px-3 py-2 text-xs text-zinc-400 hover:bg-zinc-700 transition flex items-center gap-2"
                >
                  <Settings size={11} /> Settings
                </button>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Description */}
      {agent.description && (
        <p className="text-xs text-zinc-500 mb-3 leading-relaxed line-clamp-2">{agent.description}</p>
      )}

      {/* Status badge for sub-agents */}
      {agent.isSubAgent && agent.status && (
        <div className={`flex items-center gap-1.5 mb-3 px-2 py-1 rounded-lg text-[10px] font-medium ${
          agent.status === "running" || agent.status === "spawning"
            ? "bg-blue-900/30 border border-blue-800/40 text-blue-300"
            : agent.status === "completed"
            ? "bg-emerald-900/30 border border-emerald-800/40 text-emerald-300"
            : agent.status === "error"
            ? "bg-red-900/30 border border-red-800/40 text-red-300"
            : "bg-zinc-800 text-zinc-400"
        }`}>
          {(agent.status === "running" || agent.status === "spawning") && (
            <Loader2 size={10} className="animate-spin" />
          )}
          {agent.status === "completed" && <CheckCircle size={10} />}
          {agent.status === "error" && <AlertTriangle size={10} />}
          <span>
            {agent.status === "spawning" ? "Starting up..."
              : agent.status === "running" ? "Working on task..."
              : agent.status === "completed" ? "Task complete"
              : agent.status === "error" ? "Error"
              : agent.status}
          </span>
          {agent.totalInferences > 0 && (
            <span className="ml-auto text-zinc-500">{agent.totalInferences} tokens</span>
          )}
        </div>
      )}

      {/* Stats row */}
      <div className="flex items-center gap-3 mb-3">
        <span className="flex items-center gap-1 text-[10px] text-zinc-500">
          <MessageSquare size={10} /> {agent.sessionCount || agent.totalSessions || 0} sessions
        </span>
        <span className="flex items-center gap-1 text-[10px] text-zinc-500">
          <Zap size={10} /> {agent.inferenceCount || agent.totalInferences || 0} inferences
        </span>
        {agent.isSubAgent && agent.expiresAt && (
          <span className="flex items-center gap-1 text-[10px] text-amber-400">
            <Clock size={10} /> TTL
          </span>
        )}
      </div>

      {/* Sub-agent result preview */}
      {agent.lastResult && (
        <div className={`rounded-lg ${
          agent.status === "completed" ? "bg-emerald-900/10 border border-emerald-800/30" : `${color.bg} border ${color.border}`
        } px-3 py-2`}>
          <div className="flex items-center gap-1.5 mb-1">
            {agent.status === "completed" ? (
              <>
                <CheckCircle size={10} className="text-emerald-400" />
                <span className="text-[10px] font-medium text-emerald-400">Result</span>
              </>
            ) : (
              <>
                <Activity size={10} className={color.text} />
                <span className={`text-[10px] font-medium ${color.text}`}>Output</span>
              </>
            )}
          </div>
          <p className="text-[11px] text-zinc-400 line-clamp-2 leading-relaxed">
            {agent.lastResult.slice(0, 200)}
          </p>
          {agent.lastResult.length > 200 && (
            <span className="text-[10px] text-zinc-500 mt-1 block">
              {agent.status === "completed" ? "✓ Result sent to chat" : "Click to expand"}
            </span>
          )}
        </div>
      )}

      {/* Latest chat activity (for non-sub-agents or when no lastResult) */}
      {!agent.lastResult && latestMessage && (
        <div className={`rounded-lg ${color.bg} border ${color.border} px-3 py-2`}>
          <div className="flex items-center gap-1.5 mb-1">
            <Activity size={10} className={color.text} />
            <span className={`text-[10px] font-medium ${color.text}`}>Latest</span>
          </div>
          <p className="text-[11px] text-zinc-400 line-clamp-2 leading-relaxed">{latestMessage}</p>
        </div>
      )}

      {/* Selected indicator */}
      {isSelected && (
        <div className={`absolute -bottom-px left-1/2 -translate-x-1/2 w-12 h-0.5 rounded-full bg-gradient-to-r ${color.from} ${color.to}`} />
      )}
    </div>
  );
};

// ─── Connection Lines Between Agents (SVG overlay) ──────────────────────────

const ConnectionLines = ({ agents, cardRefs, containerRef }) => {
  const [lines, setLines] = useState([]);

  useEffect(() => {
    if (!containerRef.current) return;
    const newLines = [];
    const containerRect = containerRef.current.getBoundingClientRect();

    agents.forEach(agent => {
      if (agent.isSubAgent && agent.parentAgentId) {
        const parentEl = cardRefs.current[agent.parentAgentId];
        const childEl = cardRefs.current[agent.id];
        if (parentEl && childEl) {
          const parentRect = parentEl.getBoundingClientRect();
          const childRect = childEl.getBoundingClientRect();
          newLines.push({
            x1: parentRect.right - containerRect.left,
            y1: parentRect.top + parentRect.height / 2 - containerRect.top,
            x2: childRect.left - containerRect.left,
            y2: childRect.top + childRect.height / 2 - containerRect.top,
          });
        }
      }
    });

    setLines(newLines);
  }, [agents, cardRefs, containerRef]);

  if (lines.length === 0) return null;

  return (
    <svg className="absolute inset-0 pointer-events-none z-0" style={{ width: "100%", height: "100%" }}>
      {lines.map((line, i) => (
        <path
          key={i}
          d={`M ${line.x1} ${line.y1} C ${line.x1 + 40} ${line.y1}, ${line.x2 - 40} ${line.y2}, ${line.x2} ${line.y2}`}
          fill="none"
          stroke="rgba(113, 113, 122, 0.3)"
          strokeWidth="1.5"
          strokeDasharray="4 3"
        />
      ))}
    </svg>
  );
};

// ─── Chat Sidebar ───────────────────────────────────────────────────────────

const ChatSidebar = ({ selectedAgent, agents, onSendMessage, messages, isTyping, collapsed, onToggle }) => {
  const [input, setInput] = useState("");
  const [mentionQuery, setMentionQuery] = useState(null);
  const [mentionIdx, setMentionIdx] = useState(0);
  const messagesEnd = useRef(null);
  const inputRef = useRef(null);

  useEffect(() => {
    messagesEnd.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, isTyping]);

  const handleSend = () => {
    if (!input.trim() || isTyping) return;
    onSendMessage(input.trim());
    setInput("");
    setMentionQuery(null);
  };

  const handleKeyDown = (e) => {
    if (mentionQuery !== null) {
      const filtered = agents.filter(a =>
        a.name.toLowerCase().includes(mentionQuery.toLowerCase())
      );
      if (e.key === "ArrowDown") {
        e.preventDefault();
        setMentionIdx(prev => Math.min(prev + 1, filtered.length - 1));
        return;
      }
      if (e.key === "ArrowUp") {
        e.preventDefault();
        setMentionIdx(prev => Math.max(prev - 1, 0));
        return;
      }
      if (e.key === "Enter" && filtered[mentionIdx]) {
        e.preventDefault();
        const before = input.slice(0, input.lastIndexOf("@"));
        setInput(before + `@${filtered[mentionIdx].name} `);
        setMentionQuery(null);
        return;
      }
      if (e.key === "Escape") {
        setMentionQuery(null);
        return;
      }
    }
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const handleInputChange = (e) => {
    const val = e.target.value;
    setInput(val);

    // Check for @mention
    const atIndex = val.lastIndexOf("@");
    if (atIndex !== -1 && (atIndex === 0 || val[atIndex - 1] === " ")) {
      const query = val.slice(atIndex + 1);
      if (!query.includes(" ")) {
        setMentionQuery(query);
        setMentionIdx(0);
        return;
      }
    }
    setMentionQuery(null);
  };

  const mentionResults = mentionQuery !== null
    ? agents.filter(a => a.name.toLowerCase().includes(mentionQuery.toLowerCase()))
    : [];

  if (collapsed) {
    return (
      <div className="w-12 border-l border-zinc-800 bg-zinc-950 flex flex-col items-center pt-3">
        <button onClick={onToggle} className="p-2 rounded-lg hover:bg-zinc-800 text-zinc-400 transition" title="Expand chat">
          <MessageSquare size={16} />
        </button>
      </div>
    );
  }

  return (
    <div className="w-96 border-l border-zinc-800 bg-zinc-950 flex flex-col">
      {/* Header */}
      <div className="h-11 border-b border-zinc-800 flex items-center px-3 gap-2 shrink-0">
        <button onClick={onToggle} className="p-1 rounded hover:bg-zinc-800 text-zinc-400 transition">
          <ChevronRight size={14} />
        </button>
        <MessageSquare size={14} className="text-zinc-500" />
        <span className="text-xs font-medium text-zinc-300 flex-1">Unified Chat</span>
        {selectedAgent && (
          <span className="flex items-center gap-1.5 px-2 py-0.5 rounded-full text-[10px] bg-zinc-800 text-zinc-400">
            <ArrowRight size={8} />
            {selectedAgent.name}
          </span>
        )}
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-3 space-y-3">
        {messages.length === 0 && (
          <div className="flex flex-col items-center justify-center h-full text-center px-4">
            <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-emerald-600/20 to-cyan-600/20 border border-emerald-800/30 flex items-center justify-center mb-3">
              <Users size={20} className="text-emerald-400" />
            </div>
            <p className="text-xs text-zinc-400 mb-2">Send messages to your agents</p>
            <p className="text-[10px] text-zinc-600 leading-relaxed">
              Select an agent on the canvas, then type here.
              Use <code className="bg-zinc-800 px-1 rounded">@name</code> to mention a specific agent.
            </p>
          </div>
        )}
        {messages.map((msg, i) => (
          <div key={msg.id || i} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
            <div className={`max-w-[85%] rounded-xl px-3 py-2 ${
              msg.role === "user"
                ? "bg-emerald-600/20 border border-emerald-800/40 text-zinc-100"
                : msg.isSubAgentResult
                  ? "bg-amber-950/20 border border-amber-700/40 text-zinc-200"
                  : msg.isError
                    ? "bg-red-950/30 border border-red-800/40 text-red-200"
                    : "bg-zinc-900 border border-zinc-800 text-zinc-200"
            }`}>
              {/* Sub-agent result badge */}
              {msg.isSubAgentResult && (
                <div className="flex items-center gap-1.5 mb-1.5">
                  <div className="w-4 h-4 rounded-full bg-gradient-to-br from-amber-500 to-orange-500 flex items-center justify-center">
                    <GitBranch size={8} className="text-white" />
                  </div>
                  <span className="text-[10px] font-medium text-amber-400">{msg.agentName || "Sub-Agent"}</span>
                  <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-amber-800/30 text-amber-300">result</span>
                </div>
              )}
              {/* Agent badge for assistant messages */}
              {msg.role === "assistant" && msg.agentName && !msg.isSubAgentResult && (
                <div className="flex items-center gap-1.5 mb-1.5">
                  <div className="w-4 h-4 rounded-full bg-gradient-to-br from-purple-500 to-pink-500 flex items-center justify-center">
                    <Cpu size={8} className="text-white" />
                  </div>
                  <span className="text-[10px] font-medium text-zinc-400">{msg.agentName}</span>
                </div>
              )}
              <div className="text-xs"><MarkdownText>{msg.content}</MarkdownText></div>
              <div className="flex items-center gap-2 mt-1.5 text-[10px] text-zinc-600">
                <span>{new Date(msg.timestamp).toLocaleTimeString()}</span>
                {msg.tokensUsed && (
                  <>
                    <span className="text-zinc-700">·</span>
                    <span>{msg.tokensUsed} tokens</span>
                  </>
                )}
                {msg.onChain && (
                  <>
                    <span className="text-zinc-700">·</span>
                    <span className="text-emerald-600 flex items-center gap-0.5"><Lock size={8} /> on-chain</span>
                  </>
                )}
              </div>
            </div>
          </div>
        ))}
        {isTyping && (
          <div className="flex justify-start">
            <div className="bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-2 flex items-center gap-2">
              <Loader2 size={11} className="animate-spin text-zinc-400" />
              <span className="text-[10px] text-zinc-500">
                {selectedAgent?.name || "Agent"} is thinking...
              </span>
            </div>
          </div>
        )}
        <div ref={messagesEnd} />
      </div>

      {/* @mention autocomplete */}
      {mentionResults.length > 0 && (
        <div className="mx-3 mb-1 bg-zinc-800 border border-zinc-700 rounded-lg shadow-xl overflow-hidden">
          {mentionResults.slice(0, 5).map((a, i) => (
            <button
              key={a.id}
              onClick={() => {
                const before = input.slice(0, input.lastIndexOf("@"));
                setInput(before + `@${a.name} `);
                setMentionQuery(null);
                inputRef.current?.focus();
              }}
              className={`w-full flex items-center gap-2 px-3 py-1.5 text-left transition ${
                i === mentionIdx ? "bg-zinc-700" : "hover:bg-zinc-700/50"
              }`}
            >
              <div className={`w-5 h-5 rounded-full bg-gradient-to-br ${getAgentColor(a.id).from} ${getAgentColor(a.id).to} flex items-center justify-center`}>
                <Cpu size={9} className="text-white" />
              </div>
              <span className="text-xs text-zinc-200">{a.name}</span>
              {a.isDefault && <Star size={8} className="text-amber-400" />}
            </button>
          ))}
        </div>
      )}

      {/* Input */}
      <div className="p-3 border-t border-zinc-800 shrink-0">
        <div className="flex items-center gap-2 bg-zinc-900 border border-zinc-800 rounded-xl px-3 py-1.5 focus-within:border-emerald-700 transition">
          <input
            ref={inputRef}
            type="text"
            value={input}
            onChange={handleInputChange}
            onKeyDown={handleKeyDown}
            placeholder={selectedAgent ? `Message ${selectedAgent.name}...` : "Select an agent..."}
            disabled={isTyping || !selectedAgent}
            className="flex-1 bg-transparent text-xs text-zinc-100 placeholder-zinc-600 outline-none disabled:opacity-50"
          />
          <button
            onClick={handleSend}
            disabled={isTyping || !input.trim() || !selectedAgent}
            className={`p-1.5 rounded-lg transition ${
              input.trim() && !isTyping && selectedAgent
                ? "bg-emerald-600 text-white hover:bg-emerald-500"
                : "bg-zinc-800 text-zinc-600"
            }`}
          >
            {isTyping ? <Loader2 size={12} className="animate-spin" /> : <Send size={12} />}
          </button>
        </div>
        <div className="flex items-center gap-3 mt-1.5 px-1 text-[10px] text-zinc-600">
          <span className="flex items-center gap-1"><Lock size={8} /> Encrypted</span>
          <span className="flex items-center gap-1"><Zap size={8} /> BYOK</span>
          <span className="flex items-center gap-1">@ to mention</span>
        </div>
      </div>
    </div>
  );
};

// ─── Create Agent Panel ─────────────────────────────────────────────────────

const CreateAgentPanel = ({ onClose, onCreate }) => {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [systemPrompt, setSystemPrompt] = useState("");
  const [creating, setCreating] = useState(false);

  const handleCreate = async () => {
    if (!name.trim()) return;
    setCreating(true);
    try {
      await onCreate({ name: name.trim(), description: description.trim(), systemPrompt: systemPrompt.trim() });
      onClose();
    } catch (e) {
      console.error("Create agent failed:", e);
    } finally {
      setCreating(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-zinc-900 border border-zinc-800 rounded-2xl w-full max-w-md p-6">
        <div className="flex items-center justify-between mb-5">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-purple-500 to-pink-500 flex items-center justify-center">
              <Cpu size={16} className="text-white" />
            </div>
            <h3 className="text-sm font-semibold text-zinc-100">New Agent</h3>
          </div>
          <button onClick={onClose} className="p-1 hover:bg-zinc-800 rounded-lg">
            <X size={14} className="text-zinc-500" />
          </button>
        </div>
        <div className="space-y-3">
          <div>
            <label className="text-[10px] text-zinc-500 uppercase tracking-wider mb-1 block">Name</label>
            <input value={name} onChange={e => setName(e.target.value)}
              placeholder="e.g. Research Agent, DeFi Analyst..."
              className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:border-emerald-500 outline-none" />
          </div>
          <div>
            <label className="text-[10px] text-zinc-500 uppercase tracking-wider mb-1 block">Description</label>
            <input value={description} onChange={e => setDescription(e.target.value)}
              placeholder="What does this agent specialize in?"
              className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:border-emerald-500 outline-none" />
          </div>
          <div>
            <label className="text-[10px] text-zinc-500 uppercase tracking-wider mb-1 block">System Prompt</label>
            <textarea value={systemPrompt} onChange={e => setSystemPrompt(e.target.value)}
              placeholder="Give this agent a personality or specialized instructions..."
              rows={3}
              className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:border-emerald-500 outline-none resize-none" />
          </div>
          <div className="flex gap-2 pt-2">
            <button onClick={onClose}
              className="flex-1 px-4 py-2.5 bg-zinc-800 text-zinc-400 rounded-lg text-xs hover:bg-zinc-700 transition">
              Cancel
            </button>
            <button onClick={handleCreate} disabled={!name.trim() || creating}
              className="flex-1 px-4 py-2.5 bg-emerald-600 text-white rounded-lg text-xs hover:bg-emerald-500 transition disabled:opacity-40 flex items-center justify-center gap-2">
              {creating && <Loader2 size={12} className="animate-spin" />}
              Create Agent
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

// ─── Spawn Sub-Agent Panel ──────────────────────────────────────────────────

const SpawnSubAgentPanel = ({ parentAgent, onClose, onSpawn }) => {
  const [name, setName] = useState("");
  const [task, setTask] = useState("");
  const [ttlMinutes, setTtlMinutes] = useState(60);
  const [spawning, setSpawning] = useState(false);

  const handleSpawn = async () => {
    if (!name.trim() || !task.trim()) return;
    setSpawning(true);
    try {
      await onSpawn(parentAgent.id, { name: name.trim(), description: task.trim(), ttlSeconds: ttlMinutes * 60 });
      onClose();
    } catch (e) {
      console.error("Spawn sub-agent failed:", e);
    } finally {
      setSpawning(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-zinc-900 border border-zinc-800 rounded-2xl w-full max-w-md p-6">
        <div className="flex items-center justify-between mb-5">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-amber-500 to-orange-500 flex items-center justify-center">
              <GitBranch size={16} className="text-white" />
            </div>
            <div>
              <h3 className="text-sm font-semibold text-zinc-100">Spawn Sub-Agent</h3>
              <p className="text-[10px] text-zinc-500">From {parentAgent.name}</p>
            </div>
          </div>
          <button onClick={onClose} className="p-1 hover:bg-zinc-800 rounded-lg">
            <X size={14} className="text-zinc-500" />
          </button>
        </div>
        <div className="space-y-3">
          <div>
            <label className="text-[10px] text-zinc-500 uppercase tracking-wider mb-1 block">Name</label>
            <input value={name} onChange={e => setName(e.target.value)}
              placeholder="e.g. Price Checker, Data Scraper..."
              className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:border-amber-500 outline-none" />
          </div>
          <div>
            <label className="text-[10px] text-zinc-500 uppercase tracking-wider mb-1 block">Task</label>
            <textarea value={task} onChange={e => setTask(e.target.value)}
              placeholder="What should this sub-agent do?"
              rows={2}
              className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:border-amber-500 outline-none resize-none" />
          </div>
          <div>
            <label className="text-[10px] text-zinc-500 uppercase tracking-wider mb-1 block">Time-to-Live</label>
            <select value={ttlMinutes} onChange={e => setTtlMinutes(parseInt(e.target.value))}
              className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 outline-none">
              <option value={15}>15 minutes</option>
              <option value={60}>1 hour</option>
              <option value={360}>6 hours</option>
              <option value={1440}>24 hours</option>
              <option value={0}>No expiry</option>
            </select>
          </div>
          <div className="flex gap-2 pt-2">
            <button onClick={onClose}
              className="flex-1 px-4 py-2.5 bg-zinc-800 text-zinc-400 rounded-lg text-xs hover:bg-zinc-700 transition">
              Cancel
            </button>
            <button onClick={handleSpawn} disabled={!name.trim() || !task.trim() || spawning}
              className="flex-1 px-4 py-2.5 bg-amber-600 text-white rounded-lg text-xs hover:bg-amber-500 transition disabled:opacity-40 flex items-center justify-center gap-2">
              {spawning && <Loader2 size={12} className="animate-spin" />}
              Spawn
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

// ─── Persistent state across tab switches ───────────────────────────────────
// Module-level storage so messages survive component unmount/remount
let _persistedMessages = [];
let _persistedSession = null;
let _injectedResultIds = new Set();

// ─── Main Agent Canvas Component ────────────────────────────────────────────

export default function AgentCanvas() {
  const [agents, setAgents] = useState([]);
  const [selectedAgentId, setSelectedAgentId] = useState(null);
  const [messages, setMessages] = useState(_persistedMessages); // restore on remount
  const [isTyping, setIsTyping] = useState(false);
  const [chatCollapsed, setChatCollapsed] = useState(false);
  const [showCreateAgent, setShowCreateAgent] = useState(false);
  const [showSpawnAgent, setShowSpawnAgent] = useState(false);
  const [activeSession, setActiveSession] = useState(_persistedSession);
  const [latestMessages, setLatestMessages] = useState({}); // agentId -> latest msg string
  const [error, setError] = useState(null);

  const canvasRef = useRef(null);
  const cardRefs = useRef({});
  const sessionReady = useRef(!!_persistedSession); // tracks if session init is done

  // Persist messages to module-level whenever they change
  useEffect(() => { _persistedMessages = messages; }, [messages]);
  useEffect(() => { _persistedSession = activeSession; }, [activeSession]);

  // Ensure a session exists for chat FIRST (before polling injects results)
  useEffect(() => {
    if (_persistedSession) {
      sessionReady.current = true;
      return;
    }
    (async () => {
      try {
        const sessions = await api.getSessions();
        if (sessions.length > 0) {
          setActiveSession(sessions[0]);
          if (_persistedMessages.length === 0) {
            const msgs = await api.getSessionMessages(sessions[0].id);
            setMessages(msgs.map(m => ({ ...m, agentName: "FlowClaw Agent" })));
          }
        } else {
          const newSession = await api.createSession();
          setActiveSession({ id: newSession.sessionId });
        }
      } catch (err) {
        console.warn("AgentCanvas session init failed, using session 0:", err.message);
        setActiveSession({ id: 0 });
      } finally {
        sessionReady.current = true;
      }
    })();
  }, []);

  // Fetch agents — polls faster when a sub-agent is running
  const hasRunningSubAgent = agents.some(a => a.isSubAgent && (a.status === "running" || a.status === "spawning"));

  useEffect(() => {
    const fetchAgents = async () => {
      try {
        const data = await api.getAgents();
        setAgents(data);
        if (!selectedAgentId && data.length > 0) {
          const defaultAgent = data.find(a => a.isDefault) || data[0];
          setSelectedAgentId(defaultAgent.id);
        }
        // Only inject results AFTER session init is done (prevents race condition)
        if (!sessionReady.current) return;

        // Auto-inject completed sub-agent results into chat
        const newResults = [];
        for (const agent of data) {
          if (
            agent.isSubAgent &&
            agent.status === "completed" &&
            agent.lastResult &&
            !_injectedResultIds.has(agent.id)
          ) {
            _injectedResultIds.add(agent.id);
            newResults.push({
              id: `result-${agent.id}`,
              role: "assistant",
              content: `**${agent.name}** completed:\n\n${agent.lastResult}`,
              timestamp: agent.completedAt || new Date().toISOString(),
              agentName: agent.name,
              agentId: agent.id,
              isSubAgentResult: true,
            });
          }
        }
        // Batch-add all new results at once
        if (newResults.length > 0) {
          setMessages(prev => {
            const existingIds = new Set(prev.map(m => m.id));
            const toAdd = newResults.filter(r => !existingIds.has(r.id));
            return toAdd.length > 0 ? [...prev, ...toAdd] : prev;
          });
        }
      } catch (e) {
        setAgents([]);
      }
    };
    // Small delay on first poll to let session init finish
    const startDelay = setTimeout(fetchAgents, sessionReady.current ? 0 : 1500);
    const interval = setInterval(fetchAgents, hasRunningSubAgent ? 3000 : 30000);
    return () => { clearTimeout(startDelay); clearInterval(interval); };
  }, [hasRunningSubAgent]);

  const selectedAgent = agents.find(a => a.id === selectedAgentId) || null;

  // When a completed sub-agent is selected, inject its result into chat
  const handleSelectAgent = (agentId) => {
    setSelectedAgentId(agentId);
    const agent = agents.find(a => a.id === agentId);
    if (agent && agent.isSubAgent && agent.status === "completed" && agent.lastResult) {
      // Check if we already injected this result
      const alreadyShown = messages.some(m => m.id === `result-${agentId}`);
      if (!alreadyShown) {
        setMessages(prev => [...prev, {
          id: `result-${agentId}`,
          role: "assistant",
          content: agent.lastResult,
          timestamp: agent.completedAt || new Date().toISOString(),
          agentName: agent.name,
          agentId: agentId,
          isSubAgentResult: true,
        }]);
      }
    }
  };

  // Send message in unified chat
  const handleSendMessage = async (text) => {
    if (!activeSession || !selectedAgent) return;
    setError(null);

    // Check for @mention to determine target agent
    let targetAgent = selectedAgent;
    const mentionMatch = text.match(/@(\S+)/);
    if (mentionMatch) {
      const mentioned = agents.find(a => a.name.toLowerCase() === mentionMatch[1].toLowerCase());
      if (mentioned) targetAgent = mentioned;
    }

    const userMsg = {
      id: `u-${Date.now()}`,
      role: "user",
      content: text,
      timestamp: new Date().toISOString(),
      targetAgentId: targetAgent.id,
    };
    setMessages(prev => [...prev, userMsg]);
    setIsTyping(true);

    try {
      const response = await api.sendMessage(activeSession.id, text);
      const assistantMsg = {
        id: `a-${Date.now()}`,
        role: "assistant",
        content: response.response,
        timestamp: new Date().toISOString(),
        tokensUsed: response.tokensUsed,
        onChain: response.onChain,
        agentName: targetAgent.name,
        agentId: targetAgent.id,
      };
      setMessages(prev => [...prev, assistantMsg]);
      setLatestMessages(prev => ({ ...prev, [targetAgent.id]: response.response?.slice(0, 100) }));
      // Immediately refresh agents in case LLM spawned a sub-agent during this turn
      try {
        const freshAgents = await api.getAgents();
        setAgents(freshAgents);
      } catch (_) { /* ignore */ }
    } catch (err) {
      setMessages(prev => [...prev, {
        id: `e-${Date.now()}`,
        role: "assistant",
        content: `Error: ${err.message}`,
        timestamp: new Date().toISOString(),
        isError: true,
        agentName: targetAgent.name,
      }]);
    } finally {
      setIsTyping(false);
    }
  };

  // Create agent
  const handleCreateAgent = async (agentData) => {
    const result = await api.createAgent(agentData);
    if (result.agentId) {
      await api.selectAgent(result.agentId);
      const data = await api.getAgents();
      setAgents(data);
      setSelectedAgentId(result.agentId);
    }
  };

  // Spawn sub-agent
  const handleSpawnSubAgent = async (parentId, subAgentData) => {
    const result = await api.spawnSubAgent(parentId, subAgentData);
    const data = await api.getAgents();
    setAgents(data);
  };

  // Delete agent
  const handleDeleteAgent = async (agentId) => {
    try {
      await api.deleteAgent(agentId);
      const data = await api.getAgents();
      setAgents(data);
      if (selectedAgentId === agentId) {
        const fallback = data.find(a => a.isDefault) || data[0];
        setSelectedAgentId(fallback?.id || null);
      }
    } catch (e) {
      console.error("Delete failed:", e);
    }
  };

  // Group agents: parents first, then sub-agents under their parent
  const parentAgents = agents.filter(a => !a.isSubAgent);
  const subAgentsByParent = {};
  agents.filter(a => a.isSubAgent).forEach(a => {
    const pid = a.parentAgentId || 0;
    if (!subAgentsByParent[pid]) subAgentsByParent[pid] = [];
    subAgentsByParent[pid].push(a);
  });

  return (
    <div className="flex h-full">
      {/* Canvas Area */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Canvas toolbar */}
        <div className="h-11 border-b border-zinc-800 flex items-center px-4 gap-3 shrink-0 bg-zinc-950/50">
          <Sparkles size={14} className="text-zinc-500" />
          <span className="text-xs font-medium text-zinc-300">Agent Canvas</span>
          <span className="text-[10px] text-zinc-600">{agents.length} agent{agents.length !== 1 ? "s" : ""}</span>
          <div className="flex-1" />
          <button
            onClick={() => setShowCreateAgent(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-emerald-600 hover:bg-emerald-500 text-white rounded-lg text-xs font-medium transition"
          >
            <Plus size={12} /> New Agent
          </button>
          {selectedAgent && !selectedAgent.isSubAgent && (
            <button
              onClick={() => setShowSpawnAgent(true)}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-amber-600/20 border border-amber-700/50 text-amber-300 hover:bg-amber-600/30 rounded-lg text-xs font-medium transition"
            >
              <GitBranch size={12} /> Spawn Sub-Agent
            </button>
          )}
        </div>

        {/* Canvas */}
        <div ref={canvasRef} className="flex-1 overflow-auto p-6 relative">
          {/* Background grid */}
          <div className="absolute inset-0 opacity-[0.03]"
            style={{
              backgroundImage: "radial-gradient(circle, #fff 1px, transparent 1px)",
              backgroundSize: "24px 24px",
            }}
          />

          <ConnectionLines agents={agents} cardRefs={cardRefs} containerRef={canvasRef} />

          {agents.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full text-center relative z-10">
              <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-emerald-600/20 to-cyan-600/20 border border-emerald-800/30 flex items-center justify-center mb-4">
                <Users size={28} className="text-emerald-400" />
              </div>
              <h3 className="text-lg font-medium text-zinc-200 mb-2">No Agents Yet</h3>
              <p className="text-xs text-zinc-500 max-w-sm mb-4">
                Create your first agent to get started. Each agent is a Cadence resource on the Flow blockchain
                with its own personality, tools, and memory.
              </p>
              <button
                onClick={() => setShowCreateAgent(true)}
                className="flex items-center gap-2 px-5 py-2.5 bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl text-sm font-medium transition"
              >
                <Plus size={14} /> Create First Agent
              </button>
            </div>
          ) : (
            <div className="relative z-10 grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
              {parentAgents.map(agent => (
                <div key={agent.id}>
                  <div ref={el => { cardRefs.current[agent.id] = el; }}>
                    <AgentCard
                      agent={agent}
                      isSelected={selectedAgentId === agent.id}
                      isActive={agent.isActive !== false}
                      onSelect={handleSelectAgent}
                      onDelete={handleDeleteAgent}
                      latestMessage={latestMessages[agent.id]}
                      color={getAgentColor(agent.id)}
                    />
                  </div>
                  {/* Sub-agents nested under parent */}
                  {(subAgentsByParent[agent.id] || []).map(sub => (
                    <div key={sub.id} className="mt-3" ref={el => { cardRefs.current[sub.id] = el; }}>
                      <AgentCard
                        agent={sub}
                        isSelected={selectedAgentId === sub.id}
                        isActive={sub.isActive !== false}
                        onSelect={handleSelectAgent}
                        onDelete={handleDeleteAgent}
                        latestMessage={latestMessages[sub.id]}
                        color={getAgentColor(sub.id)}
                      />
                    </div>
                  ))}
                </div>
              ))}
            </div>
          )}

          {/* Error toast */}
          {error && (
            <div className="fixed bottom-4 left-1/2 -translate-x-1/2 z-50 bg-red-950/90 border border-red-800/50 rounded-xl px-4 py-2 text-xs text-red-300 flex items-center gap-2 shadow-xl">
              <AlertTriangle size={12} />
              {error}
              <button onClick={() => setError(null)}><X size={10} /></button>
            </div>
          )}
        </div>
      </div>

      {/* Chat Sidebar */}
      <ChatSidebar
        selectedAgent={selectedAgent}
        agents={agents}
        messages={messages}
        isTyping={isTyping}
        onSendMessage={handleSendMessage}
        collapsed={chatCollapsed}
        onToggle={() => setChatCollapsed(!chatCollapsed)}
      />

      {/* Modals */}
      {showCreateAgent && (
        <CreateAgentPanel
          onClose={() => setShowCreateAgent(false)}
          onCreate={handleCreateAgent}
        />
      )}
      {showSpawnAgent && selectedAgent && (
        <SpawnSubAgentPanel
          parentAgent={selectedAgent}
          onClose={() => setShowSpawnAgent(false)}
          onSpawn={handleSpawnSubAgent}
        />
      )}
    </div>
  );
}
