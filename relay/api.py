#!/usr/bin/env python3
"""
FlowClaw Relay API Server
==========================
FastAPI server bridging the React frontend to on-chain state and LLM providers.

Endpoints:
  GET  /status              — relay health, providers, encryption
  POST /chat/send           — send message, get LLM response (synchronous)
  POST /chat/create-session — create a new on-chain session
  GET  /sessions            — list sessions
  GET  /session/{id}/messages — fetch + decrypt session messages
  GET  /memory              — fetch memory entries
  GET  /tasks               — fetch scheduled tasks
  GET  /hooks               — fetch lifecycle hooks
  GET  /global-stats        — fetch global contract stats

Usage:
  python -m uvicorn api:app --host 0.0.0.0 --port 8000 --reload
"""

import os
import sys
import json
import time
import hashlib
import logging
import subprocess
import re
import asyncio
from pathlib import Path
from typing import Optional, List, Dict, Any
from datetime import datetime

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Import relay components (works both as package and standalone)
try:
    from relay.flowclaw_relay import (
        RelayConfig, EncryptionManager,
        AnthropicProvider, OpenAIProvider, OllamaProvider, VeniceProvider,
        LLMProvider, FlowCLI, ToolExecutor,
    )
    from relay.cognitive_memory import (
        CognitiveMemoryEngine, MemoryType, BondType,
    )
    from relay.tx_executor import AgentToolExecutor, ToolResult, SecurityContext
    from relay.account_manager import AccountManager, AccountInfo
    from relay.flow_client import FlowRESTClient
    from relay.gas_sponsor import GasSponsor
except ImportError:
    sys.path.insert(0, str(Path(__file__).parent))
    from flowclaw_relay import (
        RelayConfig, EncryptionManager,
        AnthropicProvider, OpenAIProvider, OllamaProvider, VeniceProvider,
        LLMProvider, FlowCLI, ToolExecutor,
    )
    from cognitive_memory import (
        CognitiveMemoryEngine, MemoryType, BondType,
    )
    from tx_executor import AgentToolExecutor, ToolResult, SecurityContext
    from account_manager import AccountManager, AccountInfo
    from flow_client import FlowRESTClient
    from gas_sponsor import GasSponsor

# Try to load .env from project root
try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / ".env")
except ImportError:
    pass

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)

# -----------------------------------------------------------------------
# App Setup
# -----------------------------------------------------------------------

app = FastAPI(title="FlowClaw Relay API", version="0.1.0")

# CORS — configurable via ALLOWED_ORIGINS env var
_default_origins = "http://localhost:5173,http://localhost:5174,http://localhost:5175,http://localhost:3000,http://127.0.0.1:5173,http://127.0.0.1:5174,https://flowclaw.app"
_allowed_origins = [o.strip() for o in os.getenv("ALLOWED_ORIGINS", _default_origins).split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "X-API-Key", "X-Request-ID"],
)

# -----------------------------------------------------------------------
# Global State
# -----------------------------------------------------------------------

config: Optional[RelayConfig] = None
flow_cli: Optional[FlowCLI] = None
flow_rest_client: Optional[FlowRESTClient] = None
encryption: Optional[EncryptionManager] = None
providers: Dict[str, LLMProvider] = {}
tool_executor: Optional[ToolExecutor] = None
agent_tool_executor: Optional[AgentToolExecutor] = None
account_manager: Optional[AccountManager] = None
gas_sponsor: Optional[GasSponsor] = None
start_time: float = 0
# Multi-agent state
agents_cache: Dict[int, Dict] = {}  # Empty — user creates agents after adding LLM provider
active_agent_id: Optional[int] = None  # No agent selected until user creates one
session_messages: Dict[int, List[Dict]] = {}  # Local cache for PoC
memory_cache: Dict[int, Dict] = {}  # Local cache for memory operations
tasks_cache: Dict[int, Dict] = {}  # Local cache for task operations
hooks_cache: Dict[int, Dict] = {}  # Local cache for hook operations
extensions_cache: Dict[int, Dict] = {}  # Local cache for extension operations
task_results: Dict[int, List[Dict]] = {}  # Task execution results cache
_next_memory_id: int = 1
_next_task_id: int = 1
cognitive_engine: CognitiveMemoryEngine = CognitiveMemoryEngine()
_next_hook_id: int = 1
_next_extension_id: int = 1
_next_execution_id: int = 1

# Per-user provider storage: address -> list of provider configs
# Each config: { name, type, api_key, base_url, is_default }
user_providers: Dict[str, List[Dict]] = {}
# Cached per-user LLM provider instances: address -> { provider_name -> LLMProvider }
_user_provider_cache: Dict[str, Dict[str, LLMProvider]] = {}


def _get_authed_address(request: Request) -> str:
    """Extract and verify the session token from Authorization header.
    Returns the user's Flow address or raises 401."""
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
    token = auth[7:]
    if not account_manager:
        raise HTTPException(status_code=503, detail="Account manager not initialized")
    data = account_manager.verify_token(token)
    if not data:
        raise HTTPException(status_code=401, detail="Invalid or expired session token")
    return data["address"]


def _get_user_provider(address: str, provider_name: str = None) -> Optional[LLMProvider]:
    """Get an LLM provider instance for a user. Creates on-demand from stored config.
    Falls back to global providers if user has none configured."""
    user_configs = user_providers.get(address, [])

    if not user_configs:
        # No user providers — fall back to global
        if provider_name and provider_name in providers:
            return providers[provider_name]
        if providers:
            return list(providers.values())[0]
        return None

    # Find the requested or default provider
    target_config = None
    if provider_name:
        target_config = next((c for c in user_configs if c["name"] == provider_name), None)
    if not target_config:
        target_config = next((c for c in user_configs if c.get("is_default")), None)
    if not target_config and user_configs:
        target_config = user_configs[0]
    if not target_config:
        return None

    # Check cache
    cache_key = f"{target_config['name']}_{target_config.get('api_key', '')[:8]}"
    if address in _user_provider_cache and cache_key in _user_provider_cache[address]:
        return _user_provider_cache[address][cache_key]

    # Instantiate provider
    ptype = target_config.get("type", "openai-compatible")
    api_key = target_config.get("api_key", "")
    base_url = target_config.get("base_url", "")

    instance = None
    if ptype == "anthropic":
        instance = AnthropicProvider(api_key)
    elif ptype == "ollama":
        instance = OllamaProvider(base_url or "http://localhost:11434")
    else:
        # openai-compatible (covers Venice, OpenAI, OpenRouter, Together, etc.)
        instance = VeniceProvider(api_key, base_url or "https://api.openai.com/v1")

    # Cache it
    if address not in _user_provider_cache:
        _user_provider_cache[address] = {}
    _user_provider_cache[address][cache_key] = instance

    return instance


# -----------------------------------------------------------------------
# Request/Response Models
# -----------------------------------------------------------------------

class SendMessageRequest(BaseModel):
    sessionId: int
    content: str
    provider: str = ""  # empty = use user's default provider
    model: str = ""     # empty = use provider's default model

class CreateSessionRequest(BaseModel):
    maxContextMessages: int = 4096

class SendMessageResponse(BaseModel):
    requestId: int
    sessionId: int
    response: str
    tokensUsed: int
    turns: int
    onChain: bool


class StoreMemoryRequest(BaseModel):
    key: str
    content: str
    tags: List[str] = []
    source: str = "api"


class ScheduleTaskRequest(BaseModel):
    name: str
    description: str
    category: int
    prompt: str
    maxTurns: int
    priority: int
    executeAt: float
    isRecurring: bool
    intervalSeconds: Optional[float] = None
    maxExecutions: Optional[int] = None


class PublishExtensionRequest(BaseModel):
    name: str
    description: str
    version: str
    category: int
    sourceHash: str
    tags: List[str] = []


class CreatePasskeyAccountRequest(BaseModel):
    publicKey: str
    credentialId: str
    displayName: str = "FlowClaw User"


class VerifyPasskeyRequest(BaseModel):
    credentialId: str
    clientDataJSON: Optional[str] = None
    authenticatorData: Optional[str] = None
    signature: Optional[str] = None


class InitiateLinkRequest(BaseModel):
    parentAddress: str


class AddKeyRequest(BaseModel):
    publicKey: str
    weight: int = 1000
    sigAlgo: str = "ECDSA_P256"
    hashAlgo: str = "SHA3_256"


class CreateAgentRequest(BaseModel):
    name: str
    description: str
    systemPrompt: str = ""
    provider: str = ""  # empty = use user's default
    model: str = ""     # empty = use provider's default
    autonomyLevel: int = 1
    maxActionsPerHour: int = 100
    maxCostPerDay: float = 5.0


class SpawnSubAgentRequest(BaseModel):
    name: str
    description: str
    ttlSeconds: Optional[float] = None
    inheritConfig: bool = True


class InstallExtensionRequest(BaseModel):
    config: Dict[str, str] = {}


class SaveProviderRequest(BaseModel):
    name: str  # user-facing name, e.g. "My Venice", "OpenRouter GPT-4"
    type: str = "openai-compatible"  # "openai-compatible", "anthropic", "ollama"
    api_key: str = ""
    base_url: str = ""
    is_default: bool = False


class SetDefaultProviderRequest(BaseModel):
    provider_name: str
    model: str = ""


class MemoryStoreResponse(BaseModel):
    memoryId: int
    success: bool


class TaskScheduleResponse(BaseModel):
    taskId: int
    success: bool


class ExtensionPublishResponse(BaseModel):
    extensionId: int
    success: bool


class OperationResponse(BaseModel):
    success: bool


# -----------------------------------------------------------------------
# Startup
# -----------------------------------------------------------------------

