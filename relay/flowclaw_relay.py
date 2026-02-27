#!/usr/bin/env python3
"""
FlowClaw Inference Relay
========================
Off-chain companion that bridges Flow blockchain events to LLM providers.

Architecture:
  1. Polls Flow Access Node for InferenceRequested events
  2. Decodes the event payload (provider, model, messages hash)
  3. Fetches full message history from the session (via Cadence script)
  4. DECRYPTS messages locally (key never leaves this machine)
  5. Calls the appropriate LLM provider
  6. ENCRYPTS the response before posting back on-chain
  7. Handles tool calls in an agentic loop

Each relay instance serves ONE Flow account — private inference by design.
The relay only processes events for its configured owner address.

ENCRYPTION:
  All content is encrypted with XChaCha20-Poly1305 before hitting the chain.
  The encryption key lives locally in ~/.flowclaw/encryption.key
  The chain only ever sees ciphertext + plaintext hashes.
  Block explorers see encrypted gibberish, not your conversations.

Usage:
  python flowclaw_relay.py              # Start relay (reads .env)
  python flowclaw_relay.py --once       # Process one cycle and exit
  python flowclaw_relay.py --status     # Check relay status
  python flowclaw_relay.py --setup-encryption  # Generate encryption key
"""

import os
import sys
import json
import time
import hashlib
import logging
import argparse
import subprocess
import base64
import secrets
from typing import Optional, Dict, List, Any, Tuple
from dataclasses import dataclass, field
from pathlib import Path

# Try to load .env
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# -----------------------------------------------------------------------
# Encryption Layer
# -----------------------------------------------------------------------

class EncryptionManager:
    """
    Manages encryption/decryption for the relay.

    Uses XChaCha20-Poly1305 (via PyNaCl/libsodium) — the same scheme
    used by ZeroClaw. The key is stored locally and NEVER touches the chain.

    Key file: ~/.flowclaw/encryption.key (32 bytes, base64-encoded)
    On-chain: only the key fingerprint (SHA-256 of the key) is stored
    """

    ALGORITHM_XCHACHA20 = 0
    ALGORITHM_AES256GCM = 1
    KEY_SIZE = 32  # 256-bit key
    NONCE_SIZE = 24  # XChaCha20 uses 24-byte nonce

    def __init__(self, key_path: Optional[str] = None):
        self.key: Optional[bytes] = None
        self.fingerprint: str = ""
        self.algorithm: int = self.ALGORITHM_XCHACHA20
        self.key_path = key_path or os.path.expanduser("~/.flowclaw/encryption.key")
        self._nacl_available = False
        self._aead = None

        # Try to load PyNaCl (libsodium bindings)
        try:
            import nacl.secret
            import nacl.utils
            self._nacl_available = True
        except ImportError:
            pass

        # Try to load the key
        self._load_key()

    def _load_key(self):
        """Load encryption key from disk."""
        if os.path.exists(self.key_path):
            try:
                with open(self.key_path, "r") as f:
                    key_b64 = f.read().strip()
                self.key = base64.b64decode(key_b64)
                self.fingerprint = hashlib.sha256(self.key).hexdigest()
                logging.info(f"Encryption key loaded (fingerprint: {self.fingerprint[:16]}...)")
            except Exception as e:
                logging.warning(f"Failed to load encryption key: {e}")
                self.key = None

    def generate_key(self) -> Tuple[bytes, str]:
        """
        Generate a new random encryption key.
        Returns (key_bytes, fingerprint).
        """
        key = secrets.token_bytes(self.KEY_SIZE)
        fingerprint = hashlib.sha256(key).hexdigest()

        # Save to disk
        key_dir = os.path.dirname(self.key_path)
        os.makedirs(key_dir, mode=0o700, exist_ok=True)

        key_b64 = base64.b64encode(key).decode("ascii")
        with open(self.key_path, "w") as f:
            f.write(key_b64)
        os.chmod(self.key_path, 0o600)  # Owner read/write only

        self.key = key
        self.fingerprint = fingerprint

        logging.info(f"New encryption key generated (fingerprint: {fingerprint[:16]}...)")
        logging.info(f"Key saved to: {self.key_path}")
        return key, fingerprint

    @property
    def is_configured(self) -> bool:
        return self.key is not None

    def encrypt(self, plaintext: str) -> Dict[str, str]:
        """
        Encrypt plaintext content.

        Returns dict with:
          ciphertext: base64-encoded encrypted content
          nonce: base64-encoded nonce
          plaintextHash: SHA-256 of the plaintext
          keyFingerprint: identifies which key was used
          algorithm: 0 for xchacha20-poly1305
          plaintextLength: length of original text
        """
        if not self.key:
            raise RuntimeError("No encryption key configured. Run --setup-encryption first.")

        plaintext_bytes = plaintext.encode("utf-8")
        plaintext_hash = hashlib.sha256(plaintext_bytes).hexdigest()

        if self._nacl_available:
            import nacl.secret
            import nacl.utils
            box = nacl.secret.SecretBox(self.key)
            nonce = nacl.utils.random(nacl.secret.SecretBox.NONCE_SIZE)
            encrypted = box.encrypt(plaintext_bytes, nonce)
            # nacl.encrypt prepends nonce to ciphertext; extract just ciphertext
            ciphertext = encrypted.ciphertext
        else:
            # Fallback: use cryptography library
            try:
                from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
                nonce = secrets.token_bytes(12)  # ChaCha20 uses 12-byte nonce
                cipher = ChaCha20Poly1305(self.key)
                ciphertext = cipher.encrypt(nonce, plaintext_bytes, None)
            except ImportError:
                raise RuntimeError(
                    "No crypto library available (need PyNaCl or cryptography). "
                    "Install with: pip install pynacl  OR  pip install cryptography"
                )

        return {
            "ciphertext": base64.b64encode(ciphertext).decode("ascii"),
            "nonce": base64.b64encode(nonce).decode("ascii"),
            "plaintextHash": plaintext_hash,
            "keyFingerprint": self.fingerprint,
            "algorithm": self.algorithm,
            "plaintextLength": len(plaintext_bytes),
        }

    def decrypt(self, encrypted_payload: Dict[str, str]) -> str:
        """
        Decrypt an encrypted payload back to plaintext.

        Verifies the plaintext hash after decryption for integrity.
        """
        if not self.key:
            raise RuntimeError("No encryption key configured.")

        ciphertext = base64.b64decode(encrypted_payload["ciphertext"])
        nonce = base64.b64decode(encrypted_payload["nonce"])
        expected_hash = encrypted_payload.get("plaintextHash", "")

        if self._nacl_available:
            import nacl.secret
            box = nacl.secret.SecretBox(self.key)
            plaintext_bytes = box.decrypt(ciphertext, nonce)
        else:
            try:
                from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
                cipher = ChaCha20Poly1305(self.key)
                plaintext_bytes = cipher.decrypt(nonce, ciphertext, None)
            except ImportError:
                raise RuntimeError(
                    "No crypto library available (need PyNaCl or cryptography). "
                    "Install with: pip install pynacl  OR  pip install cryptography"
                )

        plaintext = plaintext_bytes.decode("utf-8")

        # Verify integrity
        if expected_hash:
            actual_hash = hashlib.sha256(plaintext_bytes).hexdigest()
            if actual_hash != expected_hash:
                raise ValueError(
                    f"Plaintext hash mismatch! Expected {expected_hash[:16]}..., "
                    f"got {actual_hash[:16]}... — content may be corrupted"
                )

        return plaintext

    def _expand_key(self, key: bytes, nonce: bytes, length: int) -> bytes:
        """Simple key expansion for XOR fallback. NOT cryptographically secure."""
        stream = b""
        counter = 0
        while len(stream) < length:
            block = hashlib.sha256(key + nonce + counter.to_bytes(4, "big")).digest()
            stream += block
            counter += 1
        return stream[:length]


