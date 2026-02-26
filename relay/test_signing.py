#!/usr/bin/env python3
"""
Diagnostic: Test Flow REST transaction signing.
Run from flowclaw root: python3.11 relay/test_signing.py
"""
import sys, os, json, hashlib, base64
sys.path.insert(0, os.path.dirname(__file__))

from flow_client import FlowRESTClient, rlp_encode, TRANSACTION_DOMAIN_TAG, _address_bytes

# Load env
from pathlib import Path
try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / ".env")
except ImportError:
    pass

pk = os.getenv("FLOW_PRIVATE_KEY", "")
addr = os.getenv("FLOW_ACCOUNT_ADDRESS", "")
network = os.getenv("FLOW_NETWORK", "testnet")

print(f"Account: {addr}")
print(f"Network: {network}")
print(f"Key (first 8): {pk[:8]}...")

# Check OpenSSL version
try:
    from cryptography.hazmat.backends.openssl import backend
    print(f"OpenSSL: {backend.openssl_version_text()}")
except:
    print("OpenSSL: unknown")

# Derive and show public key
from cryptography.hazmat.primitives.asymmetric import ec, utils
from cryptography.hazmat.primitives import hashes

private_key_int = int(pk, 16)
private_key = ec.derive_private_key(private_key_int, ec.SECP256R1())
pub = private_key.public_key().public_numbers()
pub_hex = format(pub.x, '064x') + format(pub.y, '064x')
print(f"Derived public key: {pub_hex[:24]}...{pub_hex[-24:]}")
print()

client = FlowRESTClient(
    network=network,
    signer_address=addr,
    signer_private_key_hex=pk,
)

# Load aliases
flow_json = os.path.join(os.getenv("FLOWCLAW_PROJECT_DIR", str(Path(__file__).parent.parent)), "flow.json")
if os.path.exists(flow_json):
    client.load_aliases_from_flow_json(flow_json)

# ---- TEST 1: Script (no signing) ----
print("=== TEST 1: Script execution (no signing) ===")
try:
    result = client.execute_script(
        'access(all) fun main(): String { return "hello from REST" }',
    )
    print(f"  Result: {result}")
    print("  STATUS: PASS")
except Exception as e:
    print(f"  ERROR: {e}")
    print("  STATUS: FAIL")
print()

# ---- TEST 2: Minimal transaction (now with direct SHA3 signing) ----
print("=== TEST 2: Transaction with NO arguments (direct SHA3 signing) ===")
tx_code = """
transaction() {
    prepare(signer: &Account) {
        log("REST signing test")
    }
}
"""
try:
    result = client.send_transaction(tx_code, arguments=None, timeout=30)
    print(f"  TX ID: {result.get('txId', 'none')}")
    print(f"  Status: {result.get('status', 'unknown')}")
    err = result.get('error', '')
    if err:
        print(f"  Error: {err[:200]}")
        print("  STATUS: FAIL")
    else:
        print("  STATUS: PASS")
except Exception as e:
    print(f"  ERROR: {e}")
    print("  STATUS: FAIL")
print()

# ---- DIAGNOSTIC: Dump RLP bytes for manual comparison ----
print("=== DIAGNOSTIC: RLP byte dump ===")
try:
    ref_block_id = client._get_latest_block_id()
    seq_number = client._get_sequence_number(addr, 0)

    script_bytes = tx_code.encode("utf-8")
    ref_block_bytes = bytes.fromhex(ref_block_id)
    proposer_bytes = _address_bytes(addr)

    payload_fields = [
        script_bytes,
        [],  # no arguments
        ref_block_bytes,
        9999,  # gas limit
        proposer_bytes,   # proposal key address (FLAT, not nested)
        0,                # proposal key index (FLAT)
        seq_number,       # proposal key sequence number (FLAT)
        proposer_bytes,   # payer
        [proposer_bytes],  # authorizers
    ]

    envelope_fields = [payload_fields, []]
    envelope_rlp = rlp_encode(envelope_fields)
    message = TRANSACTION_DOMAIN_TAG + envelope_rlp
    digest = hashlib.sha3_256(message).digest()

    print(f"  Domain tag hex: {TRANSACTION_DOMAIN_TAG.hex()}")
    print(f"  Domain tag len: {len(TRANSACTION_DOMAIN_TAG)}")
    print(f"  Ref block: {ref_block_id}")
    print(f"  Seq number: {seq_number}")
    print(f"  Script len: {len(script_bytes)} bytes")
    print(f"  Proposer bytes: {proposer_bytes.hex()}")
    print(f"  Payload RLP: {rlp_encode(payload_fields).hex()}")
    print(f"  Envelope RLP: {envelope_rlp.hex()}")
    print(f"  Full message hex: {message.hex()}")
    print(f"  SHA3-256 digest: {digest.hex()}")

except Exception as e:
    print(f"  DIAGNOSTIC ERROR: {e}")
    import traceback
    traceback.print_exc()

print()
print("Done!")
