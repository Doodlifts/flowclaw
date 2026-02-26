#!/usr/bin/env python3
"""
FlowClaw Gas Sponsor
=====================
Pays transaction fees for users who don't have FLOW tokens.

Flow transactions have 3 distinct roles:
  - Proposer: initiates the transaction (provides sequence number)
  - Payer: pays the gas fees
  - Authorizer: signs to authorize state changes

For passkey-onboarded users:
  - Proposer = user's passkey account
  - Payer = FlowClaw sponsor account (this module)
  - Authorizer = user's passkey account

The sponsor NEVER has a key on the user's account.
It only agrees to pay gas for approved transaction types.

Rate limiting: configurable per-account daily limit (default: 100).

Migration note: Now uses FlowRESTClient (HTTP) instead of CLI subprocess.
"""

import json
import logging
import os
import subprocess
import time
from typing import Optional, Dict, List
from pathlib import Path
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)


# Transactions that the sponsor will pay gas for
SPONSORED_TX_TYPES = {
    "send_message",
    "create_session",
    "store_memory",
    "store_cognitive_memory",
    "create_memory_bond",
    "schedule_task",
    "cancel_task",
    "setup_full_account",
    "create_agent_in_collection",
    "run_dream_cycle",
    "publish_to_parent",  # Account linking
    "migrate_to_agent_collection",
    "configure_encryption",
    "complete_inference_owner",
    "publish_extension",
    "install_extension",
    "uninstall_extension",
}


@dataclass
class SponsorBudget:
    """Tracks per-account sponsorship usage."""
    address: str
    tx_count: int = 0
    reset_time: float = 0
    total_sponsored: int = 0

    def is_within_limit(self, daily_limit: int) -> bool:
        now = time.time()
        if now - self.reset_time > 86400:
            self.tx_count = 0
            self.reset_time = now
        return self.tx_count < daily_limit

    def record_usage(self):
        self.tx_count += 1
        self.total_sponsored += 1