async def background_task_executor():
    """Background loop that executes scheduled tasks every 30 seconds."""
    global _next_execution_id

    logging.info("Background task executor started")
    while True:
        try:
            await asyncio.sleep(30)
            current_time = time.time()

            # Find due tasks
            due_tasks = []
            for task_id, task in tasks_cache.items():
                if task.get("isActive") and task.get("executeAt", 0) <= current_time:
                    due_tasks.append((task_id, task))

            if due_tasks:
                logging.info(f"Found {len(due_tasks)} due task(s) to execute")

            # Execute each due task
            for task_id, task in due_tasks:
                try:
                    logging.info(f"Executing task {task_id}: {task.get('name', 'unnamed')}")

                    # Get Venice AI provider
                    provider = providers.get("venice")
                    if not provider:
                        logging.warning(f"Task {task_id}: Venice AI provider not configured")
                        continue

                    # Build system prompt with tool definitions
                    raw_tool_defs = agent_tool_executor.get_tool_definitions() if agent_tool_executor else []
                    tool_defs = [td.get("function", td) for td in raw_tool_defs]
                    task_system = (
                        "Your name is FlowClaw. You are an autonomous AI agent running on the Flow blockchain. "
                        "You have real tool execution capabilities. "
                        "When you need data from the web or blockchain, USE the tools provided — "
                        "do NOT generate code or scripts. Call the appropriate tool function.\n\n"
                    )
                    if tool_defs:
                        task_system += "Available tools:\n"
                        for td in tool_defs:
                            fn = td.get("function", {})
                            task_system += f"- {fn.get('name')}: {fn.get('description', '')}\n"
                        task_system += "\nTo use a tool, output a tool call in your response.\n"

                    task_messages = [
                        {"role": "system", "content": task_system},
                        {"role": "user", "content": task.get("prompt", "")},
                    ]

                    # Multi-turn with tool execution (up to 5 turns)
                    ai_response = ""
                    tokens_used = 0
                    for turn in range(5):
                        result = provider.complete(
                            model="claude-sonnet-4-6",
                            messages=task_messages,
                            max_tokens=4096,
                            temperature=0.7,
                            tools=tool_defs if tool_defs else None,
                        )
                        tokens_used += result.get("tokens_used", 0)

                        # Handle tool calls
                        tool_calls = result.get("tool_calls", [])
                        if tool_calls and agent_tool_executor:
                            # Convert internal format to OpenAI format for message history
                            # Venice/OpenAI expects: {id, type, function: {name, arguments}}
                            openai_tool_calls = []
                            for tc in tool_calls:
                                openai_tool_calls.append({
                                    "id": tc.get("id", ""),
                                    "type": "function",
                                    "function": {
                                        "name": tc.get("name", ""),
                                        "arguments": json.dumps(tc.get("input", tc.get("arguments", {}))),
                                    },
                                })
                            task_messages.append({
                                "role": "assistant",
                                "content": result.get("content", "") or None,
                                "tool_calls": openai_tool_calls,
                            })
                            for tc in tool_calls:
                                logging.info(f"  Task {task_id} executing tool: {tc['name']}")
                                tool_result = agent_tool_executor.execute(
                                    tc["name"], tc.get("input", tc.get("arguments", {}))
                                )
                                task_messages.append({
                                    "role": "tool",
                                    "content": tool_result.to_message(),
                                    "tool_call_id": tc.get("id", ""),
                                })
                            continue

                        # Final response
                        ai_response = result.get("content", "")
                        break
                    else:
                        ai_response = result.get("content", "Max tool turns reached")

                    # Store result
                    execution_id = _next_execution_id
                    _next_execution_id += 1
                    executed_at = datetime.utcnow().isoformat() + "Z"

                    if task_id not in task_results:
                        task_results[task_id] = []

                    task_results[task_id].append({
                        "executionId": execution_id,
                        "result": ai_response,
                        "executedAt": executed_at,
                        "tokensUsed": tokens_used,
                    })

                    # Update task state
                    tasks_cache[task_id]["executionCount"] = task.get("executionCount", 0) + 1

                    logging.info(
                        f"Task {task_id} executed successfully "
                        f"(execution #{tasks_cache[task_id]['executionCount']}, "
                        f"tokens: {tokens_used})"
                    )

                    # Post result to the "Automated Tasks" session (session ID -1)
                    auto_session_id = -1
                    if auto_session_id not in session_messages:
                        session_messages[auto_session_id] = [{
                            "role": "system",
                            "content": "This session contains results from automated scheduled tasks."
                        }]
                    session_messages[auto_session_id].append({
                        "role": "assistant",
                        "content": f"**[Task: {task.get('name', 'unnamed')}]**\n\n{ai_response}",
                        "timestamp": executed_at,
                        "taskId": task_id,
                    })

                    # Handle recurring tasks
                    if task.get("isRecurring") and task.get("intervalSeconds"):
                        tasks_cache[task_id]["executeAt"] = current_time + task.get("intervalSeconds", 0)
                        logging.info(
                            f"Task {task_id} rescheduled for next execution "
                            f"at {tasks_cache[task_id]['executeAt']}"
                        )

                    # Check if max executions reached
                    if (task.get("maxExecutions") and
                        tasks_cache[task_id]["executionCount"] >= task.get("maxExecutions")):
                        tasks_cache[task_id]["isActive"] = False
                        logging.info(f"Task {task_id} completed (max executions reached)")

                except Exception as e:
                    logging.error(f"Error executing task {task_id}: {e}")
                    # Don't crash the loop, continue with next task

        except asyncio.CancelledError:
            logging.info("Background task executor cancelled")
            break
        except Exception as e:
            logging.error(f"Unexpected error in background task executor: {e}")
            # Continue the loop even on unexpected errors
            continue


async def background_dream_cycle():
    """
    Background dream cycle — runs every 6 hours.
    Consolidates memory: decay, bond formation, molecule detection,
    promotion of patterns, pruning of weak isolated memories.
    On Flow, we also trigger the on-chain dream cycle transaction.
    """
    while True:
        try:
            await asyncio.sleep(6 * 3600)  # Every 6 hours

            if not cognitive_engine.entries:
                continue

            logging.info("[Dream Cycle] Starting cognitive memory consolidation...")
            result = cognitive_engine.run_dream_cycle()

            # Best-effort on-chain dream cycle
            try:
                tx_args = json.dumps([
                    {"type": "UFix64", "value": "0.15000000"},  # decay threshold
                    {"type": "UInt64", "value": "3"},           # promotion threshold
                ])
                run_flow_tx("cadence/transactions/run_dream_cycle.cdc", tx_args)
                logging.info("[Dream Cycle] On-chain dream cycle committed")
            except Exception as e:
                logging.warning(f"[Dream Cycle] On-chain commit failed: {e}")

            # Best-effort commit new bonds on-chain
            for from_id, bond_list in cognitive_engine.bonds.items():
                for bond in bond_list:
                    try:
                        tx_args = json.dumps([
                            {"type": "UInt64", "value": str(bond.from_id)},
                            {"type": "UInt64", "value": str(bond.to_id)},
                            {"type": "UInt8", "value": str(bond.bond_type)},
                            {"type": "UFix64", "value": f"{bond.strength:.8f}"},
                        ])
                        run_flow_tx("cadence/transactions/create_memory_bond.cdc", tx_args)
                    except Exception:
                        pass  # Best-effort

            logging.info(
                f"[Dream Cycle] Complete: decayed={result.memories_decayed} "
                f"pruned={result.memories_pruned} bonds={result.bonds_created} "
                f"molecules={result.molecules_formed} promotions={result.promotions}"
            )

        except asyncio.CancelledError:
            logging.info("Dream cycle cancelled")
            break
        except Exception as e:
            logging.error(f"Dream cycle error: {e}")
            continue


