// FlowClaw — Landing Page
// First thing users see. Three auth paths:
// 1. Passkey (recommended) — instant account, no wallet needed
// 2. Flow Wallet — for existing Flow users
// 3. Email — custodial fallback (stub)

import { useState } from "react";
import {
  Cpu, Shield, Clock, Puzzle, Zap, Lock, Globe, ArrowUpRight,
  ChevronRight, Loader2, Activity, Brain, Database,
  Fingerprint, CheckCircle, Sparkles, Key
} from "lucide-react";
import { useAuth } from "./AuthContext";
import { getExplorerUrl } from "./flow-config";

const FeatureCard = ({ icon: Icon, title, description, color }) => (
  <div className="bg-zinc-900/80 backdrop-blur border border-zinc-800 rounded-2xl p-6 hover:border-zinc-700 transition group">
    <div className={`w-10 h-10 rounded-xl ${color} flex items-center justify-center mb-4 group-hover:scale-110 transition`}>
      <Icon size={20} className="text-white" />
    </div>
    <h3 className="text-base font-semibold text-zinc-100 mb-2">{title}</h3>
    <p className="text-sm text-zinc-400 leading-relaxed">{description}</p>
  </div>
);

const StepItem = ({ number, title, description }) => (
  <div className="flex items-start gap-4">
    <div className="w-8 h-8 rounded-full bg-emerald-900/50 flex items-center justify-center shrink-0 mt-0.5">
      <span className="text-emerald-400 text-sm font-bold">{number}</span>
    </div>
    <div>
      <h4 className="text-sm font-medium text-zinc-200">{title}</h4>
      <p className="text-xs text-zinc-500 mt-0.5">{description}</p>
    </div>
  </div>
);

