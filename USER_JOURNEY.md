# FlowClaw — Complete User Journey (Mainnet)

## Target: General consumers with both wallet and email auth options
## Core value props: Privacy & ownership, Agentic automation, Extensibility

---

## Phase 0: Discovery & Landing

**User arrives at flowclaw.app**

Landing page communicates three things in 5 seconds:
1. "Your AI agent, on your blockchain" — ownership message
2. "Encrypted. Scheduled. Extensible." — capability summary
3. Two CTAs: "Connect Wallet" | "Sign up with Email"

Landing page shows:
- Live demo animation of a chat going on-chain (simplified visual)
- Three feature cards: Private Chat, Scheduled Tasks, Extension Marketplace
- Social proof: transaction count, active agents, extensions published
- "How it works" — 4-step visual: Sign up → Chat → Schedule → Extend

---

## Phase 1: Onboarding (First 60 seconds)

### Path A: Wallet Connect
1. User clicks "Connect Wallet"
2. FCL popup → Lilico / Dapper / Magic wallet selection
3. Wallet approves connection
4. Backend checks if account has FlowClaw resources initialized
   - YES → skip to Phase 2 (returning user)
   - NO → "Welcome! Let's set up your agent" → one-click init transaction
5. Initialize transaction creates: Agent, Scheduler, Memory, ToolCollection, HookManager, ExtensionManager, ExtensionRegistry, encryption config
6. Loading animation: "Deploying your private AI agent on Flow..."
7. Success → redirect to Dashboard with confetti/celebration moment