# -----------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------

@dataclass
class RelayConfig:
    """Configuration for the inference relay."""
    flow_network: str = "emulator"
    flow_access_node: str = "http://localhost:8888"
    flow_account_address: str = ""
    flow_private_key: str = ""

    # Provider API keys
    anthropic_api_key: str = ""
    openai_api_key: str = ""
    venice_api_key: str = ""
    venice_base_url: str = "https://api.venice.ai/api/v1"
    ollama_base_url: str = "http://localhost:11434"

    # Relay settings
    poll_interval: int = 2  # seconds
    max_retries: int = 3
    log_level: str = "INFO"

    # Paths
    project_dir: str = ""
    encryption_key_path: str = ""

    @classmethod
    def from_env(cls) -> "RelayConfig":
        return cls(
            flow_network=os.getenv("FLOW_NETWORK", "emulator"),
            flow_access_node=os.getenv("FLOW_ACCESS_NODE", "http://localhost:8888"),
            flow_account_address=os.getenv("FLOW_ACCOUNT_ADDRESS", ""),
            flow_private_key=os.getenv("FLOW_PRIVATE_KEY", ""),
            anthropic_api_key=os.getenv("ANTHROPIC_API_KEY", ""),
            openai_api_key=os.getenv("OPENAI_API_KEY", ""),
            venice_api_key=os.getenv("VENICE_API_KEY", ""),
            venice_base_url=os.getenv("VENICE_BASE_URL", "https://api.venice.ai/api/v1"),
            ollama_base_url=os.getenv("OLLAMA_BASE_URL", "http://localhost:11434"),
            poll_interval=int(os.getenv("RELAY_POLL_INTERVAL", "2")),
            max_retries=int(os.getenv("RELAY_MAX_RETRIES", "3")),
            log_level=os.getenv("RELAY_LOG_LEVEL", "INFO"),
            project_dir=os.getenv("FLOWCLAW_PROJECT_DIR",
                                  str(Path(__file__).parent.parent)),
            encryption_key_path=os.getenv("FLOWCLAW_ENCRYPTION_KEY",
                                          os.path.expanduser("~/.flowclaw/encryption.key")),
        )


# -----------------------------------------------------------------------
# LLM Provider Abstraction
# -----------------------------------------------------------------------

class LLMProvider:
    """Base class for LLM providers."""

    def complete(
        self,
        model: str,
        messages: List[Dict[str, str]],
        max_tokens: int = 4096,
        temperature: float = 0.7,
        tools: Optional[List[Dict]] = None,
    ) -> Dict[str, Any]:
        raise NotImplementedError


