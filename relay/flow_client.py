#!/usr/bin/env python3
"""
FlowClaw Flow REST Client
===========================
Direct HTTP client for Flow Access API — replaces Flow CLI subprocess calls.

Uses the Flow Access REST API for all blockchain operations:
  - Script execution (read-only queries)
  - Transaction building, signing, and submission
  - Account queries
  - Account creation

No CLI dependency needed. Just Python + requests + cryptography.

Flow Access API docs: https://developers.flow.com/http-api
"""

import base64
import hashlib
import json
import logging
import struct
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import requests

# cryptography is optional — needed for transaction signing only.
# Script execution and account queries work without it.
# Install: pip3 install cryptography
try:
    from cryptography.hazmat.primitives.asymmetric import ec, utils
    from cryptography.hazmat.primitives import hashes
    HAS_CRYPTO = True
except ImportError:
    HAS_CRYPTO = False

logger = logging.getLogger(__name__)

# Flow transaction domain tags (32 bytes, right-padded with zeros)
TRANSACTION_DOMAIN_TAG = b"FLOW-V0.0-transaction" + b"\x00" * 11  # 21 + 11 = 32


# ---------------------------------------------------------------------------
# Minimal RLP Encoder (just what Flow transactions need)
# ---------------------------------------------------------------------------

def rlp_encode(item) -> bytes:
    """
    RLP encode a value. Supports:
      - bytes/bytearray → string
      - int → big-endian bytes string
      - str → utf-8 bytes string
      - list/tuple → list
    """
    if isinstance(item, (bytes, bytearray)):
        return _rlp_encode_string(item)
    elif isinstance(item, int):
        if item == 0:
            return _rlp_encode_string(b"")
        else:
            # Encode as big-endian bytes, minimal length
            length = (item.bit_length() + 7) // 8
            return _rlp_encode_string(item.to_bytes(length, "big"))
    elif isinstance(item, str):
        return _rlp_encode_string(item.encode("utf-8"))
    elif isinstance(item, (list, tuple)):
        return _rlp_encode_list(item)
    else:
        raise TypeError(f"Cannot RLP encode type: {type(item)}")


def _rlp_encode_string(data: bytes) -> bytes:
    length = len(data)
    if length == 1 and data[0] < 0x80:
        return data
    elif length <= 55:
        return bytes([0x80 + length]) + data
    else:
        len_bytes = _encode_length(length)
        return bytes([0xB7 + len(len_bytes)]) + len_bytes + data


def _rlp_encode_list(items: list) -> bytes:
    encoded = b"".join(rlp_encode(item) for item in items)
    length = len(encoded)
    if length <= 55:
        return bytes([0xC0 + length]) + encoded
    else:
        len_bytes = _encode_length(length)
        return bytes([0xF7 + len(len_bytes)]) + len_bytes + encoded


def _encode_length(length: int) -> bytes:
    if length == 0:
        return b""
    byte_length = (length.bit_length() + 7) // 8
    return length.to_bytes(byte_length, "big")


# ---------------------------------------------------------------------------
# Flow Transaction Signing
# ---------------------------------------------------------------------------

def _normalize_address(address: str) -> str:
    """Remove 0x prefix and ensure lowercase 16 chars."""
    addr = address.lower().replace("0x", "")
    # Flow addresses are 8 bytes = 16 hex chars, left-padded with zeros
    return addr.zfill(16)


def _address_bytes(address: str) -> bytes:
    """Convert Flow address string to 8-byte representation."""
    return bytes.fromhex(_normalize_address(address))


def _build_payload_rlp(
    script: bytes,
    arguments: List[bytes],
    reference_block_id: bytes,
    gas_limit: int,
    proposer_address: bytes,
    proposer_key_index: int,
    proposer_seq_number: int,
    payer: bytes,
    authorizers: List[bytes],
) -> bytes:
    """
    RLP encode a Flow transaction payload.

    Field order (per Flow spec):
      [script, arguments, referenceBlockId, gasLimit,
       [proposerAddress, keyIndex, sequenceNumber],
       payer, authorizers]
    """
    proposal_key = [proposer_address, proposer_key_index, proposer_seq_number]
    payload = [
        script,
        arguments,
        reference_block_id,
        gas_limit,
        proposal_key,
        payer,
        authorizers,
    ]
    return rlp_encode(payload)


def _build_envelope_rlp(
    payload_rlp_inner: list,
    payload_signatures: List[list],
) -> bytes:
    """
    RLP encode a Flow transaction envelope.

    Envelope = [payload_fields, payload_signatures]
    where payload_signatures = [[signerIndex, keyIndex, signature], ...]
    """
    envelope = [payload_rlp_inner, payload_signatures]
    return rlp_encode(envelope)