@app.on_event("startup")
async def startup():
    global config, flow_cli, flow_rest_client, encryption, providers, tool_executor, agent_tool_executor, account_manager, gas_sponsor, start_time
    start_time = time.time()
    config = RelayConfig.from_env()

    logging.info(f"FlowClaw Relay API starting...")
    logging.info(f"  Network: {config.flow_network}")
    logging.info(f"  Account: {config.flow_account_address}")
    logging.info(f"  Project: {config.project_dir}")

    flow_cli = FlowCLI(config)
    encryption = EncryptionManager(config.encryption_key_path)
    tool_executor = ToolExecutor(config, flow_cli)

    # Initialize Flow REST client (replaces CLI subprocess calls)
    # Mainnet uses Key 1 (secp256k1 + SHA2_256), testnet/emulator use Key 0 (P256 + SHA3_256)
    if config.flow_network == "mainnet":
        _key_index = 1
        _sig_algo = "ECDSA_secp256k1"
        _hash_algo = "SHA2_256"
    else:
        _key_index = 0
        _sig_algo = "ECDSA_P256"
        _hash_algo = "SHA3_256"

    flow_rest_client = FlowRESTClient(
        network=config.flow_network,
        access_node=config.flow_access_node if config.flow_access_node != "http://localhost:8888" else None,
        signer_address=config.flow_account_address,
        signer_private_key_hex=config.flow_private_key,
        signer_key_index=_key_index,
        sig_algo=_sig_algo,
        hash_algo=_hash_algo,
    )
    # Load contract aliases from flow.json so REST API can resolve bare imports
    flow_json_path = os.path.join(config.project_dir, "flow.json")
    if os.path.exists(flow_json_path):
        flow_rest_client.load_aliases_from_flow_json(flow_json_path)
    logging.info(f"  Flow REST Client: {flow_rest_client}")

    # Async runner for sub-agent tasks
    async def _run_sub_agent_task(sub_id: int, name: str, task_description: str):
        """Execute a sub-agent's task in the background using the LLM + tools."""
        try:
            logging.info(f"Sub-agent {sub_id} ({name}) starting task: {task_description[:100]}")
            agents_cache[sub_id]["status"] = "running"

            provider = providers.get("venice")
            if not provider:
                agents_cache[sub_id]["status"] = "error"
                agents_cache[sub_id]["lastResult"] = "No LLM provider configured"
                return

            # Build system prompt with tools
            raw_tool_defs = agent_tool_executor.get_tool_definitions() if agent_tool_executor else []
            tool_defs = [td.get("function", td) for td in raw_tool_defs]
            # Remove spawn_sub_agent from sub-agent tools (no recursive spawning)
            tool_defs = [td for td in tool_defs if td.get("function", td).get("name") != "spawn_sub_agent"]

            sub_system = (
                f"Your name is {name}. You are a sub-agent of FlowClaw on the Flow blockchain. "
                f"You have been spawned to complete a specific task. "
                f"Complete the task thoroughly and provide a clear, well-organized result. "
                f"You have real tool execution capabilities — use them to get current data.\n\n"
                f"IMPORTANT — Cadence 1.0 syntax: If you write any Cadence scripts or code, "
                f"use `access(all)` instead of `pub`. For example: `access(all) fun main(): String {{}}`. "
                f"The `pub` keyword is no longer valid in Cadence 1.0.\n\n"
                f"YOUR TASK: {task_description}\n"
            )
            if tool_defs:
                sub_system += "\nAvailable tools:\n"
                for td in tool_defs:
                    fn = td.get("function", td)
                    sub_system += f"- {fn.get('name')}: {fn.get('description', '')}\n"

            sub_messages = [
                {"role": "system", "content": sub_system},
                {"role": "user", "content": task_description},
            ]

            # Multi-turn tool loop (up to 8 turns for thorough research)
            ai_response = ""
            tokens_used = 0
            for turn in range(8):
                try:
                    result = provider.complete(
                        model="claude-sonnet-4-6",
                        messages=sub_messages,
                        max_tokens=4096,
                        temperature=0.7,
                        tools=tool_defs if tool_defs else None,
                    )
                except Exception as e:
                    logging.error(f"Sub-agent {sub_id} LLM call failed: {e}")
                    agents_cache[sub_id]["status"] = "error"
                    agents_cache[sub_id]["lastResult"] = f"LLM error: {e}"
                    return

                tokens_used += result.get("tokens_used", 0)

                tool_calls = result.get("tool_calls", [])
                if tool_calls and agent_tool_executor:
                    openai_tool_calls = []
                    for tc in tool_calls:
                        openai_tool_calls.append({
                            "id": tc.get("id", ""),
                            "type": "function",
                            "function": {
                                "name": tc.get("name", ""),
                                "arguments": json.dumps(tc.get("input", tc.get("arguments", {}))),
                            },
                        })
                    sub_messages.append({
                        "role": "assistant",
                        "content": result.get("content", "") or None,
                        "tool_calls": openai_tool_calls,
                    })
                    for tc in tool_calls:
                        tool_name = tc.get("name", "")
                        tool_input = tc.get("input", tc.get("arguments", {}))
                        logging.info(f"  Sub-agent {sub_id} executing tool: {tool_name}")
                        tool_result = agent_tool_executor.execute(tool_name, tool_input)
                        sub_messages.append({
                            "role": "tool",
                            "content": tool_result.to_message(),
                            "tool_call_id": tc.get("id", ""),
                        })
                    continue

                ai_response = result.get("content", "")
                break
            else:
                ai_response = result.get("content", "Max tool turns reached")

            # Store result in agent cache
            agents_cache[sub_id]["status"] = "completed"
            agents_cache[sub_id]["lastResult"] = ai_response
            agents_cache[sub_id]["totalInferences"] = tokens_used
            agents_cache[sub_id]["completedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ")

            # Persist sub-agent result as on-chain cognitive memory
            # This makes results composable — any frontend can query them
            try:
                mem_key = f"sub-agent-result-{sub_id}-{name.lower().replace(' ', '-')}"
                mem_content = (
                    f"Sub-agent '{name}' completed task: {task_description[:200]}\n\n"
                    f"Result:\n{ai_response}"
                )
                mem_tags = ["sub-agent", "research", name.lower().replace(" ", "-")]
                memory_type, importance, emotional_weight = CognitiveMemoryEngine.classify_memory(
                    mem_key, mem_content, mem_tags
                )
                # Sub-agent results are always at least importance 8 (high)
                importance = max(importance, 8)
                cog_entry = cognitive_engine.store(
                    key=mem_key,
                    content=mem_content,
                    tags=mem_tags,
                    source="sub-agent",
                    memory_type=memory_type,
                    importance=importance,
                    emotional_weight=emotional_weight,
                )
                # Store in legacy cache too
                memory_cache[cog_entry.memory_id] = {
                    "key": mem_key,
                    "content": mem_content,
                    "tags": mem_tags,
                    "source": "sub-agent",
                    "encrypted": False,
                    "contentHash": cog_entry.content_hash,
                    "memoryType": memory_type,
                    "importance": importance,
                }
                # Commit to chain (high importance = always commits)
                try:
                    if not encryption or not encryption.is_configured:
                        logging.error(
                            f"Encryption not configured — skipping on-chain storage for sub-agent memory "
                            f"(refusing to store plaintext on-chain)"
                        )
                        raise RuntimeError("Encryption required for on-chain storage")
                    enc = encryption.encrypt(mem_content)
                    tags_array = [{"type": "String", "value": t} for t in mem_tags]
                    tx_args = json.dumps([
                        {"type": "String", "value": mem_key},
                        {"type": "String", "value": enc["ciphertext"]},
                        {"type": "String", "value": enc["nonce"]},
                        {"type": "String", "value": enc["plaintextHash"]},
                        {"type": "Array", "value": tags_array},
                        {"type": "String", "value": enc["keyFingerprint"]},
                        {"type": "UInt8", "value": str(enc["algorithm"])},
                        {"type": "UInt8", "value": str(memory_type)},
                        {"type": "UInt8", "value": str(importance)},
                        {"type": "UInt8", "value": str(emotional_weight)},
                    ])
                    run_flow_tx("cadence/transactions/store_cognitive_memory.cdc", tx_args)
                    cog_entry.on_chain = True
                    logging.info(f"Sub-agent {sub_id} result stored on-chain as cognitive memory: {mem_key}")
                except Exception as chain_err:
                    logging.warning(f"Sub-agent memory on-chain commit failed (stored locally): {chain_err}")
            except Exception as mem_err:
                logging.warning(f"Sub-agent memory storage failed: {mem_err}")

            # Post to automated session feed (session -1)
            auto_session_id = -1
            if auto_session_id not in session_messages:
                session_messages[auto_session_id] = [{
                    "role": "system",
                    "content": "This session contains results from automated tasks and sub-agents."
                }]
            session_messages[auto_session_id].append({
                "role": "assistant",
                "content": f"**[Sub-Agent: {name}]**\n\n{ai_response}",
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "agentId": sub_id,
            })

            logging.info(
                f"Sub-agent {sub_id} ({name}) completed task "
                f"(tokens: {tokens_used}, response length: {len(ai_response)})"
            )

        except Exception as e:
            logging.error(f"Sub-agent {sub_id} execution error: {e}")
            agents_cache[sub_id]["status"] = "error"
            agents_cache[sub_id]["lastResult"] = f"Execution error: {e}"

    # Spawn callback for LLM-initiated sub-agent creation
    def _spawn_sub_agent_callback(name: str, description: str, ttl_seconds: float = None):
        """Called by AgentToolExecutor when the LLM wants to spawn a sub-agent."""
        parent_id = active_agent_id or 1
        expires_at = time.time() + ttl_seconds if ttl_seconds else None
        sub_id = max(agents_cache.keys()) + 1 if agents_cache else 3
        agents_cache[sub_id] = {
            "name": name,
            "description": description,
            "isActive": True,
            "isSubAgent": True,
            "parentAgentId": parent_id,
            "expiresAt": expires_at,
            "totalSessions": 0,
            "totalInferences": 0,
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "systemPrompt": f"You are {name}, a sub-agent of FlowClaw. Your task: {description}",
            "status": "spawning",
            "lastResult": None,
        }
        logging.info(f"LLM spawned sub-agent: ID={sub_id}, parent={parent_id}, name={name}")

        # Kick off the sub-agent's task in the background
        try:
            loop = asyncio.get_event_loop()
            loop.create_task(_run_sub_agent_task(sub_id, name, description))
            logging.info(f"Sub-agent {sub_id} background task queued")
        except Exception as e:
            logging.warning(f"Could not queue sub-agent task: {e}")

        return {"agentId": sub_id, "parentId": parent_id, "success": True}

    # Initialize agent tool executor (real tool execution for LLM)
    agent_tool_executor = AgentToolExecutor(
        flow_cli_runner=run_flow_script,
        project_dir=config.project_dir,
        spawn_callback=_spawn_sub_agent_callback,
        flow_rest_client=flow_rest_client,
    )
    logging.info(f"  Agent Tool Executor: {len(agent_tool_executor.get_tool_definitions())} tools available")

    # Initialize account manager and gas sponsor (for passkey onboarding)
    sponsor_address = os.getenv("GAS_SPONSOR_ADDRESS", config.flow_account_address)
    sponsor_key_name = os.getenv("GAS_SPONSOR_KEY_NAME", "flowclawmainnet" if config.flow_network == "mainnet" else "flowclawtest")
    account_manager = AccountManager(
        sponsor_address=sponsor_address,
        sponsor_key_name=sponsor_key_name,
        flow_network=config.flow_network,
        project_dir=config.project_dir,
        flow_rest_client=flow_rest_client,
    )
    gas_sponsor = GasSponsor(
        sponsor_address=sponsor_address,
        sponsor_key_name=sponsor_key_name,
        flow_network=config.flow_network,
        project_dir=config.project_dir,
        daily_limit=int(os.getenv("GAS_SPONSOR_DAILY_LIMIT", "999999")),
        flow_rest_client=flow_rest_client,
    )
    logging.info(f"  Account Manager: passkey onboarding enabled")
    logging.info(f"  Gas Sponsor: {gas_sponsor.daily_limit} txs/day, sponsor={sponsor_address}")

    # Register providers
    if config.venice_api_key:
        providers["venice"] = VeniceProvider(config.venice_api_key, config.venice_base_url)
        logging.info(f"  Venice AI: configured")
    if config.anthropic_api_key:
        providers["anthropic"] = AnthropicProvider(config.anthropic_api_key)
        logging.info(f"  Anthropic: configured")
    if config.openai_api_key:
        providers["openai"] = OpenAIProvider(config.openai_api_key)
        logging.info(f"  OpenAI: configured")
    if config.ollama_base_url:
        providers["ollama"] = OllamaProvider(config.ollama_base_url)
        logging.info(f"  Ollama: configured")

    # Auto-generate encryption key if not present
    if not encryption.is_configured:
        logging.info("  No encryption key found — generating one automatically...")
        encryption.generate_key()
        logging.info(f"  Encryption key generated (fingerprint: {encryption.fingerprint[:16]}...)")

    # Auto-register encryption key fingerprint on-chain
    # This ensures the on-chain contract accepts payloads encrypted with this key
    if encryption.is_configured:
        try:
            logging.info(f"  Registering encryption key on-chain (fingerprint: {encryption.fingerprint[:16]}...)...")
            tx_args = json.dumps([
                {"type": "String", "value": encryption.fingerprint},
                {"type": "UInt8", "value": "0"},
                {"type": "String", "value": "relay-auto"},
            ])
            result = run_flow_tx("cadence/transactions/configure_encryption.cdc", tx_args)
            if result and ("sealed" in result.lower() or "success" in result.lower() or "SEALED" in result):
                logging.info(f"  Encryption key registered on-chain successfully")
            else:
                logging.warning(f"  Encryption key registration may have failed: {result}")
        except Exception as e:
            logging.warning(f"  Encryption key on-chain registration failed: {e}")
            logging.warning(f"  Chat will still work but on-chain storage may fail")

    logging.info(f"  Encryption: {'ENABLED' if encryption.is_configured else 'DISABLED'}")
    logging.info(f"  Providers: {list(providers.keys())}")

    # Start background task executor
    asyncio.create_task(background_task_executor())
    logging.info(f"  Background task executor: started")

    # Start dream cycle
    asyncio.create_task(background_dream_cycle())
    logging.info(f"  Dream cycle: started (every 6 hours)")

    # Sync on-chain state to populate caches
    logging.info(f"  Syncing on-chain state...")
    await sync_all_state()

    # Migrate existing memories into cognitive engine
    if memory_cache:
        logging.info(f"  Ingesting {len(memory_cache)} existing memories into cognitive engine...")
        for mid, entry in memory_cache.items():
            cognitive_engine.ingest_flat_memory(
                memory_id=mid,
                key=entry.get("key", ""),
                content=entry.get("content", ""),
                tags=entry.get("tags", []),
                source=entry.get("source", "sync"),
            )
        logging.info(f"  Cognitive engine: {len(cognitive_engine.entries)} memories, {cognitive_engine.get_stats()['totalBonds']} bonds")

    logging.info(f"FlowClaw Relay API ready on http://0.0.0.0:8000")


# -----------------------------------------------------------------------
# Helper: Run Flow Blockchain Operations (REST API — no CLI dependency)
# -----------------------------------------------------------------------

def run_flow_script(script_path: str, args_json: str = None) -> Optional[str]:
    """
    Execute a Cadence script and return raw output.

    Uses Flow REST API via FlowRESTClient (preferred) with CLI fallback.
    """
    if flow_rest_client and flow_rest_client.signer_address:
        try:
            cadence_code = Path(config.project_dir, script_path).read_text()
            arguments = json.loads(args_json) if args_json else []
            result = flow_rest_client.execute_script(cadence_code, arguments)
            # Return as string for backward compatibility with callers
            if result is not None:
                return f"Result: {json.dumps(result) if not isinstance(result, str) else result}"
            return None
        except Exception as e:
            logging.warning(f"REST script execution failed, falling back to CLI: {e}")

    # Fallback to CLI (for emulator or if REST client not configured)
    cmd = [
        "flow", "scripts", "execute", script_path,
        "--network", config.flow_network,
    ]
    if args_json:
        cmd.extend(["--args-json", args_json])

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True,
            cwd=config.project_dir, timeout=30,
        )
        if result.returncode == 0:
            return result.stdout.strip()
        else:
            logging.warning(f"Script failed: {result.stderr[:200]}")
            return None
    except Exception as e:
        logging.error(f"Script error: {e}")
        return None


def run_flow_tx(tx_path: str, args_json: str = None) -> Optional[str]:
    """
    Send a Cadence transaction.

    NOTE: Currently all transactions run on the sponsor account.
    User-specific transactions (sessions, messages, agents) need multi-party signing
    (user passkey signs as authorizer, sponsor signs as payer) which is not yet implemented.
    For now, on-chain transactions are best-effort — failures are logged but don't break
    the off-chain functionality.

    Returns a string containing "sealed" on success for backward compat.
    """
    if flow_rest_client and flow_rest_client.signer_private_key_hex:
        try:
            cadence_code = Path(config.project_dir, tx_path).read_text()
            arguments = json.loads(args_json) if args_json else []
            result = flow_rest_client.send_transaction(cadence_code, arguments)

            # Build backward-compatible output string
            status = result.get("status", "UNKNOWN")
            tx_id = result.get("txId", "")
            error = result.get("error", "")

            output_parts = [f"Transaction ID: {tx_id}", f"Status: {status}"]
            if result.get("sealed"):
                output_parts.append("Status: SEALED")
            if error:
                output_parts.append(f"Error: {error}")
            if result.get("events"):
                for evt in result["events"][:5]:  # First 5 events
                    evt_type = evt.get("type", "unknown")
                    output_parts.append(f"Event: {evt_type}")
                    # Include event payload fields for requestId extraction
                    payload = evt.get("payload")
                    if payload and isinstance(payload, dict):
                        # JSON-CDC event: extract fields
                        val = payload.get("value", {})
                        fields = val.get("fields", []) if isinstance(val, dict) else []
                        for field in fields:
                            fname = field.get("name", "")
                            fval = field.get("value", {})
                            fval_decoded = fval.get("value", "") if isinstance(fval, dict) else fval
                            output_parts.append(f"  {fname} ({fval.get('type', '')}): {fval_decoded}")

            combined = "\n".join(output_parts)
            logging.info(f"Flow TX ({tx_path}): {combined[:300]}")
            return combined

        except Exception as e:
            logging.warning(f"REST transaction failed, falling back to CLI: {e}")

    # Fallback to CLI (for emulator or if REST client not configured)
    signer_map = {"testnet": "flowclawtest", "mainnet": "flowclawmainnet"}
    signer = signer_map.get(config.flow_network, "emulator-account")
    cmd = [
        "flow", "transactions", "send", tx_path,
        "--signer", signer,
        "--network", config.flow_network,
    ]
    if args_json:
        cmd.extend(["--args-json", args_json])

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True,
            cwd=config.project_dir, timeout=60,
        )
        combined = (result.stdout + "\n" + result.stderr).strip()
        logging.info(f"Flow TX output ({tx_path}): {combined[:300]}")
        if result.returncode == 0:
            return combined
        else:
            if "sealed" in combined.lower():
                return combined
            logging.warning(f"Transaction failed: {combined[:300]}")
            return None
    except Exception as e:
        logging.error(f"Transaction error: {e}")
        return None