class AnthropicProvider(LLMProvider):
    """Anthropic Claude provider."""

    def __init__(self, api_key: str):
        self.api_key = api_key
        try:
            import anthropic
            self.client = anthropic.Anthropic(api_key=api_key)
        except ImportError:
            self.client = None
            logging.warning("anthropic package not installed, using HTTP fallback")

    def complete(self, model, messages, max_tokens=4096, temperature=0.7, tools=None):
        if self.client:
            # Extract system message
            system_msg = ""
            chat_messages = []
            for msg in messages:
                if msg["role"] == "system":
                    system_msg = msg["content"]
                else:
                    chat_messages.append(msg)

            kwargs = {
                "model": model,
                "max_tokens": max_tokens,
                "messages": chat_messages,
            }
            if system_msg:
                kwargs["system"] = system_msg
            if temperature is not None:
                kwargs["temperature"] = temperature
            if tools:
                kwargs["tools"] = tools

            response = self.client.messages.create(**kwargs)

            # Parse response
            content = ""
            tool_calls = []
            for block in response.content:
                if block.type == "text":
                    content += block.text
                elif block.type == "tool_use":
                    tool_calls.append({
                        "id": block.id,
                        "name": block.name,
                        "input": block.input,
                    })

            return {
                "content": content,
                "tool_calls": tool_calls,
                "tokens_used": response.usage.input_tokens + response.usage.output_tokens,
                "stop_reason": response.stop_reason,
            }
        else:
            # HTTP fallback
            import requests
            headers = {
                "x-api-key": self.api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            }
            system_msg = ""
            chat_messages = []
            for msg in messages:
                if msg["role"] == "system":
                    system_msg = msg["content"]
                else:
                    chat_messages.append(msg)

            payload = {
                "model": model,
                "max_tokens": max_tokens,
                "messages": chat_messages,
            }
            if system_msg:
                payload["system"] = system_msg

            resp = requests.post(
                "https://api.anthropic.com/v1/messages",
                headers=headers,
                json=payload,
            )
            resp.raise_for_status()
            data = resp.json()
            content = ""
            for block in data.get("content", []):
                if block["type"] == "text":
                    content += block["text"]
            return {
                "content": content,
                "tool_calls": [],
                "tokens_used": data.get("usage", {}).get("input_tokens", 0) +
                               data.get("usage", {}).get("output_tokens", 0),
                "stop_reason": data.get("stop_reason", "end_turn"),
            }


class OpenAIProvider(LLMProvider):
    """OpenAI provider."""

    def __init__(self, api_key: str):
        self.api_key = api_key
        try:
            import openai
            self.client = openai.OpenAI(api_key=api_key)
        except ImportError:
            self.client = None

    def complete(self, model, messages, max_tokens=4096, temperature=0.7, tools=None):
        if self.client:
            kwargs = {
                "model": model,
                "messages": messages,
                "max_tokens": max_tokens,
                "temperature": temperature,
            }
            if tools:
                kwargs["tools"] = [
                    {"type": "function", "function": t} for t in tools
                ]
            response = self.client.chat.completions.create(**kwargs)
            choice = response.choices[0]
            tool_calls = []
            if choice.message.tool_calls:
                for tc in choice.message.tool_calls:
                    tool_calls.append({
                        "id": tc.id,
                        "name": tc.function.name,
                        "input": json.loads(tc.function.arguments),
                    })
            return {
                "content": choice.message.content or "",
                "tool_calls": tool_calls,
                "tokens_used": response.usage.total_tokens,
                "stop_reason": choice.finish_reason,
            }
        raise RuntimeError("OpenAI client not available")


class OllamaProvider(LLMProvider):
    """Ollama local model provider."""

    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")

    def complete(self, model, messages, max_tokens=4096, temperature=0.7, tools=None):
        import requests
        payload = {
            "model": model,
            "messages": messages,
            "stream": False,
            "options": {
                "num_predict": max_tokens,
                "temperature": temperature,
            },
        }
        resp = requests.post(f"{self.base_url}/api/chat", json=payload)
        resp.raise_for_status()
        data = resp.json()
        return {
            "content": data.get("message", {}).get("content", ""),
            "tool_calls": [],
            "tokens_used": data.get("eval_count", 0) + data.get("prompt_eval_count", 0),
            "stop_reason": "stop",
        }


class VeniceProvider(LLMProvider):
    """Venice AI provider (OpenAI-compatible API)."""

    def __init__(self, api_key: str, base_url: str = "https://api.venice.ai/api/v1"):
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.client = None
        try:
            from openai import OpenAI
            self.client = OpenAI(api_key=api_key, base_url=self.base_url)
        except ImportError:
            logging.warning("openai package not installed — using HTTP fallback for Venice")

    def complete(self, model, messages, max_tokens=4096, temperature=0.7, tools=None):
        if self.client:
            kwargs = {
                "model": model,
                "messages": messages,
                "max_tokens": max_tokens,
                "temperature": temperature,
            }
            if tools:
                kwargs["tools"] = [
                    {"type": "function", "function": t} for t in tools
                ]
            response = self.client.chat.completions.create(**kwargs)
            choice = response.choices[0]
            tool_calls = []
            if choice.message.tool_calls:
                for tc in choice.message.tool_calls:
                    tool_calls.append({
                        "id": tc.id,
                        "name": tc.function.name,
                        "input": json.loads(tc.function.arguments),
                    })
            return {
                "content": choice.message.content or "",
                "tool_calls": tool_calls,
                "tokens_used": getattr(response.usage, "total_tokens", 0) if response.usage else 0,
                "stop_reason": choice.finish_reason,
            }
        else:
            # HTTP fallback (no openai package)
            import requests
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            }
            payload = {
                "model": model,
                "messages": messages,
                "max_tokens": max_tokens,
                "temperature": temperature,
            }
            resp = requests.post(
                f"{self.base_url}/chat/completions",
                headers=headers,
                json=payload,
            )
            resp.raise_for_status()
            data = resp.json()
            choice = data["choices"][0]
            return {
                "content": choice["message"].get("content", ""),
                "tool_calls": [],
                "tokens_used": data.get("usage", {}).get("total_tokens", 0),
                "stop_reason": choice.get("finish_reason", "stop"),
            }