def _sign_message(message: bytes, private_key_hex: str, sig_algo: str = "ECDSA_P256", hash_algo: str = "SHA3_256") -> bytes:
    """
    Sign a message using the specified signature and hash algorithms.

    Args:
        message: Domain tag + RLP-encoded payload/envelope
        private_key_hex: Private key as hex string
        sig_algo: "ECDSA_P256" or "ECDSA_secp256k1"
        hash_algo: "SHA3_256" or "SHA2_256"

    Returns:
        Raw signature bytes (r || s), 64 bytes
    """
    if not HAS_CRYPTO:
        raise RuntimeError(
            "Transaction signing requires the 'cryptography' library. "
            "Install it: pip3 install cryptography"
        )

    # Load the private key with the correct curve
    private_key_int = int(private_key_hex, 16)
    curve = ec.SECP256K1() if sig_algo == "ECDSA_secp256k1" else ec.SECP256R1()
    private_key = ec.derive_private_key(private_key_int, curve)

    # Select hash algorithm
    hash_algorithm = hashes.SHA256() if hash_algo == "SHA2_256" else hashes.SHA3_256()

    signature_der = private_key.sign(
        message,
        ec.ECDSA(hash_algorithm)
    )

    # Decode DER signature to (r, s) integers
    r, s = utils.decode_dss_signature(signature_der)

    # Convert to raw bytes: r (32 bytes big-endian) || s (32 bytes big-endian)
    r_bytes = r.to_bytes(32, "big")
    s_bytes = s.to_bytes(32, "big")

    return r_bytes + s_bytes


def _get_signer_index(address: bytes, proposer: bytes, authorizers: List[bytes], payer: bytes) -> int:
    """
    Get the signer index for an address in the transaction's signer list.

    Flow's signer list order: proposer, then authorizers (excluding proposer),
    then payer (excluding if already in list).
    """
    signer_list = []
    seen = set()

    # Proposer first
    signer_list.append(proposer)
    seen.add(proposer)

    # Then authorizers (skip duplicates)
    for auth in authorizers:
        if auth not in seen:
            signer_list.append(auth)
            seen.add(auth)

    # Then payer (skip if duplicate)
    if payer not in seen:
        signer_list.append(payer)
        seen.add(payer)

    for i, signer in enumerate(signer_list):
        if signer == address:
            return i

    raise ValueError(f"Address {address.hex()} not found in signer list")


# ---------------------------------------------------------------------------
# JSON-CDC Argument Encoding
# ---------------------------------------------------------------------------

def _encode_cadence_argument(arg: Dict) -> str:
    """
    Encode a Cadence argument as a JSON-CDC string.
    Input: {"type": "String", "value": "hello"}
    Output: base64-encoded JSON string
    """
    return base64.b64encode(json.dumps(arg).encode("utf-8")).decode("utf-8")


# ---------------------------------------------------------------------------
# FlowRESTClient
# ---------------------------------------------------------------------------