class GasSponsor:
    """
    Manages gas sponsorship for FlowClaw users.
    """

    def __init__(
        self,
        sponsor_address: str,
        sponsor_key_name: str,
        flow_network: str = "testnet",
        project_dir: str = None,
        daily_limit: int = int(os.environ.get("GAS_SPONSOR_DAILY_LIMIT", "100")),
        initial_flow: float = 0.001,
        flow_rest_client=None,
    ):
        self.sponsor_address = sponsor_address
        self.sponsor_key_name = sponsor_key_name
        self.network = flow_network
        self.project_dir = project_dir or str(Path(__file__).parent.parent)
        self.daily_limit = daily_limit
        self.initial_flow = initial_flow
        self.flow_client = flow_rest_client  # FlowRESTClient instance

        # Per-account budgets
        self.budgets: Dict[str, SponsorBudget] = {}

        # Global stats
        self.total_accounts_funded = 0
        self.total_txs_sponsored = 0

        mode = "REST API" if flow_rest_client else "CLI fallback"
        logger.info(
            f"GasSponsor initialized: sponsor={sponsor_address}, "
            f"daily_limit={daily_limit}, initial_flow={initial_flow}, mode={mode}"
        )

    def check_budget(self, address: str) -> bool:
        """Check if an address has remaining sponsored transactions."""
        budget = self.budgets.get(address)
        if not budget:
            # New address — create budget
            self.budgets[address] = SponsorBudget(
                address=address, reset_time=time.time()
            )
            return True
        return budget.is_within_limit(self.daily_limit)

    def record_sponsored_tx(self, address: str):
        """Record a sponsored transaction."""
        if address not in self.budgets:
            self.budgets[address] = SponsorBudget(
                address=address, reset_time=time.time()
            )
        self.budgets[address].record_usage()
        self.total_txs_sponsored += 1

    def is_sponsorable(self, tx_name: str) -> bool:
        """Check if a transaction type is eligible for sponsorship."""
        # Extract base name from path
        base = tx_name.split("/")[-1].replace(".cdc", "")
        return base in SPONSORED_TX_TYPES

    def get_remaining(self, address: str) -> int:
        """Get remaining sponsored transactions for today."""
        budget = self.budgets.get(address)
        if not budget:
            return self.daily_limit
        now = time.time()
        if now - budget.reset_time > 86400:
            return self.daily_limit
        return max(0, self.daily_limit - budget.tx_count)

    # ------------------------------------------------------------------
    # Sponsored Transaction Execution
    # ------------------------------------------------------------------

    def send_sponsored_tx(
        self,
        tx_path: str,
        args_json: str,
        proposer_address: str,
        authorizer_address: Optional[str] = None,
    ) -> Optional[str]:
        """
        Send a transaction where the sponsor pays gas.

        Uses REST API if available, CLI fallback otherwise.
        """
        authorizer_address = authorizer_address or proposer_address

        # Check budget
        if not self.check_budget(proposer_address):
            logger.warning(f"Budget exceeded for {proposer_address}")
            return None

        # Check if tx type is sponsorable
        if not self.is_sponsorable(tx_path):
            logger.warning(f"Transaction type not sponsorable: {tx_path}")
            return None

        # Try REST API first
        if self.flow_client:
            try:
                cadence_code = Path(self.project_dir, tx_path).read_text()
                arguments = json.loads(args_json) if args_json else []
                result = self.flow_client.send_transaction(cadence_code, arguments)

                if result.get("sealed") or result.get("status") == "SEALED":
                    self.record_sponsored_tx(proposer_address)
                    logger.info(
                        f"Sponsored tx (REST) for {proposer_address}: {tx_path.split('/')[-1]} "
                        f"(remaining: {self.get_remaining(proposer_address)})"
                    )

                # Return backward-compatible string
                output = f"Transaction ID: {result.get('txId', '')}\nStatus: {result.get('status', 'UNKNOWN')}"
                if result.get("sealed"):
                    output += "\nStatus: SEALED"
                return output

            except Exception as e:
                logger.warning(f"REST sponsored tx failed, trying CLI: {e}")

        # CLI fallback
        try:
            cmd = [
                "flow", "transactions", "send",
                tx_path,
                "--args-json", args_json,
                "--signer", self.sponsor_key_name,
                "--network", self.network,
            ]

            result = subprocess.run(
                cmd, capture_output=True, text=True,
                cwd=self.project_dir, timeout=60,
            )

            output = result.stdout + "\n" + result.stderr

            if result.returncode == 0 or "sealed" in output.lower():
                self.record_sponsored_tx(proposer_address)
                logger.info(
                    f"Sponsored tx (CLI) for {proposer_address}: {tx_path.split('/')[-1]} "
                    f"(remaining: {self.get_remaining(proposer_address)})"
                )
                return output
            else:
                logger.error(f"Sponsored tx failed: {output[:500]}")
                return output

        except subprocess.TimeoutExpired:
            logger.error(f"Sponsored tx timed out: {tx_path}")
            return None
        except Exception as e:
            logger.error(f"Sponsored tx error: {e}")
            return None

    # ------------------------------------------------------------------
    # Fund new account with initial FLOW
    # ------------------------------------------------------------------

    def fund_account(self, address: str, amount: Optional[float] = None) -> bool:
        """
        Send initial FLOW to a new account for storage fees.
        """
        amount = amount or self.initial_flow
        amount_str = f"{amount:.8f}"

        # Try REST API first
        if self.flow_client:
            try:
                # Use the REST client's get_contract_address for proper imports
                network_addrs = {
                    "testnet": {"FlowToken": "0x7e60df042a9c0868", "FungibleToken": "0x9a0766d93b6608b7"},
                    "mainnet": {"FlowToken": "0x1654653399040a61", "FungibleToken": "0xf233dcee88fe0abe"},
                }
                addrs = network_addrs.get(self.network, network_addrs["testnet"])

                script = f"""
                import FlowToken from {addrs["FlowToken"]}
                import FungibleToken from {addrs["FungibleToken"]}

                transaction(recipient: Address, amount: UFix64) {{
                    let sentVault: @{{FungibleToken.Vault}}

                    prepare(signer: auth(BorrowValue) &Account) {{
                        let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                            from: /storage/flowTokenVault
                        ) ?? panic("Could not borrow reference to the owner's vault")
                        self.sentVault <- vaultRef.withdraw(amount: amount)
                    }}

                    execute {{
                        let receiverRef = getAccount(recipient)
                            .capabilities.borrow<&{{FungibleToken.Receiver}}>(/public/flowTokenReceiver)
                            ?? panic("Could not borrow receiver reference to the recipient's vault")
                        receiverRef.deposit(from: <- self.sentVault)
                    }}
                }}
                """

                arguments = [
                    {"type": "Address", "value": address},
                    {"type": "UFix64", "value": amount_str},
                ]

                result = self.flow_client.send_transaction(script, arguments)

                if result.get("sealed") or result.get("status") == "SEALED":
                    self.total_accounts_funded += 1
                    logger.info(f"Funded {address} with {amount} FLOW (REST)")
                    return True
                else:
                    logger.error(f"Funding failed (REST): {result.get('error', 'unknown')}")
                    return False

            except Exception as e:
                logger.warning(f"REST funding failed, trying CLI: {e}")

        # CLI fallback
        try:
            script = f"""
            import FlowToken from 0x7e60df042a9c0868
            import FungibleToken from 0x9a0766d93b6608b7

            transaction(recipient: Address, amount: UFix64) {{
                let sentVault: @{{FungibleToken.Vault}}

                prepare(signer: auth(BorrowValue) &Account) {{
                    let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                        from: /storage/flowTokenVault
                    ) ?? panic("Could not borrow reference to the owner's vault")
                    self.sentVault <- vaultRef.withdraw(amount: amount)
                }}

                execute {{
                    let receiverRef = getAccount(recipient)
                        .capabilities.borrow<&{{FungibleToken.Receiver}}>(/public/flowTokenReceiver)
                        ?? panic("Could not borrow receiver reference to the recipient's vault")
                    receiverRef.deposit(from: <- self.sentVault)
                }}
            }}
            """

            import tempfile
            with tempfile.NamedTemporaryFile(
                mode="w", suffix=".cdc", delete=False, dir="/tmp"
            ) as f:
                f.write(script)
                script_path = f.name

            args = json.dumps([
                {"type": "Address", "value": address},
                {"type": "UFix64", "value": amount_str},
            ])

            cmd = [
                "flow", "transactions", "send",
                script_path,
                "--args-json", args,
                "--signer", self.sponsor_key_name,
                "--network", self.network,
            ]

            result = subprocess.run(
                cmd, capture_output=True, text=True,
                cwd=self.project_dir, timeout=30,
            )

            import os
            os.unlink(script_path)

            success = result.returncode == 0 or "sealed" in (result.stdout + result.stderr).lower()
            if success:
                self.total_accounts_funded += 1
                logger.info(f"Funded {address} with {amount} FLOW (CLI)")
            else:
                logger.error(f"Funding failed (CLI): {result.stderr[:300]}")

            return success

        except Exception as e:
            logger.error(f"Funding error: {e}")
            return False

    # ------------------------------------------------------------------
    # Stats
    # ------------------------------------------------------------------

    def get_stats(self) -> Dict:
        """Get sponsor statistics."""
        return {
            "sponsorAddress": self.sponsor_address,
            "network": self.network,
            "dailyLimit": self.daily_limit,
            "initialFlow": self.initial_flow,
            "totalAccountsFunded": self.total_accounts_funded,
            "totalTxsSponsored": self.total_txs_sponsored,
            "activeAccounts": len(self.budgets),
        }

    def get_account_usage(self, address: str) -> Dict:
        """Get usage stats for a specific account."""
        budget = self.budgets.get(address)
        if not budget:
            return {
                "address": address,
                "txToday": 0,
                "remaining": self.daily_limit,
                "totalSponsored": 0,
            }
        return {
            "address": address,
            "txToday": budget.tx_count,
            "remaining": self.get_remaining(address),
            "totalSponsored": budget.total_sponsored,
        }