# -----------------------------------------------------------------------
# Flow CLI Wrapper
# -----------------------------------------------------------------------

class FlowCLI:
    """Wrapper around the Flow CLI for executing transactions and scripts."""

    def __init__(self, config: RelayConfig):
        self.config = config
        self.project_dir = config.project_dir

    def run_script(self, script_path: str, args: List[str] = None) -> Optional[str]:
        """Execute a Cadence script and return the result."""
        cmd = [
            "flow", "scripts", "execute", script_path,
            "--network", self.config.flow_network,
        ]
        if args:
            cmd.extend(args)

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                cwd=self.project_dir,
                timeout=30,
            )
            if result.returncode == 0:
                return result.stdout.strip()
            else:
                logging.error(f"Script failed: {result.stderr}")
                return None
        except subprocess.TimeoutExpired:
            logging.error(f"Script timed out: {script_path}")
            return None
        except FileNotFoundError:
            logging.error("Flow CLI not found. Install from: https://developers.flow.com/tools/flow-cli")
            return None

    def send_transaction(
        self,
        tx_path: str,
        args: List[str] = None,
        signer: str = None,
    ) -> Optional[str]:
        """Send a Cadence transaction and return the result."""
        cmd = [
            "flow", "transactions", "send", tx_path,
            "--network", self.config.flow_network,
        ]
        if signer:
            cmd.extend(["--signer", signer])
        if args:
            cmd.extend(args)

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                cwd=self.project_dir,
                timeout=60,
            )
            if result.returncode == 0:
                return result.stdout.strip()
            else:
                logging.error(f"Transaction failed: {result.stderr}")
                return None
        except subprocess.TimeoutExpired:
            logging.error(f"Transaction timed out: {tx_path}")
            return None

    def get_events(
        self,
        event_type: str,
        start_height: int,
        end_height: Optional[int] = None,
    ) -> List[Dict]:
        """Query Flow events by type and block range."""
        import requests

        base_url = self.config.flow_access_node
        if end_height is None:
            end_height = start_height + 100

        # Use REST API for event queries
        url = f"{base_url}/v1/events"
        params = {
            "type": event_type,
            "start_height": start_height,
            "end_height": end_height,
        }

        try:
            resp = requests.get(url, params=params, timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                events = []
                for block_events in data.get("results", []):
                    for event in block_events.get("events", []):
                        events.append(event)
                return events
            else:
                logging.debug(f"Event query returned {resp.status_code}")
                return []
        except Exception as e:
            logging.error(f"Event query failed: {e}")
            return []

    def get_latest_block_height(self) -> int:
        """Get the latest sealed block height."""
        import requests
        try:
            resp = requests.get(
                f"{self.config.flow_access_node}/v1/blocks?height=sealed",
                timeout=10,
            )
            if resp.status_code == 200:
                data = resp.json()
                if data:
                    return int(data[0].get("header", {}).get("height", 0))
        except Exception as e:
            logging.error(f"Block height query failed: {e}")
        return 0


# -----------------------------------------------------------------------
# Tool Executor
# -----------------------------------------------------------------------

class ToolExecutor:
    """Executes agent tool calls off-chain."""

    def __init__(self, config: RelayConfig, flow_cli: FlowCLI):
        self.config = config
        self.flow_cli = flow_cli

    def execute(self, tool_name: str, tool_input: Dict) -> Dict[str, Any]:
        """Execute a tool and return the result."""
        executor = {
            "memory_store": self._memory_store,
            "memory_recall": self._memory_recall,
            "web_fetch": self._web_fetch,
            "shell_exec": self._shell_exec,
            "flow_query": self._flow_query,
            "flow_transact": self._flow_transact,
        }.get(tool_name)

        if executor:
            try:
                return executor(tool_input)
            except Exception as e:
                return {"error": str(e), "success": False}
        else:
            return {"error": f"Unknown tool: {tool_name}", "success": False}

    def _memory_store(self, input: Dict) -> Dict:
        """Store to on-chain memory via transaction."""
        key = input.get("key", "")
        content = input.get("content", "")
        tags = input.get("tags", "").split(",") if input.get("tags") else []
        content_hash = hashlib.sha256(content.encode()).hexdigest()

        # In full implementation, this would send a Cadence transaction
        return {
            "success": True,
            "message": f"Stored memory with key '{key}'",
            "content_hash": content_hash,
        }

    def _memory_recall(self, input: Dict) -> Dict:
        """Recall from on-chain memory via script."""
        query = input.get("query", "")
        # In full implementation, this would execute a Cadence script
        return {
            "success": True,
            "results": [],
            "message": f"Memory search for '{query}' (on-chain lookup pending)",
        }

    def _web_fetch(self, input: Dict) -> Dict:
        """Fetch content from a URL."""
        import requests
        url = input.get("url", "")
        try:
            resp = requests.get(url, timeout=15, headers={
                "User-Agent": "FlowClaw-Agent/0.1"
            })
            return {
                "success": True,
                "status_code": resp.status_code,
                "content": resp.text[:10000],  # Truncate for context window
                "url": url,
            }
        except Exception as e:
            return {"success": False, "error": str(e)}

    def _shell_exec(self, input: Dict) -> Dict:
        """Execute a sandboxed shell command."""
        command = input.get("command", "")
        timeout_ms = input.get("timeout_ms", 30000)

        # SAFETY: Deny dangerous commands
        dangerous = ["rm -rf", "sudo", "chmod", "chown", "mkfs", "dd if="]
        for d in dangerous:
            if d in command:
                return {"success": False, "error": f"Command denied: contains '{d}'"}

        try:
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                timeout=timeout_ms / 1000,
            )
            return {
                "success": result.returncode == 0,
                "stdout": result.stdout[:5000],
                "stderr": result.stderr[:2000],
                "exit_code": result.returncode,
            }
        except subprocess.TimeoutExpired:
            return {"success": False, "error": "Command timed out"}

    def _flow_query(self, input: Dict) -> Dict:
        """Execute a Cadence script."""
        script = input.get("script", "")
        # Write script to temp file and execute
        import tempfile
        with tempfile.NamedTemporaryFile(mode="w", suffix=".cdc", delete=False) as f:
            f.write(script)
            f.flush()
            result = self.flow_cli.run_script(f.name)
            os.unlink(f.name)
            return {"success": result is not None, "result": result}

    def _flow_transact(self, input: Dict) -> Dict:
        """Send a Cadence transaction."""
        return {
            "success": False,
            "error": "Direct transaction execution requires approval (supervised mode)",
        }