export default function LandingPage() {
  const {
    createPasskeyAccount,
    authenticatePasskey, hasStoredPasskey, passkeyCreating, loading
  } = useAuth();

  const [showEmail, setShowEmail] = useState(false);
  const [email, setEmail] = useState("");
  const [authLoading, setAuthLoading] = useState(false);
  const [displayName, setDisplayName] = useState("");
  const [creationResult, setCreationResult] = useState(null);
  const [error, setError] = useState(null);

  const handlePasskeyCreate = async () => {
    setError(null);
    setAuthLoading(true);
    try {
      const result = await createPasskeyAccount(displayName || "FlowClaw User");
      setCreationResult(result);
    } catch (err) {
      setError(err.message);
    } finally {
      setAuthLoading(false);
    }
  };

  const handlePasskeySignIn = async () => {
    setError(null);
    setAuthLoading(true);
    try {
      await authenticatePasskey();
    } catch (err) {
      setError(err.message);
    } finally {
      setAuthLoading(false);
    }
  };

  // Wallet connect disabled — will return with Hybrid Custody
  // Email login disabled — stub only

  // Success state after account creation
  if (creationResult) {
    return (
      <div className="min-h-screen bg-zinc-950 text-zinc-100 flex items-center justify-center" style={{ fontFamily: "'Inter', system-ui, sans-serif" }}>
        <div className="max-w-md w-full mx-4">
          <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-8 text-center">
            <div className="w-16 h-16 mx-auto rounded-2xl bg-gradient-to-br from-emerald-500 to-cyan-500 flex items-center justify-center mb-6">
              <CheckCircle size={32} className="text-white" />
            </div>
            <h2 className="text-xl font-bold mb-2">Account Created</h2>
            <p className="text-sm text-zinc-400 mb-6">
              Your AI agent is ready on the Flow blockchain.
            </p>

            <div className="space-y-3 mb-6 text-left">
              <div className="flex items-center justify-between bg-zinc-800 rounded-lg px-4 py-2.5">
                <span className="text-xs text-zinc-500">Address</span>
                <span className="text-xs text-zinc-200 font-mono">{creationResult.address}</span>
              </div>
              <div className="flex items-center justify-between bg-zinc-800 rounded-lg px-4 py-2.5">
                <span className="text-xs text-zinc-500">Auth</span>
                <span className="text-xs text-emerald-400 flex items-center gap-1">
                  <Fingerprint size={12} /> Passkey
                </span>
              </div>
              <div className="flex items-center justify-between bg-zinc-800 rounded-lg px-4 py-2.5">
                <span className="text-xs text-zinc-500">Resources</span>
                <span className="text-xs text-zinc-200">12 contracts initialized</span>
              </div>
              <div className="flex items-center justify-between bg-zinc-800 rounded-lg px-4 py-2.5">
                <span className="text-xs text-zinc-500">Gas</span>
                <span className="text-xs text-blue-400">Sponsored (free)</span>
              </div>
            </div>

            <button
              onClick={() => window.location.reload()}
              className="w-full px-6 py-3 bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl text-sm font-medium transition shadow-lg shadow-emerald-500/20 flex items-center justify-center gap-2"
            >
              Enter Dashboard <ChevronRight size={14} />
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100 overflow-y-auto" style={{ fontFamily: "'Inter', system-ui, sans-serif" }}>
      {/* Nav */}
      <nav className="fixed top-0 w-full z-50 bg-zinc-950/80 backdrop-blur border-b border-zinc-800/50">
        <div className="max-w-6xl mx-auto px-6 h-14 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-emerald-500 to-cyan-500 flex items-center justify-center">
              <Cpu size={16} className="text-white" />
            </div>
            <span className="font-bold text-sm tracking-tight">FlowClaw</span>
            <span className="px-2 py-0.5 rounded-full text-xs bg-zinc-800 text-zinc-400">alpha</span>
          </div>
          <div className="flex items-center gap-3">
            <a href={getExplorerUrl("account", "0x91d0a5b7c9832a8b")} target="_blank" rel="noopener"
              className="text-xs text-zinc-500 hover:text-zinc-300 transition flex items-center gap-1">
              <Activity size={12} /> View on FlowScan
            </a>
          </div>
        </div>
      </nav>

      {/* Hero */}
      <section className="pt-32 pb-20 px-6">
        <div className="max-w-4xl mx-auto text-center">
          <div className="relative inline-block mb-8">
            <div className="absolute inset-0 bg-emerald-500/20 blur-3xl rounded-full scale-150" />
            <div className="relative w-20 h-20 mx-auto rounded-2xl bg-gradient-to-br from-emerald-500 to-cyan-500 flex items-center justify-center shadow-2xl shadow-emerald-500/20">
              <Cpu size={40} className="text-white" />
            </div>
          </div>

          <h1 className="text-4xl md:text-5xl font-bold leading-tight mb-4">
            Your AI agent.{" "}
            <span className="bg-gradient-to-r from-emerald-400 to-cyan-400 bg-clip-text text-transparent">
              Your blockchain.
            </span>
          </h1>
          <p className="text-lg text-zinc-400 max-w-2xl mx-auto mb-3">
            Encrypted conversations. Scheduled automation. Extensible tools.
            All on Flow — the consumer blockchain with sub-second finality.
          </p>
          <p className="text-sm text-zinc-600 mb-10">
            No one can read your conversations. No one can shut down your agent. You own everything.
          </p>

          {/* Auth CTAs — Three-option layout */}
          <div className="max-w-md mx-auto space-y-3">
            {/* Passkey — Primary CTA */}
            <div className="bg-zinc-900 border border-emerald-800/40 rounded-2xl p-4 hover:border-emerald-700/60 transition">
              <div className="flex items-center gap-3 mb-3">
                <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-emerald-500 to-cyan-500 flex items-center justify-center">
                  <Fingerprint size={20} className="text-white" />
                </div>
                <div className="text-left">
                  <div className="text-sm font-semibold text-zinc-100 flex items-center gap-2">
                    {hasStoredPasskey ? "Sign in with Passkey" : "Create with Passkey"}
                    <span className="text-[10px] px-1.5 py-0.5 bg-emerald-900/60 text-emerald-400 rounded-full">recommended</span>
                  </div>
                  <div className="text-xs text-zinc-500">
                    {hasStoredPasskey ? "Use your fingerprint or face to sign in" : "Touch ID, Face ID, or PIN — no wallet needed"}
                  </div>
                </div>
              </div>

              {!hasStoredPasskey && (
                <input
                  type="text"
                  value={displayName}
                  onChange={(e) => setDisplayName(e.target.value)}
                  placeholder="Display name (optional)"
                  className="w-full bg-zinc-800 border border-zinc-700 rounded-lg px-3 py-2 text-sm text-zinc-200 placeholder-zinc-600 focus:border-emerald-500 focus:outline-none mb-3"
                />
              )}

              <button
                onClick={hasStoredPasskey ? handlePasskeySignIn : handlePasskeyCreate}
                disabled={authLoading || passkeyCreating}
                className="w-full px-4 py-2.5 bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl text-sm font-medium transition shadow-lg shadow-emerald-500/20 disabled:opacity-50 flex items-center justify-center gap-2"
              >
                {authLoading || passkeyCreating ? (
                  <><Loader2 size={14} className="animate-spin" /> Creating account...</>
                ) : hasStoredPasskey ? (
                  <><Fingerprint size={14} /> Sign In</>
                ) : (
                  <><Sparkles size={14} /> Create Account</>
                )}
              </button>
            </div>

            {error && (
              <div className="text-xs text-red-400 bg-red-950/30 border border-red-900/30 rounded-lg px-3 py-2">
                {error}
              </div>
            )}

            <p className="text-xs text-zinc-600 mt-1">
              Passkey accounts are free. Gas is sponsored. No FLOW needed to start.
            </p>
          </div>
        </div>
      </section>

      {/* Live stats ticker */}
      <section className="border-y border-zinc-800/50 bg-zinc-900/30 py-4">
        <div className="max-w-4xl mx-auto px-6 flex items-center justify-center gap-8 sm:gap-12 text-xs text-zinc-500 flex-wrap">
          <div className="flex items-center gap-2">
            <Database size={12} className="text-emerald-500" />
            <span>11 smart contracts</span>
          </div>
          <div className="flex items-center gap-2">
            <Lock size={12} className="text-emerald-500" />
            <span>XChaCha20-Poly1305</span>
          </div>
          <div className="flex items-center gap-2">
            <Brain size={12} className="text-emerald-500" />
            <span>Cognitive Memory</span>
          </div>
          <div className="flex items-center gap-2">
            <Key size={12} className="text-emerald-500" />
            <span>Passkey Onboarding</span>
          </div>
          <div className="flex items-center gap-2">
            <Globe size={12} className="text-emerald-500" />
            <span>Flow Mainnet</span>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-20 px-6">
        <div className="max-w-4xl mx-auto">
          <h2 className="text-2xl font-bold text-center mb-3">Three pillars of agentic AI</h2>
          <p className="text-sm text-zinc-500 text-center mb-12 max-w-lg mx-auto">
            FlowClaw isn't just a chatbot. It's a private, autonomous, extensible AI that lives on-chain.
          </p>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
            <FeatureCard
              icon={Lock}
              title="Private & Yours"
              description="Every message encrypted with XChaCha20-Poly1305 before hitting the chain. Only you hold the key. No company can read your conversations or shut you down."
              color="bg-gradient-to-br from-emerald-600 to-emerald-700"
            />
            <FeatureCard
              icon={Clock}
              title="Scheduled Automation"
              description="Your agent works while you sleep. Schedule recurring tasks — price alerts, portfolio scans, daily summaries — all executed autonomously on-chain."
              color="bg-gradient-to-br from-blue-600 to-blue-700"
            />
            <FeatureCard
              icon={Puzzle}
              title="Extension Marketplace"
              description="Install tools and hooks from a permissionless marketplace. DeFi tools, Telegram channels, NFT minting — anyone can publish, you decide what to install."
              color="bg-gradient-to-br from-purple-600 to-purple-700"
            />
          </div>
        </div>
      </section>

      {/* How it works */}
      <section className="py-20 px-6 bg-zinc-900/30 border-y border-zinc-800/50">
        <div className="max-w-4xl mx-auto">
          <h2 className="text-2xl font-bold text-center mb-12">How it works</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
            <div className="space-y-6">
              <StepItem
                number="1"
                title="Create with a passkey"
                description="Tap a button, verify with your fingerprint or face. Your Flow account is created instantly — no wallet, no seed phrase, no FLOW needed."
              />
              <StepItem
                number="2"
                title="Chat with your agent"
                description="Messages are encrypted locally, posted on-chain, processed by Venice AI with real tool execution, and responses are encrypted back."
              />
              <StepItem
                number="3"
                title="Deploy multiple agents"
                description="Create specialized agents — a DeFi watcher, a research assistant, a creative writer. Each is a distinct on-chain resource you own."
              />
              <StepItem
                number="4"
                title="Upgrade when ready"
                description="Link to a Flow wallet for full self-custody via Hybrid Custody. Your passkey still works — linking adds control, never removes it."
              />
            </div>
            <div className="bg-zinc-900 border border-zinc-800 rounded-2xl p-6 flex flex-col justify-center">
              <h4 className="text-xs text-zinc-500 uppercase tracking-wider mb-4">Architecture</h4>
              <div className="space-y-3 text-sm">
                <div className="flex items-center gap-3">
                  <div className="w-2 h-2 rounded-full bg-emerald-400" />
                  <span className="text-zinc-300">React Frontend</span>
                  <ChevronRight size={12} className="text-zinc-700" />
                  <span className="text-zinc-500">your browser</span>
                </div>
                <div className="flex items-center gap-3">
                  <div className="w-2 h-2 rounded-full bg-blue-400" />
                  <span className="text-zinc-300">FastAPI Relay</span>
                  <ChevronRight size={12} className="text-zinc-700" />
                  <span className="text-zinc-500">bridges chain + AI</span>
                </div>
                <div className="flex items-center gap-3">
                  <div className="w-2 h-2 rounded-full bg-purple-400" />
                  <span className="text-zinc-300">Flow Blockchain</span>
                  <ChevronRight size={12} className="text-zinc-700" />
                  <span className="text-zinc-500">11 Cadence contracts</span>
                </div>
                <div className="flex items-center gap-3">
                  <div className="w-2 h-2 rounded-full bg-amber-400" />
                  <span className="text-zinc-300">Venice AI</span>
                  <ChevronRight size={12} className="text-zinc-700" />
                  <span className="text-zinc-500">tool-augmented inference</span>
                </div>
              </div>
              <div className="mt-6 pt-4 border-t border-zinc-800">
                <div className="flex items-center gap-2 text-xs text-zinc-600">
                  <Shield size={10} />
                  <span>Your data never touches a corporate database</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="py-20 px-6">
        <div className="max-w-2xl mx-auto text-center">
          <h2 className="text-2xl font-bold mb-4">Ready to own your AI?</h2>
          <p className="text-sm text-zinc-500 mb-8">
            Create an account with your passkey in seconds. Free to start — gas is on us.
          </p>
          <button
            onClick={handlePasskeyCreate}
            disabled={authLoading}
            className="px-8 py-3 bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl text-sm font-medium transition shadow-lg shadow-emerald-500/20 flex items-center gap-2 mx-auto"
          >
            <Fingerprint size={16} /> Create Your Agent
          </button>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-zinc-800/50 py-8 px-6">
        <div className="max-w-4xl mx-auto flex items-center justify-between text-xs text-zinc-600">
          <div className="flex items-center gap-2">
            <Cpu size={12} />
            <span>FlowClaw v0.2.0-alpha</span>
          </div>
          <div className="flex items-center gap-4">
            <a href={getExplorerUrl("account", "0x91d0a5b7c9832a8b")} target="_blank" rel="noopener" className="hover:text-zinc-400 transition">
              FlowScan
            </a>
            <a href="https://flow.com" target="_blank" rel="noopener" className="hover:text-zinc-400 transition">
              Flow Blockchain
            </a>
            <a href="https://venice.ai" target="_blank" rel="noopener" className="hover:text-zinc-400 transition">
              Venice AI
            </a>
          </div>
        </div>
      </footer>
    </div>
  );
}