class FlowRESTClient:
    """
    Direct HTTP client for Flow Access REST API.

    Replaces all Flow CLI subprocess calls with clean HTTP requests.
    Handles script execution, transaction building/signing/submission,
    and account queries.
    """

    # Access node URLs by network
    ACCESS_NODES = {
        "mainnet": "https://rest-mainnet.onflow.org",
        "testnet": "https://rest-testnet.onflow.org",
        "emulator": "http://localhost:8888",
        "local": "http://localhost:8888",
    }

    def __init__(
        self,
        network: str = "testnet",
        access_node: Optional[str] = None,
        signer_address: Optional[str] = None,
        signer_private_key_hex: Optional[str] = None,
        signer_key_index: int = 0,
        default_gas_limit: int = 9999,
        sig_algo: str = "ECDSA_P256",
        hash_algo: str = "SHA3_256",
    ):
        """
        Args:
            network: Flow network name (testnet, mainnet, emulator)
            access_node: Override access node URL
            signer_address: Default signer/payer Flow address
            signer_private_key_hex: Default signer's private key (hex)
            signer_key_index: Default signer's key index
            default_gas_limit: Default gas limit for transactions
            sig_algo: Signature algorithm ("ECDSA_P256" or "ECDSA_secp256k1")
            hash_algo: Hash algorithm ("SHA3_256" or "SHA2_256")
        """
        self.network = network
        self.access_node = access_node or self.ACCESS_NODES.get(network, self.ACCESS_NODES["testnet"])
        self.signer_address = signer_address
        self.signer_private_key_hex = signer_private_key_hex
        self.signer_key_index = signer_key_index
        self.default_gas_limit = default_gas_limit
        self.sig_algo = sig_algo
        self.hash_algo = hash_algo
        self.contract_aliases: Dict[str, str] = {}  # contract name -> address

        self._session = requests.Session()
        self._session.headers.update({
            "Content-Type": "application/json",
            "Accept": "application/json",
        })

        logger.info(
            f"FlowRESTClient initialized: network={network}, "
            f"access_node={self.access_node}, "
            f"signer={signer_address or 'none'}"
        )

    def load_aliases_from_flow_json(self, flow_json_path: str):
        """
        Load contract address aliases from flow.json so we can resolve
        bare imports like 'import AgentRegistry' to 'import AgentRegistry from 0x808983d30a46aee2'.

        The Flow CLI does this automatically, but REST API needs full addresses.
        """
        import re
        try:
            with open(flow_json_path, "r") as f:
                flow_config = json.load(f)

            contracts = flow_config.get("contracts", {})
            for name, info in contracts.items():
                aliases = info.get("aliases", {})
                addr = aliases.get(self.network, "")
                if addr:
                    if not addr.startswith("0x"):
                        addr = "0x" + addr
                    self.contract_aliases[name] = addr

            # Also add standard Flow contracts
            std = self._get_contract_address
            for name in ("FlowToken", "FungibleToken", "NonFungibleToken", "MetadataViews",
                         "HybridCustody", "CapabilityFactory", "CapabilityFilter"):
                if name not in self.contract_aliases:
                    addr = std(name)
                    if addr and addr != "0x0":
                        self.contract_aliases[name] = addr

            logger.info(f"Loaded {len(self.contract_aliases)} contract aliases for {self.network}")

        except Exception as e:
            logger.warning(f"Could not load flow.json aliases: {e}")

    def _resolve_imports(self, cadence_code: str) -> str:
        """
        Resolve bare contract imports to full address imports.

        Handles three Cadence import styles:
          1. Cadence 1.0 quoted:  import "AgentRegistry"
          2. Legacy bare:         import AgentRegistry
          3. Self-referential:    import AgentRegistry from AgentRegistry

        All resolve to:          import AgentRegistry from 0x808983d30a46aee2
        """
        import re

        if not self.contract_aliases:
            return cadence_code

        # 1. Cadence 1.0 quoted imports:  import "ContractName"
        cadence_code = re.sub(
            r'^(\s*)import\s+"(\w+)"\s*$',
            lambda m: (
                f'{m.group(1)}import {m.group(2)} from {self.contract_aliases[m.group(2)]}'
                if m.group(2) in self.contract_aliases
                else m.group(0)
            ),
            cadence_code,
            flags=re.MULTILINE,
        )

        # 2. Legacy bare imports:  import ContractName
        cadence_code = re.sub(
            r'^(\s*)import\s+(\w+)\s*$',
            lambda m: (
                f'{m.group(1)}import {m.group(2)} from {self.contract_aliases[m.group(2)]}'
                if m.group(2) in self.contract_aliases
                else m.group(0)
            ),
            cadence_code,
            flags=re.MULTILINE,
        )

        # 3. Relative path imports:  import ContractName from "../contracts/ContractName.cdc"
        #    or:  import ContractName from "./ContractName.cdc"
        cadence_code = re.sub(
            r'^(\s*)import\s+(\w+)\s+from\s+"[^"]*\.cdc"\s*$',
            lambda m: (
                f'{m.group(1)}import {m.group(2)} from {self.contract_aliases[m.group(2)]}'
                if m.group(2) in self.contract_aliases
                else m.group(0)
            ),
            cadence_code,
            flags=re.MULTILINE,
        )

        # 4. Self-referential:  import ContractName from ContractName
        for name, addr in self.contract_aliases.items():
            cadence_code = cadence_code.replace(
                f"import {name} from {name}",
                f"import {name} from {addr}",
            )

        return cadence_code

    # ------------------------------------------------------------------
    # Script Execution (read-only)
    # ------------------------------------------------------------------

    def execute_script(
        self,
        cadence_code: str,
        arguments: Optional[List[Dict]] = None,
        at_block_height: Optional[str] = None,
    ) -> Any:
        """
        Execute a read-only Cadence script.

        Args:
            cadence_code: Cadence script source code
            arguments: List of Cadence arguments [{"type": "Address", "value": "0x..."}]
            at_block_height: Optional block height ("sealed" or number)

        Returns:
            Decoded Cadence value from the script result
        """
        # Resolve bare contract imports to full address imports
        cadence_code = self._resolve_imports(cadence_code)

        # Encode script as base64
        script_b64 = base64.b64encode(cadence_code.encode("utf-8")).decode("utf-8")

        # Encode arguments as base64 JSON-CDC values
        args_b64 = []
        if arguments:
            for arg in arguments:
                args_b64.append(_encode_cadence_argument(arg))

        body = {
            "script": script_b64,
            "arguments": args_b64,
        }

        url = f"{self.access_node}/v1/scripts"
        if at_block_height:
            url += f"?block_height={at_block_height}"

        try:
            resp = self._session.post(url, json=body, timeout=30)

            if resp.status_code == 200:
                # Response is base64-encoded JSON-CDC value
                result_b64 = resp.text.strip().strip('"')
                try:
                    result_json = base64.b64decode(result_b64).decode("utf-8")
                    result = json.loads(result_json)
                    return self._decode_cadence_value(result)
                except Exception:
                    # Return raw if can't decode
                    return result_b64
            else:
                error_body = resp.text[:500]
                logger.error(f"Script execution failed ({resp.status_code}): {error_body}")
                raise RuntimeError(f"Script execution failed: {error_body}")

        except requests.exceptions.RequestException as e:
            logger.error(f"Script execution request error: {e}")
            raise RuntimeError(f"Script execution error: {e}")

    # ------------------------------------------------------------------
    # Transaction Sending
    # ------------------------------------------------------------------

    def send_transaction(
        self,
        cadence_code: str,
        arguments: Optional[List[Dict]] = None,
        authorizers: Optional[List[str]] = None,
        payer: Optional[str] = None,
        proposer: Optional[str] = None,
        proposer_key_index: Optional[int] = None,
        gas_limit: Optional[int] = None,
        wait_sealed: bool = True,
        timeout: int = 120,
    ) -> Dict[str, Any]:
        """
        Build, sign, and submit a transaction.

        For single-signer (default): proposer = authorizer = payer = self.signer_address

        Args:
            cadence_code: Cadence transaction source code
            arguments: Transaction arguments [{"type": "...", "value": "..."}]
            authorizers: List of authorizer addresses (default: [signer])
            payer: Payer address (default: signer)
            proposer: Proposer address (default: signer)
            proposer_key_index: Proposer's key index (default: self.signer_key_index)
            gas_limit: Gas limit (default: self.default_gas_limit)
            wait_sealed: Whether to poll until sealed
            timeout: Max seconds to wait for seal

        Returns:
            {"txId": "...", "status": "SEALED", "events": [...], "statusCode": 4}
        """
        if not self.signer_address or not self.signer_private_key_hex:
            raise RuntimeError("Signer not configured — set signer_address and signer_private_key_hex")

        # Resolve bare contract imports to full address imports
        cadence_code = self._resolve_imports(cadence_code)

        # Defaults
        proposer = proposer or self.signer_address
        payer = payer or self.signer_address
        authorizers = authorizers or [self.signer_address]
        proposer_key_idx = proposer_key_index if proposer_key_index is not None else self.signer_key_index
        gas = gas_limit or self.default_gas_limit

        # 1. Get reference block and sequence number
        ref_block_id = self._get_latest_block_id()
        seq_number = self._get_sequence_number(proposer, proposer_key_idx)

        # 2. Encode script and arguments
        script_bytes = cadence_code.encode("utf-8")
        arg_bytes_list = []
        if arguments:
            for arg in arguments:
                arg_bytes_list.append(json.dumps(arg).encode("utf-8"))

        # 3. Build the payload fields for RLP encoding
        ref_block_bytes = bytes.fromhex(ref_block_id)
        proposer_bytes = _address_bytes(proposer)
        payer_bytes = _address_bytes(payer)
        authorizer_bytes_list = [_address_bytes(a) for a in authorizers]

        # Flow's canonical payload is 9 FLAT fields (proposal key is NOT nested):
        #   [script, arguments, refBlockId, gasLimit,
        #    proposalKeyAddress, proposalKeyIndex, proposalKeySequenceNumber,
        #    payer, authorizers]
        payload_fields = [
            script_bytes,
            arg_bytes_list,
            ref_block_bytes,
            gas,
            proposer_bytes,       # flat, not nested
            proposer_key_idx,     # flat, not nested
            seq_number,           # flat, not nested
            payer_bytes,
            authorizer_bytes_list,
        ]

        # 4. Determine if single-signer (proposer = authorizer = payer = same account)
        all_same_signer = (
            proposer_bytes == payer_bytes
            and len(authorizer_bytes_list) == 1
            and authorizer_bytes_list[0] == proposer_bytes
        )

        if all_same_signer:
            # Single-signer: empty payload signatures, sign only envelope
            payload_signatures = []

            # Flow's canonical envelope is NESTED: [payload_list, payloadSignatures]
            # (Go SDK has Payload as a named field, not embedded, so it stays nested)
            envelope_fields = [payload_fields, payload_signatures]
            envelope_rlp = rlp_encode(envelope_fields)
            envelope_message = TRANSACTION_DOMAIN_TAG + envelope_rlp
            envelope_sig = _sign_message(envelope_message, self.signer_private_key_hex, self.sig_algo, self.hash_algo)

            envelope_signatures = [
                [0, proposer_key_idx, envelope_sig]  # signer index 0
            ]
        else:
            # Multi-signer: sign payload for proposer/authorizers, envelope for payer
            payload_rlp = rlp_encode(payload_fields)
            payload_message = TRANSACTION_DOMAIN_TAG + payload_rlp
            payload_sig = _sign_message(payload_message, self.signer_private_key_hex, self.sig_algo, self.hash_algo)

            signer_index = _get_signer_index(
                _address_bytes(self.signer_address),
                proposer_bytes,
                authorizer_bytes_list,
                payer_bytes,
            )

            payload_signatures = [
                [signer_index, proposer_key_idx, payload_sig]
            ]

            # Nested envelope: [payload_list, payloadSignatures]
            envelope_fields = [payload_fields, payload_signatures]
            envelope_rlp = rlp_encode(envelope_fields)
            envelope_message = TRANSACTION_DOMAIN_TAG + envelope_rlp
            envelope_sig = _sign_message(envelope_message, self.signer_private_key_hex, self.sig_algo, self.hash_algo)

            payer_signer_index = _get_signer_index(
                payer_bytes,
                proposer_bytes,
                authorizer_bytes_list,
                payer_bytes,
            )

            envelope_signatures = [
                [payer_signer_index, proposer_key_idx, envelope_sig]
            ]

        # 5. Build the REST API request
        args_b64 = []
        if arguments:
            for arg in arguments:
                args_b64.append(_encode_cadence_argument(arg))

        # Build payload signature list for REST API
        payload_sigs_rest = []
        if not all_same_signer:
            payload_sigs_rest = [
                {
                    "address": _normalize_address(self.signer_address),
                    "key_index": str(proposer_key_idx),
                    "signature": base64.b64encode(payload_sig).decode("utf-8"),
                }
            ]

        tx_body = {
            "script": base64.b64encode(script_bytes).decode("utf-8"),
            "arguments": args_b64,
            "reference_block_id": ref_block_id,
            "gas_limit": str(gas),
            "payer": _normalize_address(payer),
            "proposal_key": {
                "address": _normalize_address(proposer),
                "key_index": str(proposer_key_idx),
                "sequence_number": str(seq_number),
            },
            "authorizers": [_normalize_address(a) for a in authorizers],
            "payload_signatures": payload_sigs_rest,
            "envelope_signatures": [
                {
                    "address": _normalize_address(payer),
                    "key_index": str(proposer_key_idx),
                    "signature": base64.b64encode(envelope_sig).decode("utf-8"),
                }
            ],
        }

        # 7. Submit
        try:
            resp = self._session.post(
                f"{self.access_node}/v1/transactions",
                json=tx_body,
                timeout=30,
            )

            if resp.status_code not in (200, 201):
                error_body = resp.text[:1000]
                logger.error(f"Transaction submission failed ({resp.status_code}): {error_body}")
                raise RuntimeError(f"Transaction failed: {error_body}")

            tx_data = resp.json()
            tx_id = tx_data.get("id", "")

            logger.info(f"Transaction submitted: {tx_id}")

            # 8. Wait for seal if requested
            if wait_sealed and tx_id:
                return self._wait_for_seal(tx_id, timeout)

            return {
                "txId": tx_id,
                "status": "SUBMITTED",
                "statusCode": 1,
            }

        except requests.exceptions.RequestException as e:
            logger.error(f"Transaction submission error: {e}")
            raise RuntimeError(f"Transaction submission error: {e}")

    # ------------------------------------------------------------------
    # Multi-Party Transaction Building (user = proposer/authorizer, sponsor = payer)
    # ------------------------------------------------------------------

    def build_unsigned_transaction(
        self,
        cadence_code: str,
        arguments: Optional[List[Dict]] = None,
        user_address: str = None,
        user_key_index: int = 0,
        gas_limit: Optional[int] = None,
    ) -> Dict[str, Any]:
        """
        Build a transaction payload for multi-party signing.

        The user is proposer + authorizer, the sponsor (self.signer_address) is payer.
        Returns the payload hex that the user must sign, plus metadata needed for completion.

        Args:
            cadence_code: Cadence transaction source code
            arguments: Transaction arguments [{"type": "...", "value": "..."}]
            user_address: User's Flow address (proposer + authorizer)
            user_key_index: User's key index (default 0)
            gas_limit: Gas limit override

        Returns:
            {
                "payloadHex": "...",    # Hex bytes the user must sign
                "payloadFields": [...], # Serialized payload fields for completion
                "referenceBlockId": "...",
                "sequenceNumber": int,
                "userAddress": "...",
                "userKeyIndex": int,
                "gasLimit": int,
                "script_b64": "...",    # For REST API submission
                "args_b64": [...],      # For REST API submission
            }
        """
        if not user_address:
            raise ValueError("user_address is required for multi-party transactions")
        if not self.signer_address:
            raise RuntimeError("Sponsor (payer) not configured — set signer_address")

        # Resolve imports
        cadence_code = self._resolve_imports(cadence_code)

        # Defaults
        gas = gas_limit or self.default_gas_limit
        payer = self.signer_address

        # Get reference block and user's sequence number
        ref_block_id = self._get_latest_block_id()
        seq_number = self._get_sequence_number(user_address, user_key_index)

        # Encode script and arguments
        script_bytes = cadence_code.encode("utf-8")
        arg_bytes_list = []
        if arguments:
            for arg in arguments:
                arg_bytes_list.append(json.dumps(arg).encode("utf-8"))

        # Build payload fields (Flow's canonical 9-field flat format)
        ref_block_bytes = bytes.fromhex(ref_block_id)
        user_bytes = _address_bytes(user_address)
        payer_bytes = _address_bytes(payer)
        authorizer_bytes_list = [user_bytes]  # User is sole authorizer

        payload_fields = [
            script_bytes,
            arg_bytes_list,
            ref_block_bytes,
            gas,
            user_bytes,           # proposer address
            user_key_index,       # proposer key index
            seq_number,           # proposer sequence number
            payer_bytes,          # payer (sponsor)
            authorizer_bytes_list,  # authorizers (user only)
        ]

        # RLP encode the payload and prepend domain tag
        payload_rlp = rlp_encode(payload_fields)
        payload_message = TRANSACTION_DOMAIN_TAG + payload_rlp

        # Pre-encode for REST API submission
        script_b64 = base64.b64encode(script_bytes).decode("utf-8")
        args_b64 = []
        if arguments:
            for arg in arguments:
                args_b64.append(_encode_cadence_argument(arg))

        return {
            "payloadHex": payload_message.hex(),
            "referenceBlockId": ref_block_id,
            "sequenceNumber": seq_number,
            "userAddress": user_address,
            "userKeyIndex": user_key_index,
            "gasLimit": gas,
            # Internal fields needed for complete_multi_party_transaction
            "_payload_fields": payload_fields,
            "_script_b64": script_b64,
            "_args_b64": args_b64,
            "_payer": payer,
            "_user_address": user_address,
        }

    def complete_multi_party_transaction(
        self,
        build_result: Dict,
        user_signature_b64: str,
        wait_sealed: bool = True,
        timeout: int = 120,
    ) -> Dict[str, Any]:
        """
        Complete a multi-party transaction by adding the payer's envelope signature
        and submitting to Flow.

        Args:
            build_result: The result from build_unsigned_transaction()
            user_signature_b64: Base64-encoded user payload signature (r||s, 64 bytes)
            wait_sealed: Whether to poll until sealed
            timeout: Max seconds to wait

        Returns:
            {"txId": "...", "status": "SEALED", "events": [...], "sealed": True/False}
        """
        if not self.signer_private_key_hex:
            raise RuntimeError("Sponsor private key not configured")

        payload_fields = build_result["_payload_fields"]
        user_address = build_result["_user_address"]
        payer = build_result["_payer"]
        user_key_index = build_result["userKeyIndex"]

        # Decode user's payload signature
        user_sig_bytes = base64.b64decode(user_signature_b64)

        # Build signer list to determine indices
        user_bytes = _address_bytes(user_address)
        payer_bytes = _address_bytes(payer)
        authorizer_bytes_list = [user_bytes]

        user_signer_index = _get_signer_index(
            user_bytes, user_bytes, authorizer_bytes_list, payer_bytes
        )

        # Payload signatures: user signs the payload as proposer/authorizer
        payload_signatures = [
            [user_signer_index, user_key_index, user_sig_bytes]
        ]

        # Build envelope: [payload_fields, payload_signatures]
        envelope_fields = [payload_fields, payload_signatures]
        envelope_rlp = rlp_encode(envelope_fields)
        envelope_message = TRANSACTION_DOMAIN_TAG + envelope_rlp

        # Sponsor signs the envelope as payer
        envelope_sig = _sign_message(
            envelope_message,
            self.signer_private_key_hex,
            self.sig_algo,
            self.hash_algo,
        )

        payer_signer_index = _get_signer_index(
            payer_bytes, user_bytes, authorizer_bytes_list, payer_bytes
        )

        # Build REST API request
        payload_sigs_rest = [
            {
                "address": _normalize_address(user_address),
                "key_index": str(user_key_index),
                "signature": user_signature_b64,
            }
        ]

        tx_body = {
            "script": build_result["_script_b64"],
            "arguments": build_result["_args_b64"],
            "reference_block_id": build_result["referenceBlockId"],
            "gas_limit": str(build_result["gasLimit"]),
            "payer": _normalize_address(payer),
            "proposal_key": {
                "address": _normalize_address(user_address),
                "key_index": str(user_key_index),
                "sequence_number": str(build_result["sequenceNumber"]),
            },
            "authorizers": [_normalize_address(user_address)],
            "payload_signatures": payload_sigs_rest,
            "envelope_signatures": [
                {
                    "address": _normalize_address(payer),
                    "key_index": str(self.signer_key_index),
                    "signature": base64.b64encode(envelope_sig).decode("utf-8"),
                }
            ],
        }

        # Submit
        try:
            resp = self._session.post(
                f"{self.access_node}/v1/transactions",
                json=tx_body,
                timeout=30,
            )

            if resp.status_code not in (200, 201):
                error_body = resp.text[:1000]
                logger.error(f"Multi-party TX submission failed ({resp.status_code}): {error_body}")
                raise RuntimeError(f"Transaction failed: {error_body}")

            tx_data = resp.json()
            tx_id = tx_data.get("id", "")

            logger.info(f"Multi-party TX submitted: {tx_id} (user={user_address}, payer={payer})")

            if wait_sealed and tx_id:
                return self._wait_for_seal(tx_id, timeout)

            return {
                "txId": tx_id,
                "status": "SUBMITTED",
                "statusCode": 1,
            }

        except requests.exceptions.RequestException as e:
            logger.error(f"Multi-party TX submission error: {e}")
            raise RuntimeError(f"Transaction submission error: {e}")

    def send_transaction_from_file(
        self,
        tx_path: str,
        arguments: Optional[List[Dict]] = None,
        **kwargs,
    ) -> Dict[str, Any]:
        """
        Send a transaction by reading Cadence code from a file.
        Drop-in replacement for the old run_flow_tx().

        Args:
            tx_path: Path to .cdc file
            arguments: Transaction arguments
            **kwargs: Passed to send_transaction()
        """
        cadence_code = Path(tx_path).read_text()
        return self.send_transaction(cadence_code, arguments, **kwargs)

    # ------------------------------------------------------------------
    # Account Queries
    # ------------------------------------------------------------------

    def get_account(self, address: str) -> Dict:
        """
        Get account information.

        Returns: { address, balance, keys: [...], contracts: {...} }
        """
        addr = _normalize_address(address)

        try:
            resp = self._session.get(
                f"{self.access_node}/v1/accounts/{addr}?block_height=sealed&expand=keys",
                timeout=15,
            )

            if resp.status_code == 200:
                data = resp.json()
                return {
                    "address": "0x" + data.get("address", addr),
                    "balance": data.get("balance", "0"),
                    "keys": data.get("keys", []),
                    "contracts": data.get("contracts", {}),
                }
            else:
                raise RuntimeError(f"Account query failed ({resp.status_code}): {resp.text[:300]}")

        except requests.exceptions.RequestException as e:
            raise RuntimeError(f"Account query error: {e}")

    def get_balance(self, address: str) -> str:
        """Get FLOW balance for an address. Returns UFix64 string."""
        script = """
        access(all) fun main(address: Address): UFix64 {
            let account = getAccount(address)
            return account.balance
        }
        """
        result = self.execute_script(script, [{"type": "Address", "value": address}])
        return str(result) if result is not None else "0.0"

    # ------------------------------------------------------------------
    # Account Creation
    # ------------------------------------------------------------------

    def create_account(
        self,
        new_public_key_hex: str,
        sig_algo: str = "ECDSA_P256",
        hash_algo: str = "SHA3_256",
        key_weight: int = 1000,
        initial_flow: float = 0.001,
    ) -> str:
        """
        Create a new Flow account with the given public key.
        The signer account pays for creation and initial funding.

        Args:
            new_public_key_hex: P256 public key (X||Y, 64 bytes, no 04 prefix)
            sig_algo: Signature algorithm
            hash_algo: Hash algorithm
            key_weight: Key weight (1000 = full authority)
            initial_flow: FLOW to send to new account for storage

        Returns:
            New account address (0x prefixed)
        """
        # Map algo names to Cadence enum values
        sig_algo_value = {"ECDSA_P256": 1, "ECDSA_secp256k1": 2}.get(sig_algo, 1)
        hash_algo_value = {"SHA2_256": 1, "SHA3_256": 3}.get(hash_algo, 3)

        # Cadence transaction to create account with public key
        create_tx = f"""
        transaction(publicKey: String, sigAlgo: UInt8, hashAlgo: UInt8, weight: UFix64, fundAmount: UFix64) {{
            prepare(signer: auth(BorrowValue) &Account) {{
                // Create the new account
                let newAccount = Account(payer: signer)

                // Decode and add the public key
                let key = PublicKey(
                    publicKey: publicKey.decodeHex(),
                    signatureAlgorithm: sigAlgo == 1
                        ? SignatureAlgorithm.ECDSA_P256
                        : SignatureAlgorithm.ECDSA_secp256k1
                )

                newAccount.keys.add(
                    publicKey: key,
                    hashAlgorithm: hashAlgo == 3
                        ? HashAlgorithm.SHA3_256
                        : HashAlgorithm.SHA2_256,
                    weight: weight
                )

                // Fund the new account with initial FLOW for storage
                if fundAmount > 0.0 {{
                    let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                        from: /storage/flowTokenVault
                    )
                    if vaultRef != nil {{
                        let receiverRef = newAccount.capabilities.borrow<&{{FungibleToken.Receiver}}>(/public/flowTokenReceiver)
                        if receiverRef != nil {{
                            receiverRef!.deposit(from: <- vaultRef!.withdraw(amount: fundAmount))
                        }}
                    }}
                }}

                log("Account created: ".concat(newAccount.address.toString()))
            }}
        }}
        """

        # We need the contract imports
        create_tx_full = f"""
        import FlowToken from {self._get_contract_address("FlowToken")}
        import FungibleToken from {self._get_contract_address("FungibleToken")}

        {create_tx}
        """

        arguments = [
            {"type": "String", "value": new_public_key_hex},
            {"type": "UInt8", "value": str(sig_algo_value)},
            {"type": "UInt8", "value": str(hash_algo_value)},
            {"type": "UFix64", "value": f"{key_weight:.8f}"},
            {"type": "UFix64", "value": f"{initial_flow:.8f}"},
        ]

        result = self.send_transaction(create_tx_full, arguments)

        # Extract the new account address from events
        if result.get("events"):
            for event in result["events"]:
                event_type = event.get("type", "")
                if "AccountCreated" in event_type or "flow.AccountCreated" in event_type:
                    payload = event.get("payload", {})
                    if isinstance(payload, dict):
                        addr = payload.get("value", {}).get("fields", [{}])[0].get("value", {}).get("value", "")
                        if addr:
                            return addr if addr.startswith("0x") else "0x" + addr

        # Fallback: try to find address in transaction events
        logger.warning("Could not extract address from AccountCreated event, checking logs")

        raise RuntimeError(
            "Account created but could not extract address from events. "
            f"Transaction: {result.get('txId', 'unknown')}"
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _get_latest_block_id(self) -> str:
        """Get the latest sealed block ID."""
        try:
            resp = self._session.get(
                f"{self.access_node}/v1/blocks?height=sealed",
                timeout=15,
            )
            if resp.status_code == 200:
                blocks = resp.json()
                if isinstance(blocks, list) and blocks:
                    block_id = blocks[0].get("header", {}).get("id", "")
                    if block_id:
                        return block_id
            raise RuntimeError(f"Failed to get latest block: {resp.text[:200]}")
        except requests.exceptions.RequestException as e:
            raise RuntimeError(f"Block query error: {e}")

    def _get_sequence_number(self, address: str, key_index: int = 0) -> int:
        """Get the sequence number for a key on an account."""
        account = self.get_account(address)
        keys = account.get("keys", [])

        # Debug: log raw key data to diagnose format issues
        if keys:
            logger.info(f"Account {address} has {len(keys)} key(s), first key sample: {str(keys[0])[:200]}")
        else:
            logger.warning(f"Account {address} returned no keys")
            return 0

        for key in keys:
            if isinstance(key, dict):
                idx = key.get("index", key.get("key_index", -1))
                if int(idx) == key_index:
                    seq = key.get("sequence_number", key.get("sequenceNumber", 0))
                    logger.info(f"Sequence number for {address} key {key_index}: {seq}")
                    return int(seq)
            elif isinstance(key, str):
                # Keys might be base64-encoded; try to decode
                logger.info(f"Key is a string (possibly base64): {key[:80]}...")

        logger.warning(f"Key {key_index} not found for {address} (keys format: {type(keys[0]) if keys else 'empty'}), returning 0")
        return 0

    def _wait_for_seal(self, tx_id: str, timeout: int = 120) -> Dict:
        """Poll until transaction is sealed or timeout."""
        start = time.time()
        last_status = "UNKNOWN"

        while time.time() - start < timeout:
            try:
                resp = self._session.get(
                    f"{self.access_node}/v1/transaction_results/{tx_id}",
                    timeout=15,
                )
                if resp.status_code == 200:
                    data = resp.json()
                    status = data.get("status", "UNKNOWN")
                    status_code = data.get("status_code", 0)

                    if status != last_status:
                        logger.info(f"TX {tx_id[:16]}... status: {status}")
                        last_status = status

                    # SEALED = 4, or status string (API returns "Sealed" not "SEALED")
                    if status.upper() == "SEALED" or status_code == 4:
                        events = data.get("events", [])
                        error_message = data.get("error_message", "")

                        if error_message:
                            logger.error(f"TX {tx_id} sealed with error: {error_message}")
                            return {
                                "txId": tx_id,
                                "status": "SEALED",
                                "statusCode": 4,
                                "error": error_message,
                                "events": self._decode_events(events),
                                "sealed": True,
                            }

                        return {
                            "txId": tx_id,
                            "status": "SEALED",
                            "statusCode": 4,
                            "events": self._decode_events(events),
                            "sealed": True,
                        }

            except requests.exceptions.RequestException:
                pass  # Retry on transient errors

            # Exponential backoff: 0.5s, 1s, 2s, 2s, 2s, ...
            elapsed = time.time() - start
            sleep_time = min(2.0, 0.5 * (2 ** min(3, int(elapsed / 5))))
            time.sleep(sleep_time)

        logger.warning(f"TX {tx_id} timed out after {timeout}s (last status: {last_status})")
        return {
            "txId": tx_id,
            "status": last_status,
            "statusCode": 0,
            "sealed": False,
            "error": f"Timed out after {timeout}s",
        }

    def _decode_events(self, events: list) -> list:
        """Decode base64-encoded event payloads."""
        decoded = []
        for event in events:
            e = dict(event)
            if "payload" in e and isinstance(e["payload"], str):
                try:
                    payload_json = base64.b64decode(e["payload"]).decode("utf-8")
                    e["payload"] = json.loads(payload_json)
                except Exception:
                    pass  # Keep raw payload
            decoded.append(e)
        return decoded

    def _decode_cadence_value(self, value: Any) -> Any:
        """
        Decode a JSON-CDC value to a Python value.
        Handles common types: String, Int, UInt64, UFix64, Address, Bool, Array, etc.
        """
        if not isinstance(value, dict):
            return value

        v_type = value.get("type", "")
        v_value = value.get("value")

        if v_type in ("String", "Character"):
            return v_value
        elif v_type in ("Int", "Int8", "Int16", "Int32", "Int64", "Int128", "Int256",
                         "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "UInt128", "UInt256"):
            return int(v_value) if v_value else 0
        elif v_type in ("Fix64", "UFix64"):
            return v_value  # Keep as string for precision
        elif v_type == "Bool":
            return v_value
        elif v_type == "Address":
            return v_value
        elif v_type == "Array":
            return [self._decode_cadence_value(item) for item in (v_value or [])]
        elif v_type == "Dictionary":
            result = {}
            for item in (v_value or []):
                k = self._decode_cadence_value(item.get("key"))
                v = self._decode_cadence_value(item.get("value"))
                result[str(k)] = v
            return result
        elif v_type in ("Optional",):
            return self._decode_cadence_value(v_value) if v_value else None
        elif v_type == "Void":
            return None
        elif v_type in ("Struct", "Resource", "Event"):
            fields = {}
            for f in v_value.get("fields", []):
                fields[f["name"]] = self._decode_cadence_value(f["value"])
            return fields
        else:
            return v_value

    def _get_contract_address(self, contract_name: str) -> str:
        """Get the standard contract address for the current network."""
        addresses = {
            "testnet": {
                "FlowToken": "0x7e60df042a9c0868",
                "FungibleToken": "0x9a0766d93b6608b7",
                "NonFungibleToken": "0x631e88ae7f1d7c20",
                "MetadataViews": "0x631e88ae7f1d7c20",
                "HybridCustody": "0xd8a7e05a7ac670c0",
                "CapabilityFactory": "0xd8a7e05a7ac670c0",
                "CapabilityFilter": "0xd8a7e05a7ac670c0",
            },
            "mainnet": {
                "FlowToken": "0x1654653399040a61",
                "FungibleToken": "0xf233dcee88fe0abe",
                "NonFungibleToken": "0x1d7e57aa55817448",
                "MetadataViews": "0x1d7e57aa55817448",
                "HybridCustody": "0xd8a7e05a7ac670c0",
                "CapabilityFactory": "0xd8a7e05a7ac670c0",
                "CapabilityFilter": "0xd8a7e05a7ac670c0",
            },
            "emulator": {
                "FlowToken": "0x0ae53cb6e3f42a79",
                "FungibleToken": "0xee82856bf20e2aa6",
                "NonFungibleToken": "0xf8d6e0586b0a20c7",
                "MetadataViews": "0xf8d6e0586b0a20c7",
            },
        }
        return addresses.get(self.network, addresses["testnet"]).get(contract_name, "0x0")

    def close(self):
        """Close the HTTP session."""
        self._session.close()

    def __repr__(self):
        return f"FlowRESTClient(network={self.network}, signer={self.signer_address})"