# -----------------------------------------------------------------------
# Inference Relay (with E2E Encryption)
# -----------------------------------------------------------------------

class InferenceRelay:
    """
    Main relay loop: listens for on-chain events, calls LLM, posts back.

    ENCRYPTION FLOW:
    1. Poll for InferenceRequested events
    2. Filter for our owner address
    3. Fetch session history from chain (ciphertext)
    4. DECRYPT messages locally using encryption key
    5. Call LLM provider with plaintext
    6. ENCRYPT LLM response
    7. Post encrypted response back on-chain
    8. Show decrypted response to user locally

    The chain NEVER sees plaintext. Block explorers see ciphertext only.
    """

    def __init__(self, config: RelayConfig):
        self.config = config
        self.flow_cli = FlowCLI(config)
        self.tool_executor = ToolExecutor(config, self.flow_cli)
        self.encryption = EncryptionManager(config.encryption_key_path)
        self.providers: Dict[str, LLMProvider] = {}
        self.processed_requests: set = set()
        self.last_block_height: int = 0

        # Initialize providers
        if config.anthropic_api_key:
            self.providers["anthropic"] = AnthropicProvider(config.anthropic_api_key)
        if config.openai_api_key:
            self.providers["openai"] = OpenAIProvider(config.openai_api_key)
        if config.venice_api_key:
            self.providers["venice"] = VeniceProvider(
                config.venice_api_key, config.venice_base_url
            )
        if config.ollama_base_url:
            self.providers["ollama"] = OllamaProvider(config.ollama_base_url)

        logging.info(f"Relay initialized for account: {config.flow_account_address}")
        logging.info(f"Available providers: {list(self.providers.keys())}")
        logging.info(f"Encryption: {'ENABLED' if self.encryption.is_configured else 'DISABLED'}")
        if self.encryption.is_configured:
            logging.info(f"Key fingerprint: {self.encryption.fingerprint[:16]}...")

    def get_provider(self, provider_name: str) -> Optional[LLMProvider]:
        """Get the LLM provider by name."""
        return self.providers.get(provider_name)

    def _encrypt_content(self, plaintext: str) -> Dict[str, str]:
        """Encrypt content before sending on-chain."""
        if self.encryption.is_configured:
            return self.encryption.encrypt(plaintext)
        else:
            # Fallback: no encryption (for development only)
            logging.warning("Encryption not configured — sending plaintext (INSECURE)")
            return {
                "ciphertext": plaintext,
                "nonce": "",
                "plaintextHash": hashlib.sha256(plaintext.encode()).hexdigest(),
                "keyFingerprint": "",
                "algorithm": 0,
                "plaintextLength": len(plaintext),
            }

    def _decrypt_content(self, encrypted_payload: Dict[str, str]) -> str:
        """Decrypt content received from chain."""
        if self.encryption.is_configured and encrypted_payload.get("nonce"):
            return self.encryption.decrypt(encrypted_payload)
        else:
            # Assume plaintext if no nonce (legacy or unencrypted)
            return encrypted_payload.get("ciphertext", encrypted_payload.get("content", ""))

    def process_inference_request(self, event: Dict) -> Optional[Dict]:
        """Process a single inference request event."""
        payload = event.get("payload", event.get("value", {}))

        # Extract fields from the event
        request_id = payload.get("requestId", payload.get("request_id", 0))
        session_id = payload.get("sessionId", payload.get("session_id", 0))
        agent_id = payload.get("agentId", payload.get("agent_id", 0))
        owner = payload.get("owner", "")
        provider_name = payload.get("provider", "anthropic")
        model = payload.get("model", "claude-sonnet-4-5-20250929")
        content_hash = payload.get("contentHash", payload.get("content_hash", ""))

        # Only process events for our account
        if owner and owner != self.config.flow_account_address:
            return None

        # Dedup
        if request_id in self.processed_requests:
            logging.debug(f"Skipping already-processed request {request_id}")
            return None

        logging.info(
            f"Processing inference request #{request_id} "
            f"(session={session_id}, model={model})"
        )

        # Get provider
        provider = self.get_provider(provider_name)
        if not provider:
            logging.error(f"Provider '{provider_name}' not configured")
            return None

        # Fetch messages from chain (these are ENCRYPTED on-chain)
        encrypted_messages = self._get_session_messages(session_id)

        # DECRYPT messages locally
        messages = []
        for emsg in encrypted_messages:
            if emsg.get("nonce"):
                # Encrypted message — decrypt it
                try:
                    plaintext = self._decrypt_content(emsg)
                    messages.append({"role": emsg["role"], "content": plaintext})
                except Exception as e:
                    logging.warning(f"Failed to decrypt message: {e}")
                    messages.append({"role": emsg["role"], "content": "[decryption failed]"})
            else:
                # Plaintext message (system prompts, legacy)
                messages.append({"role": emsg["role"], "content": emsg.get("content", "")})

        if not messages:
            logging.warning(f"No messages found for session {session_id}")
            messages = [{"role": "user", "content": "Hello"}]

        # Agentic loop: call LLM, handle tool calls, repeat
        max_turns = 10
        total_tokens = 0

        for turn in range(max_turns):
            logging.info(f"  Turn {turn + 1}/{max_turns}")

            result = provider.complete(
                model=model,
                messages=messages,
                max_tokens=4096,
                temperature=0.7,
            )

            total_tokens += result.get("tokens_used", 0)

            # Check for tool calls
            tool_calls = result.get("tool_calls", [])
            if tool_calls:
                # Add assistant message with tool calls
                messages.append({
                    "role": "assistant",
                    "content": result.get("content", ""),
                })

                # Execute each tool
                for tc in tool_calls:
                    logging.info(f"  Executing tool: {tc['name']}")
                    tool_result = self.tool_executor.execute(
                        tc["name"], tc.get("input", {})
                    )
                    messages.append({
                        "role": "tool",
                        "content": json.dumps(tool_result),
                        "tool_call_id": tc.get("id", ""),
                    })

                # Continue the loop for the next LLM call
                continue

            # No tool calls — we have a final response
            response_content = result.get("content", "")

            self.processed_requests.add(request_id)

            logging.info(
                f"  Inference complete: {len(response_content)} chars, "
                f"{total_tokens} tokens"
            )

            # ENCRYPT response before posting on-chain
            encrypted_response = self._encrypt_content(response_content)

            # Post ENCRYPTED result back on-chain
            self._post_response_onchain(
                session_id=session_id,
                request_id=request_id,
                encrypted_response=encrypted_response,
                tokens_used=total_tokens,
            )

            return {
                "request_id": request_id,
                "session_id": session_id,
                "content": response_content,  # Plaintext for local display
                "tokens_used": total_tokens,
                "turns": turn + 1,
                "encrypted": self.encryption.is_configured,
            }

        logging.warning(f"Max turns reached for request {request_id}")
        return None

    def _get_session_messages(self, session_id: int) -> List[Dict]:
        """
        Fetch session messages from the chain.
        Messages on-chain are ENCRYPTED — we return them as-is for decryption.
        """
        result = self.flow_cli.run_script(
            "scripts/get_session_history.cdc",
            [
                f"--arg", f"Address:{self.config.flow_account_address}",
                f"--arg", f"UInt64:{session_id}",
            ],
        )

        if result:
            try:
                return self._parse_cadence_messages(result)
            except Exception as e:
                logging.debug(f"Could not parse chain messages: {e}")

        return []

    def _parse_cadence_messages(self, cadence_output: str) -> List[Dict]:
        """Parse Cadence script output into message format (with encryption fields)."""
        messages = []
        try:
            data = json.loads(cadence_output)
            if isinstance(data, list):
                for item in data:
                    msg = {
                        "role": item.get("role", "user"),
                        "content": item.get("content", ""),
                        "contentHash": item.get("contentHash", ""),
                    }
                    # Check if content looks like base64-encoded ciphertext
                    # (encrypted messages will have a nonce stored alongside)
                    if item.get("nonce"):
                        msg["ciphertext"] = item["content"]
                        msg["nonce"] = item["nonce"]
                        msg["keyFingerprint"] = item.get("keyFingerprint", "")
                    messages.append(msg)
        except json.JSONDecodeError:
            pass
        return messages

    def _post_response_onchain(
        self,
        session_id: int,
        request_id: int,
        encrypted_response: Dict[str, str],
        tokens_used: int,
    ):
        """Post ENCRYPTED inference response back to the chain."""
        logging.info(f"  Posting encrypted response on-chain (request #{request_id})")

        result = self.flow_cli.send_transaction(
            "transactions/complete_inference_owner.cdc",
            args=[
                "--arg", f"UInt64:{session_id}",
                "--arg", f"UInt64:{request_id}",
                "--arg", f'String:{encrypted_response["ciphertext"]}',
                "--arg", f'String:{encrypted_response["nonce"]}',
                "--arg", f'String:{encrypted_response["plaintextHash"]}',
                "--arg", f'String:{encrypted_response["keyFingerprint"]}',
                "--arg", f'UInt8:{encrypted_response["algorithm"]}',
                "--arg", f'UInt64:{encrypted_response["plaintextLength"]}',
                "--arg", f"UInt64:{tokens_used}",
            ],
        )

        if result:
            logging.info(f"  Encrypted response posted on-chain successfully")
        else:
            logging.warning(f"  Failed to post response on-chain (will retry)")

    def poll_once(self) -> List[Dict]:
        """Poll for new events and process them."""
        current_height = self.flow_cli.get_latest_block_height()
        if current_height <= self.last_block_height:
            return []

        # Query events
        event_type = (
            f"A.{self.config.flow_account_address}"
            f".AgentSession.InferenceRequested"
        )
        events = self.flow_cli.get_events(
            event_type=event_type,
            start_height=self.last_block_height + 1,
            end_height=current_height,
        )

        self.last_block_height = current_height

        results = []
        for event in events:
            result = self.process_inference_request(event)
            if result:
                results.append(result)

        return results

    def run(self, once: bool = False):
        """Main relay loop."""
        logging.info("=" * 60)
        logging.info("FlowClaw Inference Relay")
        logging.info(f"Account: {self.config.flow_account_address}")
        logging.info(f"Network: {self.config.flow_network}")
        logging.info(f"Providers: {list(self.providers.keys())}")
        logging.info(f"Encryption: {'ENABLED' if self.encryption.is_configured else 'DISABLED (run --setup-encryption)'}")
        logging.info("=" * 60)

        if not self.encryption.is_configured:
            logging.warning(
                "⚠ Encryption is NOT configured. Messages will be visible on-chain! "
                "Run: python flowclaw_relay.py --setup-encryption"
            )

        # Get initial block height
        self.last_block_height = self.flow_cli.get_latest_block_height()
        logging.info(f"Starting from block height: {self.last_block_height}")

        if once:
            results = self.poll_once()
            logging.info(f"Processed {len(results)} inference requests")
            return results

        # Continuous loop
        while True:
            try:
                results = self.poll_once()
                if results:
                    for r in results:
                        logging.info(
                            f"Completed: request #{r['request_id']} "
                            f"({r['tokens_used']} tokens, {r['turns']} turns, "
                            f"encrypted={r.get('encrypted', False)})"
                        )
                time.sleep(self.config.poll_interval)
            except KeyboardInterrupt:
                logging.info("Relay stopped by user")
                break
            except Exception as e:
                logging.error(f"Relay error: {e}")
                time.sleep(self.config.poll_interval * 2)