def parse_cadence_result(output: str) -> Any:
    """Extract the Result value from Flow CLI/REST output."""
    if not output:
        return None
    # REST API format: "Result: <value>"
    for line in output.split("\n"):
        if line.strip().startswith("Result:"):
            val = line.split("Result:", 1)[1].strip()
            try:
                return json.loads(val)
            except (json.JSONDecodeError, ValueError):
                return val
    return output


# -----------------------------------------------------------------------
# On-Chain State Sync
# -----------------------------------------------------------------------

async def sync_all_state():
    """Sync all on-chain state to populate caches at startup."""
    try:
        await sync_sessions()
        await sync_memories()
        await sync_tasks()
        await sync_extensions()
    except Exception as e:
        logging.error(f"Error syncing on-chain state: {e}")


async def sync_sessions():
    """Sync sessions from on-chain state and populate session_messages cache."""
    try:
        addr_arg = json.dumps([{"type": "Address", "value": config.flow_account_address}])
        result = run_flow_script("cadence/scripts/get_all_sessions.cdc", addr_arg)
        if not result:
            logging.warning("No session data from on-chain")
            return

        parsed = parse_cadence_result(result)
        logging.info(f"Synced sessions from on-chain: {str(parsed)[:200]}")

        # Populate session_messages cache so GET /sessions returns real data
        if isinstance(parsed, dict):
            sessions_list = parsed.get("sessions", [])
            for s in sessions_list:
                sid = s.get("sessionId", s.get("session_id"))
                if sid is not None:
                    sid = int(sid)
                    if sid not in session_messages:
                        session_messages[sid] = []
                        logging.info(f"Registered on-chain session {sid} in local cache")
        elif isinstance(parsed, str):
            # Try to extract session IDs from string representation
            import re as _re
            for m in _re.finditer(r'sessionId:\s*(\d+)', str(parsed)):
                sid = int(m.group(1))
                if sid not in session_messages:
                    session_messages[sid] = []
                    logging.info(f"Registered on-chain session {sid} in local cache")
    except Exception as e:
        logging.error(f"Error syncing sessions: {e}")


async def sync_memories():
    """Sync memories from on-chain state."""
    try:
        addr_arg = json.dumps([{"type": "Address", "value": config.flow_account_address}])
        result = run_flow_script("cadence/scripts/get_all_memories.cdc", addr_arg)
        if not result:
            logging.warning("No memory data from on-chain")
            return

        parsed = parse_cadence_result(result)
        logging.info(f"Synced memories from on-chain: {str(parsed)[:200]}")
    except Exception as e:
        logging.error(f"Error syncing memories: {e}")


async def sync_tasks():
    """Sync tasks from on-chain state."""
    try:
        addr_arg = json.dumps([{"type": "Address", "value": config.flow_account_address}])
        result = run_flow_script("cadence/scripts/get_all_tasks.cdc", addr_arg)
        if not result:
            logging.warning("No task data from on-chain")
            return

        parsed = parse_cadence_result(result)
        logging.info(f"Synced tasks from on-chain: {str(parsed)[:200]}")
    except Exception as e:
        logging.error(f"Error syncing tasks: {e}")


async def sync_extensions():
    """Sync extensions from on-chain state."""
    try:
        addr_arg = json.dumps([{"type": "Address", "value": config.flow_account_address}])
        result = run_flow_script("cadence/scripts/get_all_extensions.cdc", addr_arg)
        if not result:
            logging.warning("No extension data from on-chain")
            return

        parsed = parse_cadence_result(result)
        logging.info(f"Synced extensions from on-chain: {str(parsed)[:200]}")
    except Exception as e:
        logging.error(f"Error syncing extensions: {e}")


# -----------------------------------------------------------------------
# Endpoints
# -----------------------------------------------------------------------

@app.get("/status")
async def get_status():
    """Relay health check."""
    emulator_ok = False
    try:
        import requests as req
        resp = req.get(f"{config.flow_access_node}/v1/blocks?height=sealed", timeout=3)
        emulator_ok = resp.status_code == 200
    except Exception:
        pass

    return {
        "connected": emulator_ok,
        "network": config.flow_network,
        "encryptionEnabled": encryption.is_configured if encryption else False,
        "availableProviders": list(providers.keys()),
        "uptime": round(time.time() - start_time, 1),
        "byokEnabled": True,
    }


@app.get("/global-stats")
async def get_global_stats():
    """Fetch global FlowClaw stats from on-chain."""
    result = run_flow_script("cadence/scripts/get_global_stats.cdc")
    parsed = parse_cadence_result(result)

    # Parse the Cadence struct output
    if isinstance(parsed, str) and "GlobalStats" in parsed:
        # Extract fields from Cadence struct string
        stats = {}
        for field in ["version", "totalAgents", "totalSessions",
                       "totalInferenceRequests", "totalAccounts", "totalMessages"]:
            match = re.search(rf'{field}:\s*"?([^",)]+)"?', parsed)
            if match:
                val = match.group(1)
                stats[field] = int(val) if val.isdigit() else val
        return stats

    return {
        "version": "0.1.0-alpha",
        "totalAgents": 0, "totalSessions": 0,
        "totalInferenceRequests": 0, "totalAccounts": 0, "totalMessages": 0,
    }


@app.get("/sync/sessions")
async def sync_sessions_endpoint():
    """Sync and return sessions from on-chain state."""
    try:
        result = run_flow_script("cadence/scripts/get_all_sessions.cdc")
        parsed = parse_cadence_result(result)

        if parsed:
            logging.info(f"Synced sessions from on-chain")
            return {"success": True, "data": parsed}
        else:
            logging.warning("No session data from on-chain")
            return {"success": False, "data": []}

    except Exception as e:
        logging.error(f"Error syncing sessions: {e}")
        raise HTTPException(status_code=500, detail=f"Error syncing sessions: {str(e)}")


@app.get("/sync/memories")
async def sync_memories_endpoint():
    """Sync and return memories from on-chain state."""
    try:
        result = run_flow_script("cadence/scripts/get_all_memories.cdc")
        parsed = parse_cadence_result(result)

        if parsed:
            logging.info(f"Synced memories from on-chain")
            return {"success": True, "data": parsed}
        else:
            logging.warning("No memory data from on-chain")
            return {"success": False, "data": []}

    except Exception as e:
        logging.error(f"Error syncing memories: {e}")
        raise HTTPException(status_code=500, detail=f"Error syncing memories: {str(e)}")


@app.get("/sync/tasks")
async def sync_tasks_endpoint():
    """Sync and return tasks from on-chain state."""
    try:
        result = run_flow_script("cadence/scripts/get_all_tasks.cdc")
        parsed = parse_cadence_result(result)

        if parsed:
            logging.info(f"Synced tasks from on-chain")
            return {"success": True, "data": parsed}
        else:
            logging.warning("No task data from on-chain")
            return {"success": False, "data": []}

    except Exception as e:
        logging.error(f"Error syncing tasks: {e}")
        raise HTTPException(status_code=500, detail=f"Error syncing tasks: {str(e)}")


@app.get("/sync/extensions")
async def sync_extensions_endpoint():
    """Sync and return extensions from on-chain state."""
    try:
        result = run_flow_script("cadence/scripts/get_all_extensions.cdc")
        parsed = parse_cadence_result(result)

        if parsed:
            logging.info(f"Synced extensions from on-chain")
            return {"success": True, "data": parsed}
        else:
            logging.warning("No extension data from on-chain")
            return {"success": False, "data": []}

    except Exception as e:
        logging.error(f"Error syncing extensions: {e}")
        raise HTTPException(status_code=500, detail=f"Error syncing extensions: {str(e)}")


# -----------------------------------------------------------------------
# Content Encryption (for multi-party signing)
# -----------------------------------------------------------------------


class EncryptContentRequest(BaseModel):
    content: str  # Plaintext content to encrypt


@app.post("/encrypt")
async def encrypt_content(req: EncryptContentRequest, request: Request):
    """Encrypt content using the relay's encryption key.

    Used by the frontend before multi-party signed on-chain transactions.
    The frontend sends plaintext here, gets back encrypted payload fields,
    then uses those fields in the Cadence transaction arguments.

    This ensures messages are ALWAYS encrypted before touching the chain,
    even though the user (not the relay) signs the transaction.
    """
    _get_authed_address(request)  # Auth required

    if not encryption or not encryption.is_configured:
        raise HTTPException(
            status_code=503,
            detail="Encryption not configured on relay. On-chain storage requires encryption."
        )

    try:
        enc = encryption.encrypt(req.content)
        return {
            "ciphertext": enc["ciphertext"],
            "nonce": enc["nonce"],
            "plaintextHash": enc["plaintextHash"],
            "keyFingerprint": enc["keyFingerprint"],
            "algorithm": enc["algorithm"],
            "plaintextLength": enc["plaintextLength"],
        }
    except Exception as e:
        logging.error(f"Encryption failed: {e}")
        raise HTTPException(status_code=500, detail=f"Encryption failed: {str(e)}")


# -----------------------------------------------------------------------
# Multi-Party Transaction Signing
# -----------------------------------------------------------------------

# In-memory cache for pending unsigned transactions (keyed by build ID)
import uuid as _uuid
_pending_tx_builds: Dict[str, Dict] = {}


class BuildTransactionRequest(BaseModel):
    transactionPath: str  # Path to .cdc file relative to project dir
    arguments: List[Dict] = []  # Cadence arguments [{"type": "...", "value": "..."}]


class SubmitTransactionRequest(BaseModel):
    txBuildId: str
    userSignature: str  # Base64-encoded raw signature (r||s, 64 bytes)


@app.post("/transaction/build")
async def build_transaction(req: BuildTransactionRequest, request: Request):
    """Build an unsigned transaction for multi-party signing.

    The authenticated user becomes proposer + authorizer.
    The sponsor (relay) becomes the payer.
    Returns a payloadHex that the user must sign client-side.
    """
    address = _get_authed_address(request)

    if not flow_rest_client:
        raise HTTPException(status_code=503, detail="Flow REST client not initialized")

    try:
        # Read the Cadence transaction file
        tx_file = Path(config.project_dir) / req.transactionPath
        if not tx_file.exists():
            raise HTTPException(status_code=404, detail=f"Transaction file not found: {req.transactionPath}")

        cadence_code = tx_file.read_text()

        # Build the unsigned transaction
        build_result = flow_rest_client.build_unsigned_transaction(
            cadence_code=cadence_code,
            arguments=req.arguments if req.arguments else None,
            user_address=address,
            user_key_index=0,  # User accounts created with key index 0
        )

        # Store in cache with a unique build ID (expires after 5 minutes)
        build_id = str(_uuid.uuid4())
        _pending_tx_builds[build_id] = {
            "build_result": build_result,
            "user_address": address,
            "created_at": time.time(),
        }

        # Clean up old builds (older than 5 minutes)
        cutoff = time.time() - 300
        expired = [k for k, v in _pending_tx_builds.items() if v["created_at"] < cutoff]
        for k in expired:
            del _pending_tx_builds[k]

        logging.info(f"Transaction built for {address}: {req.transactionPath} (build_id={build_id[:8]}...)")

        return {
            "txBuildId": build_id,
            "payloadHex": build_result["payloadHex"],
            "referenceBlockId": build_result["referenceBlockId"],
            "sequenceNumber": build_result["sequenceNumber"],
        }

    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Transaction build failed: {e}")
        raise HTTPException(status_code=500, detail=f"Transaction build failed: {str(e)}")


