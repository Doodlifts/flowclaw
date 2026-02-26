#!/usr/bin/env python3
"""
FlowClaw Account Manager
=========================
Handles passkey (WebAuthn) account creation and verification on Flow.

Flow supports P256 keys natively — a WebAuthn passkey IS a P256 key.
The sponsor account pays for account creation and initial resource setup.
The user's passkey becomes the SOLE key on their new account (weight 1000).

Account creation flow:
  1. User creates passkey in browser (WebAuthn navigator.credentials.create)
  2. Frontend sends P256 public key to relay
  3. Relay uses REST API to create new Flow account with that key
  4. Relay runs setup_full_account.cdc to initialize all FlowClaw resources
  5. Relay generates encryption key for the new account
  6. Returns { address, agentId } to frontend

Migration note: This module now uses FlowRESTClient (HTTP) instead of CLI subprocess.
"""

import json
import logging
import subprocess
import hashlib
import secrets
import time
import base64
from typing import Optional, Dict, Any, Tuple
from pathlib import Path
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)


@dataclass
class AccountInfo:
    """Represents a created FlowClaw account."""
    address: str
    agent_id: int
    auth_method: str  # "passkey", "wallet", "email"
    credential_id: Optional[str] = None
    public_key: Optional[str] = None
    created_at: float = 0
    custody_type: str = "standalone"  # "standalone" or "linked"
    linked_parent: Optional[str] = None

    def to_dict(self) -> Dict:
        return {
            "address": self.address,
            "agentId": self.agent_id,
            "authMethod": self.auth_method,
            "credentialId": self.credential_id,
            "createdAt": self.created_at,
            "custodyType": self.custody_type,
            "linkedParent": self.linked_parent,
        }