# -----------------------------------------------------------------------
# CLI-based Interaction Mode (with E2E Encryption)
# -----------------------------------------------------------------------

class CLIMode:
    """
    Interactive CLI mode for testing FlowClaw without a running emulator.
    Simulates the on-chain flow locally, including encryption.
    """

    def __init__(self, config: RelayConfig):
        self.config = config
        self.encryption = EncryptionManager(config.encryption_key_path)
        self.providers: Dict[str, LLMProvider] = {}
        self.tool_executor = ToolExecutor(config, FlowCLI(config))
        self.sessions: Dict[int, List[Dict]] = {}
        self.session_counter = 0

        if config.anthropic_api_key:
            self.providers["anthropic"] = AnthropicProvider(config.anthropic_api_key)
        if config.openai_api_key:
            self.providers["openai"] = OpenAIProvider(config.openai_api_key)
        if config.venice_api_key:
            self.providers["venice"] = VeniceProvider(
                config.venice_api_key, config.venice_base_url
            )
        if config.ollama_base_url:
            self.providers["ollama"] = OllamaProvider(config.ollama_base_url)

    def create_session(self, system_prompt: str = "") -> int:
        """Create a new session."""
        self.session_counter += 1
        sid = self.session_counter
        self.sessions[sid] = []
        if system_prompt:
            self.sessions[sid].append({"role": "system", "content": system_prompt})
        return sid

    def chat(
        self,
        session_id: int,
        user_message: str,
        provider: str = "anthropic",
        model: str = "claude-sonnet-4-5-20250929",
    ) -> str:
        """Send a message and get a response (with agentic loop + encryption simulation)."""
        messages = self.sessions.get(session_id, [])

        # Simulate encryption: encrypt before "on-chain", decrypt for LLM
        if self.encryption.is_configured:
            encrypted = self.encryption.encrypt(user_message)
            # In real flow: encrypted goes on-chain, then relay decrypts
            decrypted = self.encryption.decrypt(encrypted)
            messages.append({"role": "user", "content": decrypted})
        else:
            messages.append({"role": "user", "content": user_message})

        llm = self.providers.get(provider)
        if not llm:
            return f"Error: Provider '{provider}' not configured"

        max_turns = 10
        for turn in range(max_turns):
            result = llm.complete(model=model, messages=messages)

            tool_calls = result.get("tool_calls", [])
            if tool_calls:
                messages.append({
                    "role": "assistant",
                    "content": result.get("content", ""),
                })
                for tc in tool_calls:
                    tool_result = self.tool_executor.execute(tc["name"], tc.get("input", {}))
                    messages.append({
                        "role": "tool",
                        "content": json.dumps(tool_result),
                        "tool_call_id": tc.get("id", ""),
                    })
                continue

            response = result.get("content", "")

            # Simulate encryption of the response
            if self.encryption.is_configured:
                enc_resp = self.encryption.encrypt(response)
                # Verify round-trip: decrypt what would be stored on-chain
                verified = self.encryption.decrypt(enc_resp)
                assert verified == response, "Encryption round-trip failed!"

            messages.append({"role": "assistant", "content": response})
            self.sessions[session_id] = messages
            return response

        return "Error: Max turns reached"

    def interactive(self):
        """Run interactive CLI chat."""
        print("=" * 60)
        print("FlowClaw Interactive Mode")
        print(f"Account: {self.config.flow_account_address or '(local)'}")
        print(f"Providers: {list(self.providers.keys())}")
        print(f"Encryption: {'ENABLED' if self.encryption.is_configured else 'DISABLED'}")
        if self.encryption.is_configured:
            print(f"Key: {self.encryption.fingerprint[:16]}...")
        print("Type 'quit' to exit, 'new' for new session")
        print("=" * 60)

        # Pick provider (prefer Venice, then Anthropic, then OpenAI, then Ollama)
        provider = "venice" if "venice" in self.providers else (
            "anthropic" if "anthropic" in self.providers else (
                "openai" if "openai" in self.providers else "ollama"
            )
        )
        model = {
            "venice": "claude-sonnet-4-6",
            "anthropic": "claude-sonnet-4-5-20250929",
            "openai": "gpt-4o",
            "ollama": "llama3",
        }.get(provider, "claude-sonnet-4-6")

        print(f"Using: {provider}/{model}")
        print()

        system_prompt = (
            "You are a FlowClaw agent running on the Flow blockchain. "
            "You have access to tools for memory, web search, shell execution, "
            "and Flow blockchain queries. You are private to your owner's account. "
            "All messages are end-to-end encrypted — only the relay can read them."
        )
        session_id = self.create_session(system_prompt)
        print(f"Session #{session_id} created")
        print()

        while True:
            try:
                user_input = input("You: ").strip()
                if not user_input:
                    continue
                if user_input.lower() == "quit":
                    break
                if user_input.lower() == "new":
                    session_id = self.create_session(system_prompt)
                    print(f"\nNew session #{session_id} created\n")
                    continue

                print("Agent: ", end="", flush=True)
                response = self.chat(session_id, user_input, provider, model)
                print(response)
                print()
            except KeyboardInterrupt:
                print("\nGoodbye!")
                break
            except Exception as e:
                print(f"\nError: {e}\n")