@app.post("/transaction/submit")
async def submit_transaction(req: SubmitTransactionRequest, request: Request):
    """Submit a signed multi-party transaction.

    The user provides their payload signature. The relay adds the payer (sponsor)
    envelope signature and submits to Flow.
    """
    address = _get_authed_address(request)

    if not flow_rest_client:
        raise HTTPException(status_code=503, detail="Flow REST client not initialized")

    # Look up the pending build
    pending = _pending_tx_builds.get(req.txBuildId)
    if not pending:
        raise HTTPException(status_code=404, detail="Transaction build not found or expired")

    # Verify the build belongs to this user
    if pending["user_address"] != address:
        raise HTTPException(status_code=403, detail="Transaction build belongs to a different user")

    # Check expiry (5 minute window)
    if time.time() - pending["created_at"] > 300:
        del _pending_tx_builds[req.txBuildId]
        raise HTTPException(status_code=410, detail="Transaction build expired")

    try:
        # Complete the multi-party transaction
        result = flow_rest_client.complete_multi_party_transaction(
            build_result=pending["build_result"],
            user_signature_b64=req.userSignature,
        )

        # Clean up the pending build
        del _pending_tx_builds[req.txBuildId]

        logging.info(
            f"Multi-party TX completed: {result.get('txId', 'unknown')} "
            f"(user={address}, status={result.get('status', 'unknown')})"
        )

        return {
            "txId": result.get("txId", ""),
            "status": result.get("status", "UNKNOWN"),
            "sealed": result.get("sealed", False),
            "events": result.get("events", []),
            "error": result.get("error", ""),
        }

    except Exception as e:
        logging.error(f"Transaction submit failed: {e}")
        raise HTTPException(status_code=500, detail=f"Transaction submit failed: {str(e)}")


@app.post("/chat/create-session")
async def create_session(req: CreateSessionRequest):
    """Create a new chat session (off-chain for now).

    On-chain sessions require multi-party signing (user passkey + sponsor payer)
    which is not yet implemented. Sessions are managed off-chain in the relay cache.
    """
    session_id = len(session_messages)
    session_messages[session_id] = []
    logging.info(f"Session created (off-chain): ID={session_id}")
    return {"sessionId": session_id, "success": True, "txResult": "off-chain"}


def _build_memory_context(user_message: str) -> str:
    """
    Build memory context using the Cognitive Memory Engine.

    Uses molecular retrieval (O(k)) instead of flat keyword scan (O(n)):
    1. Finds seed memories matching the query
    2. Traverses molecular bonds to get coherent clusters
    3. Includes self-model (identity) and relevant procedures
    4. Weights by importance, strength, and emotional weight

    Falls back to legacy keyword matching if cognitive engine is empty.
    """

    # Use cognitive engine if it has memories
    if cognitive_engine.entries:
        return cognitive_engine.build_context(user_message)

    # Legacy fallback for backward compatibility
    if not memory_cache:
        return ""

    words = set(user_message.lower().split())
    relevant = []

    for mid, entry in memory_cache.items():
        key_words = set(entry.get("key", "").lower().replace("-", " ").replace("_", " ").split())
        content_words = set(entry.get("content", "").lower().split())
        tag_words = set(t.lower() for t in entry.get("tags", []))
        overlap = len(words & (key_words | content_words | tag_words))
        if overlap > 0:
            relevant.append((overlap, entry))

    if len(memory_cache) <= 10:
        for mid, entry in memory_cache.items():
            if not any(e[1] is entry for e in relevant):
                relevant.append((0, entry))

    if not relevant:
        return ""

    relevant.sort(key=lambda x: -x[0])
    top = [e for _, e in relevant[:10]]

    context = "## Your Memories\n"
    for entry in top:
        key = entry.get("key", "unknown")
        content = entry.get("content", "")
        tags = ", ".join(entry.get("tags", []))
        context += f"- **{key}**: {content}"
        if tags:
            context += f" (tags: {tags})"
        context += "\n"
    context += "\nUse these memories to personalize your responses when relevant.\n"
    return context


def _clean_markdown(text: str) -> str:
    """Strip markdown formatting so chat output renders cleanly as plain text."""
    # Bold: **text** or __text__
    text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
    text = re.sub(r'__(.+?)__', r'\1', text)
    # Italic: *text* or _text_ (but not inside words like don_t)
    text = re.sub(r'(?<!\w)\*(.+?)\*(?!\w)', r'\1', text)
    text = re.sub(r'(?<!\w)_(.+?)_(?!\w)', r'\1', text)
    # Inline code: `text`
    text = re.sub(r'`(.+?)`', r'\1', text)
    # Headers: ### text
    text = re.sub(r'^#{1,6}\s+', '', text, flags=re.MULTILINE)
    # Bullet dashes at start of line stay (those read fine as plain text)
    return text.strip()


def _parse_and_store_memories(response_content: str) -> str:
    """
    Parse STORE_MEMORY directives from agent response and store them
    in the Cognitive Memory Engine + on-chain.

    Auto-classifies memories into cognitive types:
    - Episodic: events, conversations, experiences
    - Semantic: facts, knowledge, insights
    - Procedural: skills, workflows, how-to sequences
    - Self-Model: identity, preferences, personality

    Uses importance scoring for selective on-chain commitment.
    """
    global _next_memory_id

    # Find all [STORE_MEMORY ...]: ... patterns
    pattern = r'\[STORE_MEMORY\s+key="([^"]+)"(?:\s+tags="([^"]*)")?\]:\s*(.+?)(?:\n|$)'
    matches = re.findall(pattern, response_content)

    for key, tags_str, content in matches:
        tags = [t.strip() for t in tags_str.split(",") if t.strip()] if tags_str else []

        # Cognitive classification
        memory_type, importance, emotional_weight = CognitiveMemoryEngine.classify_memory(
            key, content.strip(), tags
        )

        logging.info(
            f"Agent auto-storing memory: key={key}, "
            f"type={MemoryType(memory_type).name}, importance={importance}, "
            f"content={content[:50]}..."
        )

        # Store in cognitive engine (creates bonds automatically)
        cog_entry = cognitive_engine.store(
            key=key,
            content=content.strip(),
            tags=tags,
            source="agent-auto",
            memory_type=memory_type,
            importance=importance,
            emotional_weight=emotional_weight,
        )

        # Also store in legacy cache for backward compat
        memory_id = cog_entry.memory_id
        memory_cache[memory_id] = {
            "key": key,
            "content": content.strip(),
            "tags": tags,
            "source": "agent-auto",
            "encrypted": encryption.is_configured if encryption else False,
            "contentHash": cog_entry.content_hash,
            "memoryType": memory_type,
            "importance": importance,
        }

        # Selective on-chain commitment: only commit important memories
        should_commit = importance >= 7 or memory_type == MemoryType.SELF_MODEL
        if should_commit:
            try:
                if not encryption or not encryption.is_configured:
                    logging.error(
                        f"Encryption not configured — skipping on-chain storage for memory '{key}' "
                        f"(refusing to store plaintext on-chain)"
                    )
                    continue
                enc = encryption.encrypt(content.strip())
                tags_array = [{"type": "String", "value": t} for t in tags]

                # Use cognitive store transaction (stores in both AgentMemory + CognitiveMemory)
                tx_args = json.dumps([
                    {"type": "String", "value": key},
                    {"type": "String", "value": enc["ciphertext"]},
                    {"type": "String", "value": enc["nonce"]},
                    {"type": "String", "value": enc["plaintextHash"]},
                    {"type": "String", "value": enc.get("keyFingerprint", "")},
                    {"type": "UInt8", "value": str(enc.get("algorithm", 0))},
                    {"type": "UInt64", "value": str(enc.get("plaintextLength", len(content)))},
                    {"type": "Array", "value": tags_array},
                    {"type": "String", "value": "agent-auto"},
                    {"type": "UInt8", "value": str(memory_type)},
                    {"type": "UInt8", "value": str(importance)},
                    {"type": "UInt8", "value": str(emotional_weight)},
                ])
                run_flow_tx("cadence/transactions/store_cognitive_memory.cdc", tx_args)
                cog_entry.on_chain = True
                logging.info(
                    f"Memory '{key}' committed on-chain "
                    f"(type={MemoryType(memory_type).name}, importance={importance})"
                )
            except Exception as e:
                logging.warning(f"Failed to store memory on-chain: {e}")
                # Fall back to legacy transaction
                try:
                    tx_args = json.dumps([
                        {"type": "String", "value": key},
                        {"type": "String", "value": enc["ciphertext"]},
                        {"type": "String", "value": enc["nonce"]},
                        {"type": "String", "value": enc["plaintextHash"]},
                        {"type": "String", "value": enc.get("keyFingerprint", "")},
                        {"type": "UInt8", "value": str(enc.get("algorithm", 0))},
                        {"type": "UInt64", "value": str(enc.get("plaintextLength", len(content)))},
                        {"type": "Array", "value": tags_array},
                        {"type": "String", "value": "agent-auto"},
                    ])
                    run_flow_tx("cadence/transactions/store_memory.cdc", tx_args)
                    cog_entry.on_chain = True
                    logging.info(f"Memory '{key}' stored on-chain (legacy fallback)")
                except Exception as e2:
                    logging.warning(f"Legacy fallback also failed: {e2}")
        else:
            logging.info(
                f"Memory '{key}' kept local-only "
                f"(importance={importance} < threshold {7})"
            )

    # Strip the STORE_MEMORY directives from the response shown to user
    clean_response = re.sub(pattern, '', response_content).strip()
    return clean_response if clean_response else response_content


