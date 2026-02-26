#!/usr/bin/env python3
"""
FlowClaw Transaction & Tool Executor
=====================================
Gives agents real tool execution capabilities beyond text generation.
This is what turns "check FLOW price" from generating a Python script
into actually fetching the price and returning real data.

Tool categories:
  - web_fetch: HTTP requests to external APIs
  - query_balance: Check FLOW/token balances on-chain
  - execute_cadence: Run arbitrary Cadence scripts
  - transfer_flow: Send FLOW tokens (requires approval based on autonomy level)

Security:
  - All tools checked against agent's SecurityPolicy
  - Rate limiting enforced per agent
  - Financial tools require autonomyLevel >= 1
  - Dangerous tools (shell_exec) denied by default

Migration note: Now uses FlowRESTClient (HTTP) instead of CLI subprocess.
"""

import json
import logging
import os
import time
import subprocess
import hashlib
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, field
from pathlib import Path

try:
    import requests as http_requests
except ImportError:
    http_requests = None

logger = logging.getLogger(__name__)


@dataclass
class ToolResult:
    """Result of a tool execution."""
    tool_name: str
    success: bool
    output: Any
    error: Optional[str] = None
    execution_time_ms: int = 0
    tokens_estimate: int = 0

    def to_dict(self) -> Dict:
        return {
            "tool": self.tool_name,
            "success": self.success,
            "output": self.output,
            "error": self.error,
            "executionTimeMs": self.execution_time_ms,
        }

    def to_message(self) -> str:
        """Format as a string for LLM consumption."""
        if self.success:
            if isinstance(self.output, dict):
                return json.dumps(self.output, indent=2)
            return str(self.output)
        return f"Error: {self.error}"


@dataclass
class SecurityContext:
    """Agent's security context for tool authorization."""
    agent_id: int
    autonomy_level: int  # 0=readonly, 1=supervised, 2=full
    allowed_tools: List[str] = field(default_factory=list)
    denied_tools: List[str] = field(default_factory=list)
    max_actions_per_hour: int = 100
    action_count_this_hour: int = 0
    last_hour_reset: float = 0