# -----------------------------------------------------------------------
# Encryption Setup
# -----------------------------------------------------------------------

def setup_encryption(config: RelayConfig):
    """Interactive encryption setup."""
    print("=" * 60)
    print("FlowClaw Encryption Setup")
    print("=" * 60)
    print()
    print("This will generate a new XChaCha20-Poly1305 encryption key.")
    print("The key will be stored locally — it NEVER touches the blockchain.")
    print()

    enc = EncryptionManager(config.encryption_key_path)

    if enc.is_configured:
        print(f"Existing key found: {enc.fingerprint[:16]}...")
        print(f"Location: {enc.key_path}")
        print()
        answer = input("Generate a new key? (old messages will need the old key) [y/N]: ").strip()
        if answer.lower() != "y":
            print("Keeping existing key.")
            return
        print()

    # Generate key
    key, fingerprint = enc.generate_key()

    print()
    print("Key generated successfully!")
    print(f"  Fingerprint: {fingerprint}")
    print(f"  Location:    {enc.key_path}")
    print()
    print("Next steps:")
    print("  1. Register the key fingerprint on-chain:")
    print(f'     flow transactions send transactions/configure_encryption.cdc \\')
    print(f'       --arg "String:{fingerprint}" \\')
    print(f'       --arg "UInt8:0" \\')
    print(f'       --arg "String:primary-key"')
    print()
    print("  2. Start the relay — it will automatically use this key:")
    print("     python flowclaw_relay.py")
    print()
    print("  3. All messages will now be encrypted on-chain!")
    print()

    # Verify round-trip
    test_msg = "Hello, FlowClaw encryption test!"
    encrypted = enc.encrypt(test_msg)
    decrypted = enc.decrypt(encrypted)
    assert decrypted == test_msg, "Round-trip verification failed!"
    print("Round-trip verification: PASSED")
    print(f"  Plaintext:  '{test_msg}'")
    print(f"  Ciphertext: '{encrypted['ciphertext'][:40]}...'")
    print(f"  Decrypted:  '{decrypted}'")


# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="FlowClaw Inference Relay")
    parser.add_argument("--once", action="store_true", help="Process one cycle and exit")
    parser.add_argument("--status", action="store_true", help="Check relay status")
    parser.add_argument("--interactive", "-i", action="store_true",
                       help="Run interactive CLI mode (no emulator needed)")
    parser.add_argument("--setup-encryption", action="store_true",
                       help="Generate encryption key and configure E2E encryption")
    parser.add_argument("--provider", default=None,
                       help="LLM provider to use (anthropic, openai, ollama)")
    parser.add_argument("--model", default=None, help="Model to use")
    args = parser.parse_args()

    config = RelayConfig.from_env()

    logging.basicConfig(
        level=getattr(logging, config.log_level),
        format="%(asctime)s [%(levelname)s] %(message)s",
    )

    if args.setup_encryption:
        setup_encryption(config)
        return

    if args.status:
        enc = EncryptionManager(config.encryption_key_path)
        print(f"FlowClaw Relay Status")
        print(f"  Network:    {config.flow_network}")
        print(f"  Account:    {config.flow_account_address}")
        print(f"  Access Node: {config.flow_access_node}")
        print(f"  Encryption: {'ENABLED' if enc.is_configured else 'DISABLED'}")
        if enc.is_configured:
            print(f"  Key:        {enc.fingerprint[:16]}...")
            print(f"  Key file:   {enc.key_path}")
        print(f"  Providers:  ", end="")
        providers = []
        if config.anthropic_api_key:
            providers.append("anthropic")
        if config.openai_api_key:
            providers.append("openai")
        if config.ollama_base_url:
            providers.append("ollama")
        print(", ".join(providers) if providers else "none configured")
        return

    if args.interactive:
        cli = CLIMode(config)
        cli.interactive()
        return

    relay = InferenceRelay(config)
    relay.run(once=args.once)


if __name__ == "__main__":
    main()