### Path B: Email/Social Login
1. User clicks "Sign up with Email"
2. Email + password (or Google/Apple OAuth)
3. Backend creates a custodial Flow account (Hybrid Custody pattern)
   - Private key stored server-side (encrypted with user's password-derived key)
   - User can later "graduate" to self-custody by linking a Lilico/Dapper wallet
4. Same init transaction as Path A, but relay signs it
5. User sees same success screen — they don't need to know about wallets yet
6. Subtle banner: "Your agent runs on Flow blockchain. Link a wallet anytime for full self-custody."

### First-run experience (both paths):
- Dashboard loads with a guided tour overlay (3-4 tooltips)
- Pre-populated "Welcome" chat session with a system message explaining what FlowClaw can do
- Agent sends a first message: "Hey! I'm your private AI agent running on Flow. Everything we discuss is encrypted and stored on-chain — only you can read it. Try asking me anything, or explore the tabs above to schedule tasks, store memories, or install extensions."

---

## Phase 2: Core Loop — Daily Usage

### Chat (Primary engagement)
User flow:
1. Open FlowClaw → lands on Chat (not Dashboard — chat is the core action)
2. Previous sessions loaded from on-chain data (decrypted client-side or via relay)
3. Type message → see "Encrypting..." → "Sending to Flow..." → "Thinking..." → response appears
4. Each message shows: timestamp, token count, on-chain indicator, tx hash link
5. Click tx hash → opens Flowscan in new tab (proof it's really on-chain)
6. Create new sessions for different topics
7. Session history persists across devices (it's on-chain)

What makes this different from ChatGPT:
- "On-chain" badge on every message — constant reinforcement that this is YOUR data
- Encryption indicator — "Only you can read this"
- Session data survives server outages — it's on Flow, not in a database
- No corporate entity can read your conversations

### Memory (Passive + Active)
User flow:
1. During chat, agent auto-stores important facts: "I noticed you mentioned you prefer dark mode. I'll remember that."
2. User can also manually store memories from the Memory tab
3. Memories persist across sessions — agent recalls context from weeks ago
4. Search memories by key, content, or tags
5. Delete memories (on-chain delete transaction)

### Scheduler (Automation)
User flow:
1. User asks in chat: "Remind me to check FLOW price every morning"
2. Agent creates a scheduled task automatically (or user does it from Scheduler tab)
3. Task card appears with: frequency, next run time, execution count
4. When task executes, result appears as a new message in a dedicated "Automated" session
5. User gets a notification (if they've enabled browser notifications)
6. Tasks can be paused, edited, cancelled

Execution engine (relay-side):
- Background loop polls on-chain scheduler every 30 seconds
- When a task is due: run prompt through Venice AI, post result on-chain, update task metadata
- If recurring: reschedule automatically
- Results stored in a "task results" session for that task

### Extensions (Marketplace)
User flow:
1. Browse marketplace — search, filter by category
2. See install counts, audit status, author reputation
3. One-click install → Cadence transaction
4. Extension immediately available in agent's tool/hook repertoire
5. Publish your own: paste code, set metadata, publish on-chain
6. Community-driven — no approval needed, but audit badges add trust

For mainnet, the extension registry should be on a shared account (not per-user), so everyone browses the same marketplace.

---

## Phase 3: Retention & Power Features

### Dashboard (Home base)
- Agent health: connected, sessions active, tasks running, memory entries
- Network status: testnet/mainnet, block height, account address
- Activity feed: recent transactions with links
- Usage stats: messages this week, tokens used, tasks executed

### Settings
- Encryption: view fingerprint, rotate key, export key backup
- Wallet: link/unlink wallet, switch from custodial to self-custody
- AI Provider: switch between Venice, Anthropic, OpenAI, Ollama (local)
- Notifications: browser push for task completions, session summaries
- Export: download all data (encrypted or plaintext)
- Delete account: remove all on-chain resources

### Advanced
- API access: personal API key to interact with your agent programmatically
- Webhook support: trigger external actions when tasks complete
- Multi-agent: create additional agents with different personalities/contexts
- Sharing: share a read-only session link (decrypted on recipient's end)

---

## Implementation Roadmap

### Sprint 1: Foundation (Must-have for launch)
- [ ] **Wallet connect (FCL)** — Lilico + Dapper wallet support
- [ ] **On-chain state sync** — read all data from chain on page load (sessions, memories, tasks, extensions)
- [ ] **Persistent sessions** — chat history survives page refresh and relay restart
- [ ] **Task execution engine** — relay background loop that runs due tasks
- [ ] **Shared extension registry** — single on-chain registry all users browse
- [ ] **Landing page** — marketing page with auth CTAs
- [ ] **Default tab = Chat** — not Dashboard

### Sprint 2: Polish (Needed for good first impression)
- [ ] **Onboarding tour** — guided tooltips for first-time users
- [ ] **Welcome agent message** — pre-populated first chat
- [ ] **Transaction status indicators** — "Encrypting..." → "On-chain..." → "Done"
- [ ] **Flowscan links** — every on-chain action links to block explorer
- [ ] **Mobile responsive** — works on phone browsers
- [ ] **Error recovery** — graceful handling when chain is slow or relay drops
- [ ] **CORS for production domain** — flowclaw.app origin

### Sprint 3: Growth (Needed for retention)
- [ ] **Email/social auth** — custodial wallet onboarding
- [ ] **Auto-memory during chat** — agent stores facts automatically
- [ ] **Browser notifications** — task completion alerts
- [ ] **Settings page** — encryption, wallet, provider config
- [ ] **Activity feed** — recent transactions on dashboard
- [ ] **Session persistence across devices** — read from chain, not relay cache

### Sprint 4: Scale (Post-launch)
- [ ] **Multi-agent support**
- [ ] **Webhook integrations**
- [ ] **API access / developer mode**
- [ ] **Data export**
- [ ] **Hybrid custody graduation** (custodial → self-custody)
- [ ] **Extension audit system**
- [ ] **Gas sponsorship** (so users don't need FLOW for transactions)

---

## Current State vs Mainnet-Ready

| Feature | Current | Mainnet Ready |
|---------|---------|--------------|
| Chat | ✅ Works on testnet | Need persistent sessions from chain |
| Encryption | ✅ XChaCha20 working | Need client-side key management |
| Memory | ✅ Store on-chain | Need read-back from chain, auto-store |
| Scheduler | ✅ Register on-chain | Need execution engine |
| Extensions | ✅ Publish/install/uninstall | Need shared registry, not per-user |
| Auth | ❌ Hardcoded server key | Need FCL wallet connect |
| Persistence | ❌ In-memory relay cache | Need on-chain state sync |
| Landing page | ❌ None | Need marketing + auth page |
| Onboarding | ❌ None | Need guided first-run |
| Task execution | ❌ Tasks register but never run | Need relay execution loop |
| Mobile | ❌ Desktop only | Need responsive CSS |
| Error handling | ❌ Minimal | Need graceful degradation |
| Hosting | ❌ localhost only | Need deployed frontend + relay |

---

## Architecture for Mainnet

```
[User Browser]
    ↓
[Landing Page / Auth]  ←→  [FCL Wallet] or [Email Auth API]
    ↓
[React Frontend (Vite)]  — hosted on Vercel/Cloudflare
    ↓
[Relay API (FastAPI)]  — hosted on Railway/Fly.io
    ↓ ↗                ↘
[Flow Mainnet]     [Venice AI API]
(10 contracts)     (LLM inference)
```

Key change: Frontend talks to relay, relay talks to chain and AI.
For wallet connect: frontend handles FCL directly for reads (scripts).
For writes: relay builds + signs transactions (server wallet) OR
            frontend builds tx + user wallet signs via FCL.

Recommended: Hybrid approach
- Reads: frontend → FCL → Flow (no relay needed)
- Writes: frontend → relay → Flow (relay has the signing key)
- Auth: FCL wallet connect in frontend, relay verifies account ownership