class AgentToolExecutor:
    """
    Executes tools on behalf of AI agents with security policy enforcement.

    This is the bridge between LLM tool calls and actual execution.
    When Venice AI returns a tool_call for "web_fetch", this class
    actually makes the HTTP request and returns real data.
    """

    # Configurable safety limit for FLOW transfers
    MAX_FLOW_TRANSFER = float(os.environ.get("MAX_FLOW_TRANSFER", "10.0"))

    def __init__(self, flow_cli_runner=None, project_dir: str = None, spawn_callback=None, flow_rest_client=None, network: str = None):
        """
        Args:
            flow_cli_runner: Function that runs Flow CLI commands (legacy, from api.py)
            project_dir: Path to FlowClaw project root
            spawn_callback: Function(parent_id, name, description, ttl_seconds) -> dict
                            Called when the LLM wants to spawn a sub-agent.
            flow_rest_client: FlowRESTClient instance for direct REST API access
            network: Flow network (testnet, mainnet, emulator)
        """
        self.flow_cli_runner = flow_cli_runner
        self.project_dir = project_dir or str(Path(__file__).parent.parent)
        self.spawn_callback = spawn_callback
        self.flow_client = flow_rest_client  # FlowRESTClient instance
        self.network = network or os.environ.get("FLOW_NETWORK", "testnet")

        # Track tool usage per agent for rate limiting
        self._agent_usage: Dict[int, Dict] = {}

        # Tool registry
        self._tools = {
            "web_fetch": self._tool_web_fetch,
            "query_balance": self._tool_query_balance,
            "query_account": self._tool_query_account,
            "execute_cadence_script": self._tool_execute_cadence,
            "send_flow_tokens": self._tool_send_flow_tokens,
            "execute_transaction": self._tool_execute_transaction,
            "get_block_info": self._tool_get_block_info,
            "get_flow_price": self._tool_get_flow_price,
            "search_web": self._tool_search_web,
            "spawn_sub_agent": self._tool_spawn_sub_agent,
        }

        logger.info(f"AgentToolExecutor initialized with {len(self._tools)} tools")

    def get_tool_definitions(self) -> List[Dict]:
        """
        Return OpenAI-compatible tool definitions for the LLM system prompt.
        These tell the LLM what tools it can call.
        """
        return [
            {
                "type": "function",
                "function": {
                    "name": "web_fetch",
                    "description": (
                        "Fetch data from a URL. Use this for checking prices, "
                        "reading APIs, getting current information from the web. "
                        "Returns the response body as text or JSON."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "url": {
                                "type": "string",
                                "description": "The URL to fetch data from",
                            },
                            "method": {
                                "type": "string",
                                "enum": ["GET", "POST"],
                                "description": "HTTP method (default: GET)",
                            },
                            "headers": {
                                "type": "object",
                                "description": "Optional HTTP headers",
                            },
                        },
                        "required": ["url"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "query_balance",
                    "description": (
                        "Check the FLOW token balance of any Flow blockchain address."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "address": {
                                "type": "string",
                                "description": "The Flow address to check (e.g., '0xe467b9dd11fa00df')",
                            },
                        },
                        "required": ["address"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "query_account",
                    "description": (
                        "Get information about a Flow blockchain account including "
                        "address, balance, keys, and contracts."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "address": {
                                "type": "string",
                                "description": "The Flow address to query",
                            },
                        },
                        "required": ["address"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "execute_cadence_script",
                    "description": (
                        "Execute a read-only Cadence script on the Flow blockchain. "
                        "This cannot modify state — it only reads data. "
                        "Use for custom on-chain queries."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "script": {
                                "type": "string",
                                "description": "The Cadence script code to execute",
                            },
                            "arguments": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "type": {"type": "string"},
                                        "value": {"type": "string"},
                                    },
                                },
                                "description": "Script arguments in Cadence JSON format",
                            },
                        },
                        "required": ["script"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "send_flow_tokens",
                    "description": (
                        "Send FLOW tokens from the agent's wallet to another Flow address. "
                        "This submits a real on-chain transaction. Use when the user asks "
                        "to transfer, send, or move FLOW to an address."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "to_address": {
                                "type": "string",
                                "description": "The recipient Flow address (e.g., '0x1234...')",
                            },
                            "amount": {
                                "type": "string",
                                "description": "Amount of FLOW to send (e.g., '1.0', '0.5')",
                            },
                        },
                        "required": ["to_address", "amount"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "execute_transaction",
                    "description": (
                        "Execute a custom Cadence transaction on the Flow blockchain. "
                        "This can modify on-chain state. Use for any on-chain action "
                        "beyond simple FLOW transfers — like interacting with contracts, "
                        "creating resources, updating storage, etc."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "transaction_code": {
                                "type": "string",
                                "description": "The Cadence transaction code to execute",
                            },
                            "arguments": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "type": {"type": "string"},
                                        "value": {"type": "string"},
                                    },
                                },
                                "description": "Transaction arguments in Cadence JSON format",
                            },
                        },
                        "required": ["transaction_code"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "get_block_info",
                    "description": (
                        "Get the latest sealed block information from the Flow blockchain."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {},
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "get_flow_price",
                    "description": (
                        "Get the current FLOW token price in USD from CoinGecko."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "currency": {
                                "type": "string",
                                "description": "Currency to get price in (default: usd)",
                            },
                        },
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "search_web",
                    "description": (
                        "Search the web for information using DuckDuckGo. "
                        "Returns a summary of top results."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "The search query",
                            },
                            "max_results": {
                                "type": "integer",
                                "description": "Maximum number of results (default: 5)",
                            },
                        },
                        "required": ["query"],
                    },
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "spawn_sub_agent",
                    "description": (
                        "Spawn a sub-agent to handle a specific task autonomously. "
                        "Sub-agents are temporary Cadence resources with their own identity. "
                        "Use this when the user asks you to delegate work to a sub-agent, "
                        "or when a task would benefit from a specialized worker. "
                        "The sub-agent will appear on the user's Agent Canvas."
                    ),
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "name": {
                                "type": "string",
                                "description": "Name for the sub-agent (e.g., 'Research Agent', 'Price Tracker')",
                            },
                            "task": {
                                "type": "string",
                                "description": "Description of what this sub-agent should do",
                            },
                            "ttl_minutes": {
                                "type": "integer",
                                "description": "Time-to-live in minutes before the sub-agent expires (default: 60, 0 for no expiry)",
                            },
                        },
                        "required": ["name", "task"],
                    },
                },
            },
        ]

    def check_authorization(
        self, tool_name: str, security: SecurityContext
    ) -> Optional[str]:
        """
        Check if the agent is authorized to use this tool.
        Returns None if authorized, error message if not.
        """
        # Check denied tools
        if tool_name in security.denied_tools:
            return f"Tool '{tool_name}' is denied by agent security policy"

        # Check allowed tools (if specified, acts as whitelist)
        if security.allowed_tools and tool_name not in security.allowed_tools:
            return f"Tool '{tool_name}' not in agent's allowed tools list"

        # Check autonomy level for financial/transaction tools
        financial_tools = {"send_flow_tokens", "execute_transaction", "transfer_nft"}
        if tool_name in financial_tools and security.autonomy_level < 1:
            return f"Tool '{tool_name}' requires autonomy level >= 1 (current: {security.autonomy_level})"

        # Check rate limit
        now = time.time()
        if now - security.last_hour_reset > 3600:
            security.action_count_this_hour = 0
            security.last_hour_reset = now

        if security.action_count_this_hour >= security.max_actions_per_hour:
            return f"Rate limit exceeded ({security.max_actions_per_hour} actions/hour)"

        return None

    def execute(
        self,
        tool_name: str,
        parameters: Dict[str, Any],
        security: Optional[SecurityContext] = None,
    ) -> ToolResult:
        """
        Execute a tool with the given parameters.

        Args:
            tool_name: Name of the tool to execute
            parameters: Tool parameters from LLM
            security: Agent's security context (optional for backward compat)

        Returns:
            ToolResult with the execution outcome
        """
        start_time = time.time()

        # Authorization check
        if security:
            auth_error = self.check_authorization(tool_name, security)
            if auth_error:
                return ToolResult(
                    tool_name=tool_name,
                    success=False,
                    output=None,
                    error=auth_error,
                )
            security.action_count_this_hour += 1

        # Find and execute tool
        tool_fn = self._tools.get(tool_name)
        if not tool_fn:
            return ToolResult(
                tool_name=tool_name,
                success=False,
                output=None,
                error=f"Unknown tool: {tool_name}. Available: {list(self._tools.keys())}",
            )

        try:
            result = tool_fn(parameters)
            execution_ms = int((time.time() - start_time) * 1000)

            return ToolResult(
                tool_name=tool_name,
                success=True,
                output=result,
                execution_time_ms=execution_ms,
            )
        except Exception as e:
            execution_ms = int((time.time() - start_time) * 1000)
            logger.error(f"Tool '{tool_name}' execution error: {e}")
            return ToolResult(
                tool_name=tool_name,
                success=False,
                output=None,
                error=str(e),
                execution_time_ms=execution_ms,
            )

    # -----------------------------------------------------------------------
    # Tool Implementations
    # -----------------------------------------------------------------------

    def _tool_web_fetch(self, params: Dict) -> Any:
        """Fetch data from a URL."""
        if not http_requests:
            raise RuntimeError("requests library not installed")

        url = params.get("url")
        if not url:
            raise ValueError("'url' parameter is required")

        method = params.get("method", "GET").upper()
        headers = params.get("headers", {})
        body = params.get("body")

        # Safety: block obviously dangerous URLs
        blocked_patterns = ["localhost", "127.0.0.1", "0.0.0.0", "169.254", "10.", "192.168."]
        for pattern in blocked_patterns:
            if pattern in url.lower():
                raise ValueError(f"Cannot fetch internal/private URLs (contains '{pattern}')")

        # Add a reasonable user agent
        if "User-Agent" not in headers:
            headers["User-Agent"] = "FlowClaw-Agent/0.1"

        try:
            if method == "GET":
                resp = http_requests.get(url, headers=headers, timeout=15)
            elif method == "POST":
                resp = http_requests.post(url, headers=headers, json=body, timeout=15)
            else:
                raise ValueError(f"Unsupported HTTP method: {method}")

            # Try to parse as JSON
            try:
                data = resp.json()
                return {
                    "status": resp.status_code,
                    "data": data,
                    "content_type": resp.headers.get("content-type", ""),
                }
            except (json.JSONDecodeError, ValueError):
                # Return as text, truncated for safety
                text = resp.text[:5000]
                return {
                    "status": resp.status_code,
                    "data": text,
                    "content_type": resp.headers.get("content-type", ""),
                }

        except http_requests.exceptions.Timeout:
            raise RuntimeError(f"Request timed out after 15 seconds: {url}")
        except http_requests.exceptions.ConnectionError:
            raise RuntimeError(f"Connection error: {url}")

    def _tool_query_balance(self, params: Dict) -> Dict:
        """Query FLOW balance for an address."""
        address = params.get("address", "")
        if not address:
            raise ValueError("'address' parameter is required")

        # Normalize address
        if not address.startswith("0x"):
            address = "0x" + address

        # Try REST API first
        if self.flow_client:
            try:
                balance = self.flow_client.get_balance(address)
                return {
                    "address": address,
                    "balance": balance,
                    "currency": "FLOW",
                    "source": "REST API",
                }
            except Exception as e:
                logger.warning(f"REST balance query failed, trying script: {e}")

        # Fallback to Cadence script
        script = """
        access(all) fun main(address: Address): UFix64 {
            let account = getAccount(address)
            return account.balance
        }
        """

        result = self._run_cadence_script(script, [
            {"type": "Address", "value": address}
        ])

        return {
            "address": address,
            "balance": result,
            "currency": "FLOW",
        }

    def _tool_query_account(self, params: Dict) -> Dict:
        """Query account information."""
        address = params.get("address", "")
        if not address:
            raise ValueError("'address' parameter is required")

        if not address.startswith("0x"):
            address = "0x" + address

        # Try REST API first
        if self.flow_client:
            try:
                account = self.flow_client.get_account(address)
                return {
                    "address": address,
                    "balance": account.get("balance", "0"),
                    "keys": len(account.get("keys", [])),
                    "contracts": list(account.get("contracts", {}).keys()),
                    "source": "REST API",
                }
            except Exception as e:
                logger.warning(f"REST account query failed, trying CLI: {e}")

        # CLI fallback
        try:
            network = self.network
            cmd = [
                "flow", "accounts", "get", address,
                "--network", network,
            ]
            result = subprocess.run(
                cmd, capture_output=True, text=True,
                cwd=self.project_dir, timeout=15,
            )
            if result.returncode == 0:
                return {
                    "address": address,
                    "info": result.stdout.strip()[:3000],
                }
            else:
                return {
                    "address": address,
                    "error": result.stderr.strip()[:500],
                }
        except Exception as e:
            raise RuntimeError(f"Failed to query account: {e}")

    def _tool_execute_cadence(self, params: Dict) -> Any:
        """Execute a Cadence script (read-only)."""
        script = params.get("script", "")
        if not script:
            raise ValueError("'script' parameter is required")

        arguments = params.get("arguments", [])

        # Safety check: reject anything that looks like a transaction
        dangerous_keywords = ["prepare(", "execute {", "transaction(", "transaction {"]
        for kw in dangerous_keywords:
            if kw in script:
                raise ValueError(
                    "Cannot execute transactions via this tool. "
                    "Only read-only scripts are allowed."
                )

        return self._run_cadence_script(script, arguments)

    def _tool_send_flow_tokens(self, params: Dict) -> Dict:
        """Send FLOW tokens to another address."""
        to_address = params.get("to_address", "")
        amount = params.get("amount", "")

        if not to_address:
            raise ValueError("'to_address' parameter is required")
        if not amount:
            raise ValueError("'amount' parameter is required")

        # Normalize address
        if not to_address.startswith("0x"):
            to_address = "0x" + to_address

        # Validate amount is a reasonable number
        try:
            amt = float(amount)
            if amt <= 0:
                raise ValueError("Amount must be positive")
            if amt > self.MAX_FLOW_TRANSFER:
                raise ValueError(
                    f"Safety limit: cannot send more than {self.MAX_FLOW_TRANSFER} FLOW in a single transaction "
                    f"(requested: {amount}). Adjust MAX_FLOW_TRANSFER env var to change."
                )
        except (ValueError, TypeError) as e:
            if "Safety limit" in str(e) or "positive" in str(e):
                raise
            raise ValueError(f"Invalid amount: {amount}")

        # Build the FLOW transfer transaction
        tx_code = """
import "FungibleToken"
import "FlowToken"

transaction(amount: UFix64, to: Address) {
    let sentVault: @{FungibleToken.Vault}

    prepare(signer: auth(BorrowValue) &Account) {
        let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        ) ?? panic("Could not borrow reference to the owner's Vault!")

        self.sentVault <- vaultRef.withdraw(amount: amount)
    }

    execute {
        let receiverRef = getAccount(to)
            .capabilities.borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
            ?? panic("Could not borrow receiver reference to the recipient's Vault")

        receiverRef.deposit(from: <-self.sentVault)
    }
}
"""

        if not self.flow_client:
            raise RuntimeError("Flow REST client not configured — cannot send transactions")

        try:
            arguments = [
                {"type": "UFix64", "value": amount},
                {"type": "Address", "value": to_address},
            ]
            result = self.flow_client.send_transaction(tx_code, arguments)

            status = result.get("status", "UNKNOWN")
            tx_id = result.get("txId", "")
            error = result.get("error", "")

            if error:
                return {
                    "success": False,
                    "tx_id": tx_id,
                    "status": status,
                    "error": error,
                    "amount": amount,
                    "to": to_address,
                }

            return {
                "success": True,
                "tx_id": tx_id,
                "status": status,
                "amount": amount,
                "to": to_address,
                "message": f"Successfully sent {amount} FLOW to {to_address}",
                "flowscan_url": self._flowscan_url(tx_id),
            }
        except Exception as e:
            raise RuntimeError(f"Failed to send FLOW tokens: {e}")

    def _tool_execute_transaction(self, params: Dict) -> Dict:
        """Execute a custom Cadence transaction."""
        tx_code = params.get("transaction_code", "")
        arguments = params.get("arguments", [])

        if not tx_code:
            raise ValueError("'transaction_code' parameter is required")

        # Basic safety: must contain transaction keyword
        if "transaction" not in tx_code.lower():
            raise ValueError("Code must be a valid Cadence transaction (must contain 'transaction' keyword)")

        if not self.flow_client:
            raise RuntimeError("Flow REST client not configured — cannot send transactions")

        try:
            result = self.flow_client.send_transaction(tx_code, arguments)

            status = result.get("status", "UNKNOWN")
            tx_id = result.get("txId", "")
            error = result.get("error", "")

            if error:
                return {
                    "success": False,
                    "tx_id": tx_id,
                    "status": status,
                    "error": error,
                }

            events = result.get("events", [])
            event_summary = [e.get("type", "unknown") for e in events[:5]]

            return {
                "success": True,
                "tx_id": tx_id,
                "status": status,
                "events": event_summary,
                "message": f"Transaction sealed successfully",
                "flowscan_url": self._flowscan_url(tx_id),
            }
        except Exception as e:
            raise RuntimeError(f"Failed to execute transaction: {e}")

    def _flowscan_url(self, tx_id: str) -> str:
        """Generate the correct FlowScan URL based on network."""
        if self.network == "mainnet":
            return f"https://www.flowscan.io/transaction/{tx_id}"
        elif self.network == "testnet":
            return f"https://testnet.flowscan.io/transaction/{tx_id}"
        return f"https://testnet.flowscan.io/transaction/{tx_id}"

    def _tool_get_block_info(self, params: Dict) -> Dict:
        """Get latest block information."""
        script = """
        access(all) fun main(): {String: AnyStruct} {
            let block = getCurrentBlock()
            return {
                "height": block.height,
                "timestamp": block.timestamp,
                "id": block.id
            }
        }
        """
        return self._run_cadence_script(script, [])

    def _tool_get_flow_price(self, params: Dict) -> Dict:
        """Get current FLOW token price from CoinGecko."""
        if not http_requests:
            raise RuntimeError("requests library not installed")

        currency = params.get("currency", "usd").lower()

        try:
            resp = http_requests.get(
                f"https://api.coingecko.com/api/v3/simple/price"
                f"?ids=flow&vs_currencies={currency}",
                headers={"User-Agent": "FlowClaw-Agent/0.1"},
                timeout=10,
            )
            data = resp.json()

            price = data.get("flow", {}).get(currency, "unknown")
            return {
                "token": "FLOW",
                "price": price,
                "currency": currency.upper(),
                "source": "CoinGecko",
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
            }
        except Exception as e:
            raise RuntimeError(f"Failed to fetch FLOW price: {e}")

    def _tool_search_web(self, params: Dict) -> Dict:
        """Search the web using DuckDuckGo HTML search."""
        if not http_requests:
            raise RuntimeError("requests library not installed")

        query = params.get("query", "")
        if not query:
            raise ValueError("'query' parameter is required")

        max_results = min(params.get("max_results", 5), 10)

        try:
            results = []

            # Primary: DuckDuckGo HTML search (works for all query types)
            resp = http_requests.get(
                "https://html.duckduckgo.com/html/",
                params={"q": query},
                headers={
                    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                },
                timeout=15,
            )
            if resp.status_code == 200:
                import re as _re
                # Parse result blocks from DuckDuckGo HTML
                titles = _re.findall(r'class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>', resp.text)
                snippets = _re.findall(r'class="result__snippet"[^>]*>(.*?)</a>', resp.text, _re.DOTALL)

                for i, (url, title) in enumerate(titles[:max_results]):
                    clean_title = _re.sub(r'<[^>]+>', '', title).strip()
                    clean_snippet = _re.sub(r'<[^>]+>', '', snippets[i]).strip() if i < len(snippets) else ""
                    actual_url = url
                    url_match = _re.search(r'uddg=([^&]+)', url)
                    if url_match:
                        import urllib.parse
                        actual_url = urllib.parse.unquote(url_match.group(1))
                    results.append({
                        "title": clean_title[:200],
                        "snippet": clean_snippet[:500],
                        "url": actual_url,
                    })

            # Fallback: also check instant answer API for factual queries
            if len(results) < 2:
                try:
                    resp2 = http_requests.get(
                        "https://api.duckduckgo.com/",
                        params={"q": query, "format": "json", "no_html": 1},
                        headers={"User-Agent": "FlowClaw-Agent/0.1"},
                        timeout=10,
                    )
                    data = resp2.json()
                    if data.get("Abstract"):
                        results.insert(0, {
                            "title": data.get("Heading", ""),
                            "snippet": data["Abstract"][:500],
                            "url": data.get("AbstractURL", ""),
                            "source": data.get("AbstractSource", ""),
                        })
                except Exception:
                    pass  # Instant answer is optional

            return {
                "query": query,
                "results": results[:max_results],
                "total": len(results),
            }
        except Exception as e:
            raise RuntimeError(f"Web search failed: {e}")

    def _tool_spawn_sub_agent(self, params: Dict) -> Dict:
        """Spawn a sub-agent via the callback provided by the API layer."""
        name = params.get("name", "")
        task = params.get("task", "")
        ttl_minutes = params.get("ttl_minutes", 60)

        if not name:
            raise ValueError("'name' parameter is required")
        if not task:
            raise ValueError("'task' parameter is required")

        if not self.spawn_callback:
            raise RuntimeError("Sub-agent spawning not configured")

        try:
            result = self.spawn_callback(
                name=name,
                description=task,
                ttl_seconds=ttl_minutes * 60 if ttl_minutes else None,
            )
            return {
                "spawned": True,
                "agent_id": result.get("agentId"),
                "name": name,
                "task": task,
                "ttl_minutes": ttl_minutes or "no expiry",
                "message": f"Sub-agent '{name}' spawned successfully and is now visible on the Agent Canvas.",
            }
        except Exception as e:
            raise RuntimeError(f"Failed to spawn sub-agent: {e}")

    # -----------------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------------

    def _run_cadence_script(self, script: str, arguments: list) -> Any:
        """
        Execute a Cadence script. Uses REST API if available, CLI fallback otherwise.
        """
        # Try REST API first
        if self.flow_client:
            try:
                return self.flow_client.execute_script(script, arguments)
            except Exception as e:
                logger.warning(f"REST script execution failed, trying CLI: {e}")

        # CLI fallback
        return self._run_cadence_script_cli(script, arguments)

    def _run_cadence_script_cli(self, script: str, arguments: list) -> Any:
        """Execute a Cadence script via Flow CLI (fallback)."""
        import tempfile

        # Write script to temp file
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".cdc", delete=False, dir="/tmp"
        ) as f:
            f.write(script)
            script_path = f.name

        try:
            cmd = ["flow", "scripts", "execute", script_path, "--network", self.network]
            if arguments:
                cmd.extend(["--args-json", json.dumps(arguments)])

            result = subprocess.run(
                cmd, capture_output=True, text=True,
                cwd=self.project_dir, timeout=30,
            )

            if result.returncode == 0:
                output = result.stdout.strip()
                # Parse "Result: <value>"
                for line in output.split("\n"):
                    if line.strip().startswith("Result:"):
                        val = line.split("Result:", 1)[1].strip()
                        try:
                            return json.loads(val)
                        except (json.JSONDecodeError, ValueError):
                            return val
                return output
            else:
                raise RuntimeError(f"Cadence script failed: {result.stderr[:500]}")
        finally:
            import os
            os.unlink(script_path)