@app.post("/chat/send")
async def send_message(req: SendMessageRequest, request: Request):
    """
    Send a message and get an LLM response (synchronous).

    Flow:
    1. Send message on-chain (transaction)
    2. Call LLM provider (user's BYOK or relay fallback)
    3. Post response on-chain (transaction)
    4. Return plaintext response to frontend
    """
    # Try to get user-specific provider first (BYOK)
    provider = None
    try:
        address = _get_authed_address(request)
        provider = _get_user_provider(address, req.provider)
    except HTTPException:
        pass  # No auth token — fall back to global providers

    # Fall back to global providers
    if not provider:
        provider = providers.get(req.provider)
    if not provider:
        available = list(providers.keys())
        if available:
            provider = providers[available[0]]
            req.provider = available[0]
            logging.info(f"Provider '{req.provider}' not found, using '{available[0]}'")
        else:
            raise HTTPException(
                status_code=503,
                detail="No LLM provider configured. Go to Settings and add your API key for Venice, OpenAI, Anthropic, or another provider."
            )

    # Auto-resolve session ID: use off-chain session management
    # On-chain sessions require multi-party signing (not yet implemented)
    if req.sessionId not in session_messages:
        # Create a new off-chain session for this ID
        session_messages[req.sessionId] = []
        logging.info(f"Auto-created off-chain session {req.sessionId}")

    logging.info(f"Session ID for this message: {req.sessionId}")

    # Build message history for this session
    if req.sessionId not in session_messages:
        # Build system prompt with memory context and real tool definitions
        tool_defs = agent_tool_executor.get_tool_definitions() if agent_tool_executor else []
        system_content = (
            "Your name is FlowClaw. You are an autonomous AI agent running on the Flow blockchain. "
            "Your conversations are stored on-chain with end-to-end encryption. "
            "You have REAL tool execution capabilities — when you need data from the web "
            "or blockchain, USE the tools provided. Do NOT generate code or scripts to "
            "accomplish tasks that your tools can handle directly. "
            "You are private to your owner's account. "
            "Be helpful, concise, and mention on-chain features when relevant.\n\n"
            "IMPORTANT — Cadence 1.0 syntax: If you write any Cadence scripts or code, "
            "use `access(all)` instead of `pub`. For example: `access(all) fun main(): String {}`. "
            "The `pub` keyword is no longer valid in Cadence 1.0.\n\n"
        )

        # Add tool descriptions to system prompt
        if tool_defs:
            system_content += "## Available Tools\n"
            for td in tool_defs:
                fn = td.get("function", {})
                system_content += f"- **{fn.get('name')}**: {fn.get('description', '')}\n"
            system_content += (
                "\nUse these tools by making tool calls when you need real data. "
                "For example, use `get_flow_price` to check FLOW price, "
                "`web_fetch` to fetch data from APIs, or `query_balance` to check balances.\n\n"
            )

        # Inject relevant memories into system prompt
        memory_context = _build_memory_context(req.content)
        if memory_context:
            system_content += memory_context

        # Add auto-store instruction with cognitive memory guidance
        system_content += (
            "\n\nIMPORTANT — COGNITIVE MEMORY SYSTEM:\n"
            "You have a cognitive memory system with four types:\n"
            "- Episodic: events, conversations, things that happened (\"User asked about X on date Y\")\n"
            "- Semantic: facts and knowledge (\"User's company is called X\", \"X means Y\")\n"
            "- Procedural: skills and how-to (\"To deploy on Flow: step 1, step 2...\")\n"
            "- Self-Model: identity and preferences (\"User prefers concise responses\")\n\n"
            "When you learn something important, end your response with:\n"
            "[STORE_MEMORY key=\"descriptive-key\" tags=\"tag1,tag2\"]: The content to remember\n\n"
            "Tag guidelines — use tags that categorize the memory:\n"
            "- For preferences: tags=\"preference,personal\"\n"
            "- For facts: tags=\"fact,knowledge,topic-name\"\n"
            "- For events: tags=\"event,context-name\"\n"
            "- For skills: tags=\"procedure,skill,topic-name\"\n\n"
            "This will be automatically classified, importance-scored, and stored in encrypted on-chain memory. "
            "Important memories (preferences, decisions, facts) get committed to the blockchain. "
            "Routine observations stay local. Memories form molecular bonds — related memories "
            "cluster together for smarter retrieval. Only store genuinely useful information."
        )

        session_messages[req.sessionId] = [{"role": "system", "content": system_content}]
    else:
        # Update system prompt with fresh memory context for ongoing sessions
        memory_context = _build_memory_context(req.content)
        if memory_context and session_messages[req.sessionId]:
            old_system = session_messages[req.sessionId][0].get("content", "")
            # Replace or append memory section
            if "## Your Memories" in old_system:
                old_system = old_system[:old_system.index("## Your Memories")]
            session_messages[req.sessionId][0]["content"] = old_system + memory_context

    # Inject completed sub-agent results into system context
    # so the parent agent can reference what its sub-agents found.
    # Sources: 1) live agents_cache (current session), 2) cognitive memory (persists across restarts)
    sub_agent_results = []
    seen_keys = set()

    # First: pull from live agents_cache
    for aid, info in agents_cache.items():
        if info.get("isSubAgent") and info.get("status") == "completed" and info.get("lastResult"):
            key = f"sub-agent-result-{aid}"
            seen_keys.add(key)
            sub_agent_results.append(
                f"### {info['name']} (Sub-Agent #{aid})\n"
                f"Task: {info.get('description', 'N/A')}\n"
                f"Completed: {info.get('completedAt', 'unknown')}\n"
                f"Result:\n{info['lastResult']}\n"
            )

    # Second: pull from cognitive memory (survives relay restarts)
    if cognitive_engine.entries:
        for entry in cognitive_engine.entries.values():
            if entry.source == "sub-agent" and entry.key not in seen_keys:
                sub_agent_results.append(
                    f"### {entry.key} (from memory)\n"
                    f"Result:\n{entry.content}\n"
                )

    if sub_agent_results and session_messages.get(req.sessionId):
        sys_msg = session_messages[req.sessionId][0].get("content", "")
        # Remove old sub-agent section and append fresh one
        if "## Sub-Agent Reports" in sys_msg:
            sys_msg = sys_msg[:sys_msg.index("## Sub-Agent Reports")]
        sys_msg += "\n\n## Sub-Agent Reports\n"
        sys_msg += "The following sub-agents have completed their tasks. Use their findings to inform your responses:\n\n"
        sys_msg += "\n---\n".join(sub_agent_results)
        session_messages[req.sessionId][0]["content"] = sys_msg

    # Add user message
    session_messages[req.sessionId].append({
        "role": "user",
        "content": req.content,
    })

    # On-chain message storage is handled via multi-party signing from the frontend.
    # The relay no longer sends on-chain transactions from the sponsor account
    # (the sponsor has no agents/sessions — those belong to user accounts).
    on_chain = False
    on_chain_request_id = 0

    # Call LLM with full conversation history + tool definitions
    total_tokens = 0
    max_turns = 10
    messages = list(session_messages[req.sessionId])
    # Extract just the function objects (providers wrap them in {"type": "function", "function": ...})
    raw_tool_defs = agent_tool_executor.get_tool_definitions() if agent_tool_executor else []
    tool_defs = [td.get("function", td) for td in raw_tool_defs]

    # Resolve model: request → user's default → agent config → provider default
    resolved_model = req.model
    if not resolved_model:
        # Check user's default provider config for a stored default_model
        try:
            addr = _get_authed_address(request)
            user_configs = user_providers.get(addr, [])
            default_config = next((c for c in user_configs if c.get("is_default")), None)
            if default_config and default_config.get("default_model"):
                resolved_model = default_config["default_model"]
        except Exception:
            pass
    if not resolved_model and active_agent_id and active_agent_id in agents_cache:
        resolved_model = agents_cache[active_agent_id].get("model", "")
    if not resolved_model:
        # Infer sensible default from provider type
        if isinstance(provider, AnthropicProvider):
            resolved_model = "claude-sonnet-4-5-20250929"
        else:
            resolved_model = "gpt-4o-mini"
    logging.info(f"Using model: {resolved_model}")

    for turn in range(max_turns):
        try:
            result = provider.complete(
                model=resolved_model,
                messages=messages,
                max_tokens=4096,
                temperature=0.7,
                tools=tool_defs if tool_defs else None,
            )
        except Exception as e:
            logging.error(f"LLM call failed: {e}")
            raise HTTPException(status_code=502, detail=f"LLM provider error: {str(e)}")

        total_tokens += result.get("tokens_used", 0)

        # Handle tool calls — use AgentToolExecutor for real execution
        tool_calls = result.get("tool_calls", [])
        if tool_calls and agent_tool_executor:
            # Convert internal format to OpenAI format for message history
            # Venice/OpenAI expects: {id, type, function: {name, arguments}}
            openai_tool_calls = []
            for tc in tool_calls:
                openai_tool_calls.append({
                    "id": tc.get("id", ""),
                    "type": "function",
                    "function": {
                        "name": tc.get("name", ""),
                        "arguments": json.dumps(tc.get("input", tc.get("arguments", {}))),
                    },
                })
            messages.append({
                "role": "assistant",
                "content": result.get("content", "") or None,
                "tool_calls": openai_tool_calls,
            })
            for tc in tool_calls:
                tool_name = tc.get("name", "")
                tool_input = tc.get("input", tc.get("arguments", {}))
                logging.info(f"  Executing tool: {tool_name} with {json.dumps(tool_input)[:200]}")
                tool_result = agent_tool_executor.execute(tool_name, tool_input)
                logging.info(f"  Tool result: success={tool_result.success}, time={tool_result.execution_time_ms}ms")
                messages.append({
                    "role": "tool",
                    "content": tool_result.to_message(),
                    "tool_call_id": tc.get("id", ""),
                })
            continue

        # Final response
        response_content = result.get("content", "")

        # Parse and auto-store any memories the agent decided to save
        response_content = _parse_and_store_memories(response_content)

        # Save to session
        session_messages[req.sessionId].append({
            "role": "assistant",
            "content": response_content,
        })

        # On-chain response posting disabled — requires multi-party signing
        # (the sponsor account has no agents/sessions; those belong to user accounts).
        # On-chain message storage will be handled via frontend multi-party signing.

        return SendMessageResponse(
            requestId=int(time.time() * 1000) % 1000000,
            sessionId=req.sessionId,
            response=response_content,
            tokensUsed=total_tokens,
            turns=turn + 1,
            onChain=on_chain,
        )

    raise HTTPException(status_code=500, detail="Max turns reached")


@app.get("/sessions")
async def get_sessions():
    """List sessions from local cache."""
    # For PoC, return sessions we know about from the in-memory cache
    sessions = []
    for sid, msgs in session_messages.items():
        non_system = [m for m in msgs if m["role"] != "system"]
        sessions.append({
            "id": sid,
            "label": f"Session {sid}",
            "messageCount": len(non_system),
            "totalTokens": 0,
            "isOpen": True,
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
        })
    return sessions


@app.get("/session/{session_id}/messages")
async def get_session_messages(session_id: int):
    """Fetch messages for a session."""
    msgs = session_messages.get(session_id, [])
    result = []
    for i, m in enumerate(msgs):
        if m["role"] == "system":
            continue
        entry = {
            "id": i + 1,
            "role": m["role"],
            "content": m["content"],
            "timestamp": m.get("timestamp", time.strftime("%Y-%m-%dT%H:%M:%SZ")),
        }
        # Pass through extra fields (taskId, tokensUsed, etc.)
        if "taskId" in m:
            entry["taskId"] = m["taskId"]
        if "tokensUsed" in m:
            entry["tokensUsed"] = m["tokensUsed"]
        result.append(entry)
    return result


@app.get("/memory")
async def get_memory():
    """Fetch memory entries with cognitive metadata."""
    # If cognitive engine has data, use it (richer than flat cache)
    if cognitive_engine.entries:
        return cognitive_engine.export_entries()

    # Legacy fallback
    return [
        {
            "id": mid,
            "key": entry["key"],
            "content": entry.get("content", ""),
            "tags": entry.get("tags", []),
            "source": entry.get("source", ""),
            "encrypted": entry.get("encrypted", False),
            "contentHash": entry.get("contentHash", ""),
        }
        for mid, entry in memory_cache.items()
    ]


# -----------------------------------------------------------------------
# Cognitive Memory Endpoints
# -----------------------------------------------------------------------

@app.get("/cognitive/state")
async def get_cognitive_state():
    """Full cognitive memory state: entries, bonds, molecules, stats."""
    return {
        "stats": cognitive_engine.get_stats(),
        "entries": cognitive_engine.export_entries(),
        "bonds": cognitive_engine.export_bonds(),
        "molecules": cognitive_engine.export_molecules(),
    }


@app.get("/cognitive/stats")
async def get_cognitive_stats():
    """Quick cognitive memory statistics."""
    return cognitive_engine.get_stats()


@app.get("/cognitive/retrieve")
async def cognitive_retrieve(query: str, max_results: int = 10):
    """Molecular retrieval: find semantically coherent memory cluster for a query."""
    results = cognitive_engine.retrieve_molecular(query, max_results=max_results)
    return [
        {
            "id": e.memory_id,
            "key": e.key,
            "content": e.content,
            "tags": e.tags,
            "memoryType": e.memory_type,
            "memoryTypeName": MemoryType(e.memory_type).name.lower(),
            "importance": e.importance,
            "strength": round(e.strength, 3),
            "bondCount": e.bond_count,
            "moleculeId": e.molecule_id,
        }
        for e in results
    ]


@app.post("/cognitive/dream")
async def trigger_dream_cycle():
    """Manually trigger a dream cycle consolidation."""
    if not cognitive_engine.entries:
        return {"message": "No memories to consolidate", "result": None}

    result = cognitive_engine.run_dream_cycle()
    return {
        "message": "Dream cycle complete",
        "result": {
            "memoriesDecayed": result.memories_decayed,
            "memoriesPruned": result.memories_pruned,
            "bondsCreated": result.bonds_created,
            "moleculesFormed": result.molecules_formed,
            "promotions": result.promotions,
        },
        "stats": cognitive_engine.get_stats(),
    }


# -----------------------------------------------------------------------
# Account / Passkey Endpoints
# -----------------------------------------------------------------------

@app.post("/account/create-passkey")
async def create_passkey_account(req: CreatePasskeyAccountRequest):
    """Create a new Flow account using a WebAuthn passkey."""
    if not account_manager:
        raise HTTPException(status_code=503, detail="Account manager not initialized")

    try:
        result = await account_manager.create_passkey_account(
            public_key_hex=req.publicKey,
            credential_id=req.credentialId,
            display_name=req.displayName,
        )
        logging.info(f"Passkey account created: {result.get('address', 'unknown')}")
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        logging.error(f"Passkey account creation error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/account/verify-passkey")
async def verify_passkey(req: VerifyPasskeyRequest):
    """Verify a returning user's passkey and issue a session token."""
    if not account_manager:
        raise HTTPException(status_code=503, detail="Account manager not initialized")

    result = await account_manager.verify_passkey(
        credential_id=req.credentialId,
        client_data_json=req.clientDataJSON,
        authenticator_data=req.authenticatorData,
        signature=req.signature,
    )

    if not result:
        raise HTTPException(status_code=401, detail="Invalid passkey credential")

    return result