class AccountManager:
    """
    Manages Flow account creation via passkeys and session tokens.

    Accepts an optional FlowRESTClient for HTTP-based blockchain operations.
    Falls back to CLI if no REST client is provided.
    """

    def __init__(
        self,
        sponsor_address: str,
        sponsor_key_name: str,
        flow_network: str = "testnet",
        project_dir: str = None,
        daily_create_limit: int = 999999,
        flow_rest_client=None,
    ):
        self.sponsor_address = sponsor_address
        self.sponsor_key_name = sponsor_key_name  # Name in flow.json accounts
        self.network = flow_network
        self.project_dir = project_dir or str(Path(__file__).parent.parent)
        self.daily_create_limit = daily_create_limit
        self.flow_client = flow_rest_client  # FlowRESTClient instance

        # In-memory account registry (production: use a database)
        self.accounts: Dict[str, AccountInfo] = {}  # address -> AccountInfo
        self.credential_map: Dict[str, str] = {}  # credentialId -> address
        self.session_tokens: Dict[str, Dict] = {}  # token -> { address, expiresAt }

        # Rate limiting
        self._daily_creates = 0
        self._daily_reset = time.time()

        mode = "REST API" if flow_rest_client else "CLI fallback"
        logger.info(f"AccountManager initialized: sponsor={sponsor_address}, network={flow_network}, mode={mode}")

    # ------------------------------------------------------------------
    # Passkey Account Creation
    # ------------------------------------------------------------------

    async def create_passkey_account(
        self,
        public_key_hex: str,
        credential_id: str,
        display_name: str = "FlowClaw User",
    ) -> Dict[str, Any]:
        """
        Create a new Flow account with a WebAuthn passkey as the sole key.

        Args:
            public_key_hex: P256 public key from WebAuthn, hex-encoded (uncompressed, no 0x04 prefix)
            credential_id: WebAuthn credential ID (base64url)
            display_name: User-chosen display name

        Returns:
            { address, agentId, success, token }
        """
        # Rate limit check
        self._check_daily_limit()

        # Validate public key format (should be 128 hex chars for uncompressed P256 without prefix)
        clean_key = public_key_hex.replace("0x", "").replace("04", "", 1) if public_key_hex.startswith("04") else public_key_hex.replace("0x", "")
        if len(clean_key) != 128:
            # Try with the full uncompressed key (65 bytes = 130 hex chars including 04 prefix)
            if len(public_key_hex.replace("0x", "")) == 130 and public_key_hex.replace("0x", "").startswith("04"):
                clean_key = public_key_hex.replace("0x", "")[2:]  # Strip 04 prefix
            else:
                raise ValueError(
                    f"Invalid P256 public key length: expected 128 hex chars (64 bytes), "
                    f"got {len(clean_key)}. Pass the raw X||Y coordinates without the 04 prefix."
                )

        # Check if credential already used
        if credential_id in self.credential_map:
            existing_addr = self.credential_map[credential_id]
            logger.warning(f"Credential {credential_id[:16]}... already registered to {existing_addr}")
            return {
                "address": existing_addr,
                "agentId": self.accounts[existing_addr].agent_id,
                "success": True,
                "existing": True,
                "token": self._issue_token(existing_addr, credential_id),
            }

        try:
            # Step 1: Create Flow account with the passkey's P256 public key
            logger.info(f"Creating Flow account with passkey for {display_name}")
            address = await self._create_flow_account(clean_key)

            if not address:
                raise RuntimeError("Failed to create Flow account")

            logger.info(f"Flow account created: {address}")

            # Step 2: Initialize all FlowClaw resources
            logger.info(f"Initializing FlowClaw resources for {address}")
            agent_id = await self._initialize_flowclaw(address, display_name)

            logger.info(f"FlowClaw initialized: agent #{agent_id}")

            # Step 3: Register account
            account = AccountInfo(
                address=address,
                agent_id=agent_id,
                auth_method="passkey",
                credential_id=credential_id,
                public_key=clean_key,
                created_at=time.time(),
            )
            self.accounts[address] = account
            self.credential_map[credential_id] = address
            self._daily_creates += 1

            # Step 4: Issue session token
            token = self._issue_token(address, credential_id)

            logger.info(f"Account creation complete: {address}, agent #{agent_id}")

            return {
                "address": address,
                "agentId": agent_id,
                "success": True,
                "existing": False,
                "token": token,
            }

        except Exception as e:
            logger.error(f"Account creation failed: {e}")
            raise

    # ------------------------------------------------------------------
    # Passkey Verification (returning users)
    # ------------------------------------------------------------------

    async def verify_passkey(
        self,
        credential_id: str,
        client_data_json: Optional[str] = None,
        authenticator_data: Optional[str] = None,
        signature: Optional[str] = None,
    ) -> Optional[Dict]:
        """
        Verify a returning user's passkey assertion.

        For the PoC, we trust the credential_id mapping.
        In production, we'd verify the WebAuthn assertion signature
        against the stored public key.
        """
        address = self.credential_map.get(credential_id)
        if not address:
            logger.warning(f"Unknown credential: {credential_id[:16]}...")
            return None

        account = self.accounts.get(address)
        if not account:
            logger.warning(f"Account not found for credential: {credential_id[:16]}...")
            return None

        # In production: verify the assertion signature using the stored P256 public key
        # For now, the credential_id match is sufficient for the PoC
        # TODO: Implement full WebAuthn assertion verification

        token = self._issue_token(address, credential_id)

        return {
            "address": address,
            "agentId": account.agent_id,
            "authMethod": "passkey",
            "token": token,
            "custodyType": account.custody_type,
        }

    # ------------------------------------------------------------------
    # Session Tokens
    # ------------------------------------------------------------------

    def _issue_token(self, address: str, credential_id: str, ttl_hours: int = 24) -> str:
        """Issue a simple session token. Production: use JWT with proper signing."""
        token = secrets.token_urlsafe(48)
        self.session_tokens[token] = {
            "address": address,
            "credentialId": credential_id,
            "issuedAt": time.time(),
            "expiresAt": time.time() + (ttl_hours * 3600),
        }
        return token

    def verify_token(self, token: str) -> Optional[Dict]:
        """Verify a session token. Returns token data or None."""
        data = self.session_tokens.get(token)
        if not data:
            return None
        if time.time() > data["expiresAt"]:
            del self.session_tokens[token]
            return None
        return data

    def get_account_status(self, address: str) -> Optional[Dict]:
        """Get account status by address."""
        account = self.accounts.get(address)
        if not account:
            return None
        return account.to_dict()

    # ------------------------------------------------------------------
    # Account Linking (Hybrid Custody)
    # ------------------------------------------------------------------

    async def initiate_link(self, child_address: str, parent_address: str) -> Dict:
        """
        Initiate HybridCustody linking: child publishes capability for parent.
        The child (FlowClaw) account runs publish_to_parent.cdc.
        """
        account = self.accounts.get(child_address)
        if not account:
            raise ValueError(f"Account not found: {child_address}")

        try:
            result = self._run_transaction(
                "cadence/transactions/publish_to_parent.cdc",
                [{"type": "Address", "value": parent_address}],
            )

            success = result is not None and ("sealed" in str(result).lower() or result.get("sealed", False) if isinstance(result, dict) else False)

            if success:
                account.custody_type = "linking"
                logger.info(f"Link initiated: {child_address} → {parent_address}")

            return {
                "success": success,
                "childAddress": child_address,
                "parentAddress": parent_address,
                "status": "published" if success else "failed",
            }
        except Exception as e:
            logger.error(f"Link initiation failed: {e}")
            return {"success": False, "error": str(e)}

    async def confirm_link(self, child_address: str, parent_address: str):
        """Called after parent claims the child account."""
        account = self.accounts.get(child_address)
        if account:
            account.custody_type = "linked"
            account.linked_parent = parent_address
            logger.info(f"Link confirmed: {child_address} is child of {parent_address}")

    # ------------------------------------------------------------------
    # Flow Operations (REST API with CLI fallback)
    # ------------------------------------------------------------------

    async def _create_flow_account(self, p256_public_key_hex: str) -> Optional[str]:
        """
        Create a new Flow account with the given P256 public key.
        Uses REST API (preferred) with CLI fallback.
        """
        # Try REST API first
        if self.flow_client:
            try:
                address = self.flow_client.create_account(
                    new_public_key_hex=p256_public_key_hex,
                    sig_algo="ECDSA_P256",
                    hash_algo="SHA3_256",
                    key_weight=1000,
                    initial_flow=0.001,
                )
                return address
            except Exception as e:
                logger.warning(f"REST account creation failed, trying CLI fallback: {e}")

        # CLI fallback
        return await self._create_flow_account_cli(p256_public_key_hex)

    async def _create_flow_account_cli(self, p256_public_key_hex: str) -> Optional[str]:
        """Create account via Flow CLI (fallback)."""
        try:
            cmd = [
                "flow", "accounts", "create",
                "--key", p256_public_key_hex,
                "--sig-algo", "ECDSA_P256",
                "--hash-algo", "SHA3_256",
                "--signer", self.sponsor_key_name,
                "--network", self.network,
                "--output", "json",
            ]

            result = subprocess.run(
                cmd, capture_output=True, text=True,
                cwd=self.project_dir, timeout=120,
            )

            if result.returncode != 0:
                clean_err = self._clean_cli_output(result.stderr)
                logger.error(f"CLI account creation failed: {clean_err}")
                raise RuntimeError(f"Flow account creation failed: {clean_err[:500]}")

            # Parse JSON output
            try:
                data = json.loads(result.stdout)
                address = data.get("address", "")
                if address:
                    return address if address.startswith("0x") else "0x" + address
            except json.JSONDecodeError:
                pass

            # Fallback: parse text output for address
            for line in result.stdout.split("\n"):
                if "Address" in line and "0x" in line:
                    parts = line.split()
                    for part in parts:
                        if part.startswith("0x") and len(part) == 18:
                            return part

            logger.error(f"Could not parse address from: {result.stdout[:500]}")
            return None

        except subprocess.TimeoutExpired:
            raise RuntimeError("Account creation timed out")

    async def _initialize_flowclaw(
        self, address: str, agent_name: str
    ) -> int:
        """
        Run setup_full_account.cdc to initialize all FlowClaw resources.
        Returns the agent ID.
        """
        arguments = [
            {"type": "String", "value": agent_name},
            {"type": "String", "value": f"FlowClaw AI agent for {agent_name}"},
            {"type": "String", "value": "venice"},
            {"type": "String", "value": "claude-sonnet-4-6"},
            {"type": "String", "value": ""},  # apiKeyHash
            {"type": "UInt64", "value": "4096"},
            {"type": "UFix64", "value": "0.70000000"},
            {"type": "String", "value": (
                "You are FlowClaw, an autonomous AI agent running on the Flow blockchain. "
                "Your conversations are stored on-chain with end-to-end encryption. "
                "Be helpful, concise, and use your tools when you need real data."
            )},
            {"type": "UInt8", "value": "1"},  # autonomyLevel: supervised
            {"type": "UInt64", "value": "100"},  # maxActionsPerHour
            {"type": "UFix64", "value": "5.00000000"},  # maxCostPerDay
        ]

        result = self._run_transaction(
            "cadence/transactions/setup_full_account.cdc",
            arguments,
        )

        if not result:
            raise RuntimeError("FlowClaw initialization failed: no response")

        # Check for errors in the result
        result_str = str(result)
        if isinstance(result, dict):
            if result.get("error"):
                raise RuntimeError(f"FlowClaw initialization failed: {result['error']}")
        else:
            # CLI output: check for actual errors (not warnings)
            result_clean = result_str.replace("Security warning", "").replace("security warning", "")
            has_error = ("error" in result_clean.lower() and "error code" in result_clean.lower()) or "panic" in result_clean.lower()
            if has_error and "sealed" not in result_str.lower():
                raise RuntimeError(f"FlowClaw initialization failed: {result_str[:500]}")

        # Extract agent ID (for PoC, use local counter)
        return 1  # Default agent ID; in production parse from events

    def _run_transaction(self, tx_path: str, arguments: list) -> Any:
        """
        Run a Cadence transaction. Uses REST API if available, CLI fallback otherwise.

        Args:
            tx_path: Path to .cdc file (relative to project_dir)
            arguments: List of Cadence arguments [{"type": "...", "value": "..."}]

        Returns:
            REST: dict with {txId, status, events, sealed}
            CLI: string output
        """
        # Try REST API first
        if self.flow_client:
            try:
                full_path = str(Path(self.project_dir) / tx_path)
                return self.flow_client.send_transaction_from_file(
                    full_path,
                    arguments=arguments,
                )
            except Exception as e:
                logger.warning(f"REST transaction failed, trying CLI: {e}")

        # CLI fallback
        args_json = json.dumps(arguments)
        return self._run_flow_tx_cli(tx_path, args_json)

    def _run_flow_tx_cli(
        self, tx_path: str, args_json: str, signer: str = None
    ) -> Optional[str]:
        """Run a Cadence transaction via Flow CLI (fallback)."""
        cmd = [
            "flow", "transactions", "send",
            tx_path,
            "--args-json", args_json,
            "--signer", signer or self.sponsor_key_name,
            "--network", self.network,
        ]

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True,
                cwd=self.project_dir, timeout=120,
            )
            output = self._clean_cli_output(result.stdout + "\n" + result.stderr)
            if result.returncode != 0:
                logger.error(f"CLI transaction failed: {output[:500]}")
            return output
        except subprocess.TimeoutExpired:
            logger.error(f"CLI transaction timed out: {tx_path}")
            return None

    @staticmethod
    def _clean_cli_output(raw: str) -> str:
        """Strip ANSI escape codes and spinner artifacts from Flow CLI output."""
        import re
        clean = re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', raw)
        clean = re.sub(r'⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏', '', clean)
        return clean.strip()

    # ------------------------------------------------------------------
    # Rate Limiting
    # ------------------------------------------------------------------

    def _check_daily_limit(self):
        """Check and reset daily account creation limit."""
        now = time.time()
        if now - self._daily_reset > 86400:
            self._daily_creates = 0
            self._daily_reset = now

        if self._daily_creates >= self.daily_create_limit:
            raise RuntimeError(
                f"Daily account creation limit reached ({self.daily_create_limit}). "
                "Try again tomorrow."
            )