@app.get("/account/status")
async def get_account_status(request: Request):
    """Get account status including auth method and custody type."""
    # Try to get address from auth token first
    try:
        address = _get_authed_address(request)
    except HTTPException:
        # No valid token — return unauthenticated status
        return {
            "address": "",
            "authMethod": "none",
            "custodyType": "standalone",
            "authenticated": False,
        }

    if account_manager:
        status = account_manager.get_account_status(address)
        if status:
            status["authenticated"] = True
            return status

    return {
        "address": address,
        "authMethod": "passkey",
        "custodyType": "standalone",
        "authenticated": True,
    }


@app.post("/account/initiate-link")
async def initiate_link(req: InitiateLinkRequest):
    """Initiate Hybrid Custody linking to a parent wallet."""
    if not account_manager:
        raise HTTPException(status_code=503, detail="Account manager not initialized")

    address = config.flow_account_address if config else ""

    try:
        result = await account_manager.initiate_link(
            child_address=address,
            parent_address=req.parentAddress,
        )
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logging.error(f"Link initiation error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/account/custody-status")
async def get_custody_status():
    """Get current custody status (standalone, linking, linked)."""
    address = config.flow_account_address if config else ""

    if account_manager:
        acct = account_manager.accounts.get(address)
        if acct:
            return {
                "type": acct.custody_type,
                "parentAddress": acct.linked_parent,
                "authMethod": acct.auth_method,
            }

    return {"type": "standalone", "parentAddress": None, "authMethod": "relay"}


@app.get("/account/gas-usage")
async def get_gas_usage():
    """Get gas sponsorship usage for the current account."""
    if not gas_sponsor:
        return {"sponsored": False}

    address = config.flow_account_address if config else ""
    return gas_sponsor.get_account_usage(address)


# -----------------------------------------------------------------------
# User LLM Provider Endpoints (BYOK)
# -----------------------------------------------------------------------

KNOWN_PROVIDER_PRESETS = {
    "venice": {"type": "openai-compatible", "base_url": "https://api.venice.ai/api/v1"},
    "openai": {"type": "openai-compatible", "base_url": "https://api.openai.com/v1"},
    "anthropic": {"type": "anthropic", "base_url": "https://api.anthropic.com"},
    "openrouter": {"type": "openai-compatible", "base_url": "https://openrouter.ai/api/v1"},
    "together": {"type": "openai-compatible", "base_url": "https://api.together.xyz/v1"},
    "groq": {"type": "openai-compatible", "base_url": "https://api.groq.com/openai/v1"},
    "ollama": {"type": "ollama", "base_url": "http://localhost:11434"},
}


@app.get("/account/providers")
async def get_user_providers(request: Request):
    """List the authenticated user's configured LLM providers (keys masked)."""
    address = _get_authed_address(request)
    configs = user_providers.get(address, [])
    # Mask API keys in response
    masked = []
    for c in configs:
        entry = {**c}
        key = entry.get("api_key", "")
        entry["api_key"] = f"{key[:8]}...{key[-4:]}" if len(key) > 12 else "***"
        masked.append(entry)
    return {"providers": masked, "presets": list(KNOWN_PROVIDER_PRESETS.keys())}


@app.post("/account/providers")
async def save_user_provider(req: SaveProviderRequest, request: Request):
    """Save or update an LLM provider configuration for the authenticated user."""
    address = _get_authed_address(request)

    if address not in user_providers:
        user_providers[address] = []

    # Update existing or add new
    existing = next((c for c in user_providers[address] if c["name"] == req.name), None)
    if existing:
        existing["type"] = req.type
        existing["api_key"] = req.api_key
        existing["base_url"] = req.base_url
        if req.is_default:
            for c in user_providers[address]:
                c["is_default"] = False
            existing["is_default"] = True
    else:
        new_config = {
            "name": req.name,
            "type": req.type,
            "api_key": req.api_key,
            "base_url": req.base_url,
            "is_default": req.is_default or len(user_providers[address]) == 0,
        }
        # If this is the first provider, make it default
        if not user_providers[address]:
            new_config["is_default"] = True
        user_providers[address].append(new_config)

    # Clear cached provider instances for this user
    _user_provider_cache.pop(address, None)

    logging.info(f"Provider saved for {address}: {req.name} ({req.type})")
    return {"success": True, "name": req.name}


@app.delete("/account/providers/{provider_name}")
async def delete_user_provider(provider_name: str, request: Request):
    """Remove an LLM provider configuration for the authenticated user."""
    address = _get_authed_address(request)
    configs = user_providers.get(address, [])
    user_providers[address] = [c for c in configs if c["name"] != provider_name]
    _user_provider_cache.pop(address, None)
    logging.info(f"Provider deleted for {address}: {provider_name}")
    return {"success": True}


@app.put("/account/default-provider")
async def set_default_provider(req: SetDefaultProviderRequest, request: Request):
    """Set the default LLM provider and model for the authenticated user."""
    address = _get_authed_address(request)
    configs = user_providers.get(address, [])
    found = False
    for c in configs:
        if c["name"] == req.provider_name:
            c["is_default"] = True
            if req.model:
                c["default_model"] = req.model
            found = True
        else:
            c["is_default"] = False
    if not found:
        raise HTTPException(status_code=404, detail=f"Provider '{req.provider_name}' not found")
    return {"success": True}


@app.get("/account/providers/{provider_name}/models")
async def get_provider_models(provider_name: str, request: Request):
    """Fetch available models from a user's configured LLM provider.

    Queries the provider's API to list available models.
    Works with OpenAI-compatible APIs (Venice, OpenAI, OpenRouter, Together, Groq)
    and Anthropic.
    """
    address = _get_authed_address(request)
    configs = user_providers.get(address, [])
    target = next((c for c in configs if c["name"] == provider_name), None)
    if not target:
        raise HTTPException(status_code=404, detail=f"Provider '{provider_name}' not found")

    ptype = target.get("type", "openai-compatible")
    api_key = target.get("api_key", "")
    base_url = target.get("base_url", "")

    try:
        import requests as req_lib

        if ptype == "anthropic":
            # Anthropic doesn't have a /models endpoint; return known models
            return {"models": [
                {"id": "claude-opus-4-5-20251101", "name": "Claude Opus 4.5"},
                {"id": "claude-sonnet-4-5-20250929", "name": "Claude Sonnet 4.5"},
                {"id": "claude-haiku-4-5-20251001", "name": "Claude Haiku 4.5"},
                {"id": "claude-sonnet-4-6-20250514", "name": "Claude Sonnet 4.6"},
            ]}

        elif ptype == "ollama":
            # Ollama: GET /api/tags
            ollama_url = base_url or "http://localhost:11434"
            resp = req_lib.get(f"{ollama_url}/api/tags", timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                models = [
                    {"id": m.get("name", ""), "name": m.get("name", ""), "size": m.get("size", 0)}
                    for m in data.get("models", [])
                ]
                return {"models": models}
            return {"models": [], "error": f"Ollama returned {resp.status_code}"}

        else:
            # OpenAI-compatible: GET /v1/models
            url = base_url or "https://api.openai.com/v1"
            # Strip trailing /v1 if present, then add it back
            url = url.rstrip("/")
            if not url.endswith("/v1"):
                url += "/v1"
            headers = {"Authorization": f"Bearer {api_key}"}
            resp = req_lib.get(f"{url}/models", headers=headers, timeout=15)
            if resp.status_code == 200:
                data = resp.json()
                raw_models = data.get("data", data.get("models", []))
                models = []
                for m in raw_models:
                    model_id = m.get("id", "") if isinstance(m, dict) else str(m)
                    model_name = m.get("id", "") if isinstance(m, dict) else str(m)
                    owned_by = m.get("owned_by", "") if isinstance(m, dict) else ""
                    models.append({"id": model_id, "name": model_name, "owned_by": owned_by})
                # Sort alphabetically
                models.sort(key=lambda x: x["id"])
                return {"models": models}
            else:
                error_text = resp.text[:300]
                logging.warning(f"Model list fetch failed from {url}: {resp.status_code} {error_text}")
                return {"models": [], "error": f"Provider returned {resp.status_code}"}

    except Exception as e:
        logging.error(f"Error fetching models for {provider_name}: {e}")
        return {"models": [], "error": str(e)}


@app.get("/account/provider-presets")
async def get_provider_presets():
    """Get known provider presets with their default base URLs."""
    return {"presets": KNOWN_PROVIDER_PRESETS}


# -----------------------------------------------------------------------
# Multi-Agent Endpoints
# -----------------------------------------------------------------------

@app.get("/agents")
async def get_agents():
    """List all agents for this account."""
    if not agents_cache:
        # No agents yet — user needs to create one after adding LLM provider
        return []

    return [
        {
            "id": aid,
            "name": info.get("name", ""),
            "description": info.get("description", ""),
            "isActive": info.get("isActive", True),
            "isDefault": aid == active_agent_id,
            "isSubAgent": info.get("isSubAgent", False),
            "parentAgentId": info.get("parentAgentId"),
            "expiresAt": info.get("expiresAt"),
            "totalSessions": info.get("totalSessions", 0),
            "totalInferences": info.get("totalInferences", 0),
            "createdAt": info.get("createdAt", ""),
            "systemPrompt": info.get("systemPrompt", ""),
            "status": info.get("status"),
            "lastResult": info.get("lastResult"),
            "completedAt": info.get("completedAt"),
        }
        for aid, info in agents_cache.items()
    ]


@app.post("/agents/create")
async def create_agent(req: CreateAgentRequest):
    """Create a new agent in the account's AgentCollection."""
    global active_agent_id

    try:
        # On-chain agent creation is handled via multi-party signing from the frontend.
        # The relay only manages the local cache; on-chain tx runs with user as authorizer.
        success = True

        # Cache locally
        agent_id = max(agents_cache.keys()) + 1 if agents_cache else 2
        agents_cache[agent_id] = {
            "name": req.name,
            "description": req.description,
            "isActive": True,
            "isSubAgent": False,
            "totalSessions": 0,
            "totalInferences": 0,
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "systemPrompt": req.systemPrompt or f"You are {req.name}, an AI agent on Flow blockchain.",
            "provider": req.provider,
            "model": req.model,
        }

        # Set as active if first additional agent
        if active_agent_id is None:
            active_agent_id = agent_id

        logging.info(f"Agent created: ID={agent_id}, name={req.name}")
        return {"agentId": agent_id, "success": True, "onChain": success}

    except Exception as e:
        logging.error(f"Error creating agent: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/agents/{agent_id}/spawn")
async def spawn_sub_agent(agent_id: int, req: SpawnSubAgentRequest):
    """Spawn a sub-agent from a parent agent."""
    try:
        # Calculate expiry
        expires_at = None
        if req.ttlSeconds:
            expires_at = time.time() + req.ttlSeconds

        sub_id = max(agents_cache.keys()) + 1 if agents_cache else 3
        agents_cache[sub_id] = {
            "name": req.name,
            "description": req.description,
            "isActive": True,
            "isSubAgent": True,
            "parentAgentId": agent_id,
            "expiresAt": expires_at,
            "totalSessions": 0,
            "totalInferences": 0,
            "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "systemPrompt": f"You are {req.name}, a sub-agent.",
        }

        logging.info(f"Sub-agent spawned: ID={sub_id}, parent={agent_id}, name={req.name}")
        return {"agentId": sub_id, "parentId": agent_id, "success": True}

    except Exception as e:
        logging.error(f"Error spawning sub-agent: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/agents/{agent_id}/select")
async def select_agent(agent_id: int):
    """Set the active agent for the current session."""
    global active_agent_id
    active_agent_id = agent_id
    logging.info(f"Active agent changed to: {agent_id}")
    return {"activeAgentId": agent_id, "success": True}


@app.delete("/agents/{agent_id}")
async def delete_agent(agent_id: int):
    """Remove an agent from the collection."""
    global active_agent_id

    if agent_id in agents_cache:
        del agents_cache[agent_id]
        if active_agent_id == agent_id:
            active_agent_id = next(iter(agents_cache), None)
        logging.info(f"Agent deleted: ID={agent_id}")
        return {"success": True}

    raise HTTPException(status_code=404, detail="Agent not found")


@app.get("/tasks")
async def get_tasks():
    """Fetch scheduled tasks from on-chain + local cache."""
    # Return cached tasks from operations performed through the API
    return [
        {
            "id": tid,
            "name": entry["name"],
            "description": entry.get("description", ""),
            "category": entry.get("category", 0),
            "prompt": entry.get("prompt", ""),
            "maxTurns": entry.get("maxTurns", 10),
            "priority": entry.get("priority", 0),
            "executeAt": entry.get("executeAt", 0.0),
            "isRecurring": entry.get("isRecurring", False),
            "isActive": entry.get("isActive", True),
            "executionCount": entry.get("executionCount", 0),
        }
        for tid, entry in tasks_cache.items()
    ]


@app.get("/hooks")
async def get_hooks():
    """Fetch lifecycle hooks from on-chain + local cache."""
    # Return cached hooks from operations performed through the API
    return [
        {
            "id": hid,
            "name": entry.get("name", ""),
            "hookType": entry.get("hookType", ""),
            "isActive": entry.get("isActive", True),
        }
        for hid, entry in hooks_cache.items()
    ]


# -----------------------------------------------------------------------
# Memory Endpoints
# -----------------------------------------------------------------------

@app.post("/memory/store")
async def store_memory(req: StoreMemoryRequest):
    """Store a memory entry on-chain with encryption."""
    global _next_memory_id

    try:
        # Encrypt the content — REQUIRED for on-chain storage
        if not encryption or not encryption.is_configured:
            raise HTTPException(
                status_code=503,
                detail="Encryption not configured. Cannot store unencrypted content on-chain."
            )
        enc = encryption.encrypt(req.content)
        encrypted = True

        # Build transaction arguments (9 params as per schema)
        # tags must be an array of {type, value} objects for Flow CLI
        tags_array = [{"type": "String", "value": t} for t in (req.tags or [])]
        tx_args = json.dumps([
            {"type": "String", "value": req.key},
            {"type": "String", "value": enc["ciphertext"]},
            {"type": "String", "value": enc["nonce"]},
            {"type": "String", "value": enc["plaintextHash"]},
            {"type": "String", "value": enc["keyFingerprint"]},
            {"type": "UInt8", "value": str(enc["algorithm"])},
            {"type": "UInt64", "value": str(enc["plaintextLength"])},
            {"type": "Array", "value": tags_array},
            {"type": "String", "value": req.source},
        ])

        # Send transaction
        result = run_flow_tx("cadence/transactions/store_memory.cdc", tx_args)
        success = result is not None and ("sealed" in result.lower() or "success" in result.lower())

        if success:
            # Classify and store in cognitive engine
            memory_type, importance, emotional_weight = CognitiveMemoryEngine.classify_memory(
                req.key, req.content, req.tags or []
            )
            cog_entry = cognitive_engine.store(
                key=req.key,
                content=req.content if not encrypted else "[encrypted]",
                tags=req.tags or [],
                source=req.source,
                memory_type=memory_type,
                importance=importance,
                emotional_weight=emotional_weight,
            )
            cog_entry.on_chain = True

            # Also cache in legacy system
            memory_id = cog_entry.memory_id
            memory_cache[memory_id] = {
                "key": req.key,
                "content": req.content if not encrypted else "[encrypted]",
                "tags": req.tags,
                "source": req.source,
                "encrypted": encrypted,
                "contentHash": enc["plaintextHash"],
                "memoryType": memory_type,
                "importance": importance,
            }
            logging.info(
                f"Memory stored: ID={memory_id}, key={req.key}, "
                f"type={MemoryType(memory_type).name}, importance={importance}, "
                f"bonds={cog_entry.bond_count}"
            )
            return MemoryStoreResponse(memoryId=memory_id, success=True)
        else:
            logging.error(f"Failed to store memory: {result}")
            raise HTTPException(status_code=500, detail=f"Failed to store memory on-chain")

    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Error storing memory: {e}")
        raise HTTPException(status_code=500, detail=f"Error storing memory: {str(e)}")


# -----------------------------------------------------------------------
# Task Endpoints
# -----------------------------------------------------------------------

@app.post("/tasks/schedule")
async def schedule_task(req: ScheduleTaskRequest):
    """Schedule a task on-chain."""
    global _next_task_id

    try:
        # Build transaction arguments — types must match Cadence signature exactly
        # executeAt must be UFix64 format (decimal string like "1234567890.00000000")
        execute_at_str = f"{req.executeAt:.8f}"

        # Build optional args
        tx_arg_list = [
            {"type": "String", "value": req.name},
            {"type": "String", "value": req.description},
            {"type": "UInt8", "value": str(req.category)},
            {"type": "String", "value": req.prompt},
            {"type": "UInt64", "value": str(req.maxTurns)},
            {"type": "UInt8", "value": str(req.priority)},
            {"type": "UFix64", "value": execute_at_str},
            {"type": "Bool", "value": req.isRecurring},
        ]
        # Optional UFix64?
        if req.intervalSeconds:
            tx_arg_list.append({"type": "Optional", "value": {"type": "UFix64", "value": f"{req.intervalSeconds:.8f}"}})
        else:
            tx_arg_list.append({"type": "Optional", "value": None})
        # Optional UInt64?
        if req.maxExecutions:
            tx_arg_list.append({"type": "Optional", "value": {"type": "UInt64", "value": str(req.maxExecutions)}})
        else:
            tx_arg_list.append({"type": "Optional", "value": None})

        tx_args = json.dumps(tx_arg_list)

        # Send transaction
        result = run_flow_tx("cadence/transactions/schedule_task.cdc", tx_args)
        success = result is not None and ("sealed" in result.lower() or "success" in result.lower())

        if success:
            # Cache the operation
            task_id = _next_task_id
            tasks_cache[task_id] = {
                "name": req.name,
                "description": req.description,
                "category": req.category,
                "prompt": req.prompt,
                "maxTurns": req.maxTurns,
                "priority": req.priority,
                "executeAt": req.executeAt,
                "isRecurring": req.isRecurring,
                "intervalSeconds": req.intervalSeconds,
                "maxExecutions": req.maxExecutions,
                "isActive": True,
                "executionCount": 0,
            }
            _next_task_id += 1
            logging.info(f"Task scheduled: ID={task_id}, name={req.name}")
            return TaskScheduleResponse(taskId=task_id, success=True)
        else:
            logging.error(f"Failed to schedule task: {result}")
            raise HTTPException(status_code=500, detail=f"Failed to schedule task on-chain")

    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Error scheduling task: {e}")
        raise HTTPException(status_code=500, detail=f"Error scheduling task: {str(e)}")


@app.post("/tasks/{task_id}/cancel")
async def cancel_task(task_id: int):
    """Cancel a scheduled task."""
    try:
        # Build transaction arguments
        tx_args = json.dumps([
            {"type": "UInt64", "value": str(task_id)},
        ])

        # Send transaction
        result = run_flow_tx("cadence/transactions/cancel_task.cdc", tx_args)
        success = result is not None and ("sealed" in result.lower() or "success" in result.lower())

        if success:
            # Update cache
            if task_id in tasks_cache:
                tasks_cache[task_id]["isActive"] = False
            logging.info(f"Task cancelled: ID={task_id}")
            return OperationResponse(success=True)
        else:
            logging.error(f"Failed to cancel task: {result}")
            raise HTTPException(status_code=500, detail=f"Failed to cancel task on-chain")

    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Error cancelling task: {e}")
        raise HTTPException(status_code=500, detail=f"Error cancelling task: {str(e)}")


@app.get("/tasks/{task_id}/results")
async def get_task_results(task_id: int):
    """Fetch execution results for a task."""
    if task_id not in tasks_cache:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")

    results = task_results.get(task_id, [])
    return results


# -----------------------------------------------------------------------
# Extension Endpoints
# -----------------------------------------------------------------------

@app.get("/extensions")
async def get_extensions():
    """Fetch extensions from on-chain + local cache."""
    return [
        {
            "id": eid,
            "name": entry["name"],
            "description": entry.get("description", ""),
            "version": entry.get("version", "1.0.0"),
            "category": entry.get("category", 0),
            "tags": entry.get("tags", []),
            "sourceHash": entry.get("sourceHash", ""),
            "isInstalled": entry.get("isInstalled", False),
        }
        for eid, entry in extensions_cache.items()
    ]


@app.post("/extensions/publish")
async def publish_extension(req: PublishExtensionRequest):
    """Publish an extension on-chain."""
    global _next_extension_id

    try:
        # Build transaction arguments
        # tags must be an array of {type, value} objects for Flow CLI
        tags_array = [{"type": "String", "value": t} for t in (req.tags or [])]
        tx_args = json.dumps([
            {"type": "String", "value": req.name},
            {"type": "String", "value": req.description},
            {"type": "String", "value": req.version},
            {"type": "UInt8", "value": str(req.category)},
            {"type": "String", "value": req.sourceHash},
            {"type": "Array", "value": tags_array},
        ])

        # Send transaction
        result = run_flow_tx("cadence/transactions/publish_extension.cdc", tx_args)
        success = result is not None and ("sealed" in result.lower() or "success" in result.lower())

        if success:
            # Cache the operation
            extension_id = _next_extension_id
            extensions_cache[extension_id] = {
                "name": req.name,
                "description": req.description,
                "version": req.version,
                "category": req.category,
                "sourceHash": req.sourceHash,
                "tags": req.tags,
                "isInstalled": False,
            }
            _next_extension_id += 1
            logging.info(f"Extension published: ID={extension_id}, name={req.name}")
            return ExtensionPublishResponse(extensionId=extension_id, success=True)
        else:
            logging.error(f"Failed to publish extension: {result}")
            raise HTTPException(status_code=500, detail=f"Failed to publish extension on-chain")

    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Error publishing extension: {e}")
        raise HTTPException(status_code=500, detail=f"Error publishing extension: {str(e)}")


@app.post("/extensions/{extension_id}/install")
async def install_extension(extension_id: int, req: InstallExtensionRequest):
    """Install an extension."""
    try:
        # Build transaction arguments
        # config must be a Cadence Dictionary {String: String}
        config_entries = [
            {"key": {"type": "String", "value": k}, "value": {"type": "String", "value": v}}
            for k, v in (req.config or {}).items()
        ]
        tx_args = json.dumps([
            {"type": "UInt64", "value": str(extension_id)},
            {"type": "Dictionary", "value": config_entries},
        ])

        # Send transaction
        result = run_flow_tx("cadence/transactions/install_extension.cdc", tx_args)
        success = result is not None and ("sealed" in result.lower() or "success" in result.lower())

        if success:
            # Update cache
            if extension_id in extensions_cache:
                extensions_cache[extension_id]["isInstalled"] = True
            logging.info(f"Extension installed: ID={extension_id}")
            return OperationResponse(success=True)
        else:
            logging.error(f"Failed to install extension: {result}")
            raise HTTPException(status_code=500, detail=f"Failed to install extension on-chain")

    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Error installing extension: {e}")
        raise HTTPException(status_code=500, detail=f"Error installing extension: {str(e)}")


@app.post("/extensions/{extension_id}/uninstall")
async def uninstall_extension(extension_id: int):
    """Uninstall an extension."""
    try:
        # Build transaction arguments
        tx_args = json.dumps([
            {"type": "UInt64", "value": str(extension_id)},
        ])

        # Send transaction
        result = run_flow_tx("cadence/transactions/uninstall_extension.cdc", tx_args)
        success = result is not None and ("sealed" in result.lower() or "success" in result.lower())

        if success:
            # Update cache
            if extension_id in extensions_cache:
                extensions_cache[extension_id]["isInstalled"] = False
            logging.info(f"Extension uninstalled: ID={extension_id}")
            return OperationResponse(success=True)
        else:
            logging.error(f"Failed to uninstall extension: {result}")
            raise HTTPException(status_code=500, detail=f"Failed to uninstall extension on-chain")

    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Error uninstalling extension: {e}")
        raise HTTPException(status_code=500, detail=f"Error uninstalling extension: {str(e)}")


# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
