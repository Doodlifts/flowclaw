// FlowClaw — Client-side Transaction Signing
// Uses SubtleCrypto P256 keys (separate from passkeys) to sign Flow transactions.
//
// Flow transaction signing:
//   1. Relay builds unsigned tx → returns payloadHex (TRANSACTION_DOMAIN_TAG + RLP)
//   2. Browser signs payloadHex with SubtleCrypto ECDSA P-256 + SHA-256
//   3. Browser sends signature back to relay
//   4. Relay adds payer (sponsor) envelope signature and submits

// -----------------------------------------------------------------------
// Key Management
// -----------------------------------------------------------------------

/**
 * Generate a new P256 signing key pair via SubtleCrypto.
 * Returns { publicKeyHex, privateKeyJwk }
 */
export async function generateSigningKeyPair() {
  const keyPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true, // extractable — we need to export/store the private key
    ["sign", "verify"]
  );

  // Export private key as JWK for localStorage storage
  const privateKeyJwk = await crypto.subtle.exportKey("jwk", keyPair.privateKey);

  // Export public key as raw bytes (65 bytes: 04 || X || Y)
  const publicKeyRaw = await crypto.subtle.exportKey("raw", keyPair.publicKey);
  const publicKeyBytes = new Uint8Array(publicKeyRaw);

  // Strip the 04 prefix — Flow expects just X||Y (64 bytes = 128 hex chars)
  const xyBytes = publicKeyBytes.slice(1); // Remove 0x04 prefix
  const publicKeyHex = Array.from(xyBytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return { publicKeyHex, privateKeyJwk };
}

/**
 * Store a signing key in localStorage, keyed by Flow address.
 */
export function storeSigningKey(address, privateKeyJwk) {
  const key = `flowclaw_signing_key_${address}`;
  localStorage.setItem(key, JSON.stringify(privateKeyJwk));
}

/**
 * Load a signing key from localStorage by Flow address.
 * Returns the JWK object or null if not found.
 */
export function loadSigningKey(address) {
  const key = `flowclaw_signing_key_${address}`;
  const stored = localStorage.getItem(key);
  if (!stored) return null;
  try {
    return JSON.parse(stored);
  } catch {
    return null;
  }
}

/**
 * Remove a signing key from localStorage.
 */
export function removeSigningKey(address) {
  localStorage.removeItem(`flowclaw_signing_key_${address}`);
}

/**
 * Check if a signing key exists for the given address.
 */
export function hasSigningKey(address) {
  return !!localStorage.getItem(`flowclaw_signing_key_${address}`);
}

// -----------------------------------------------------------------------
// Transaction Signing
// -----------------------------------------------------------------------

/**
 * Sign a Flow transaction payload using the stored SubtleCrypto key.
 *
 * @param {string} payloadHex - Hex-encoded bytes to sign (domain_tag + RLP payload)
 * @param {string} userAddress - Flow address of the signer
 * @returns {string} Base64-encoded raw signature (r||s, 64 bytes)
 */
export async function signFlowPayload(payloadHex, userAddress) {
  // 1. Load private key from localStorage
  const jwk = loadSigningKey(userAddress);
  if (!jwk) {
    throw new Error(
      `No signing key found for ${userAddress}. ` +
      `Please create a new account or restore your signing key.`
    );
  }

  // 2. Import as SubtleCrypto CryptoKey
  const privateKey = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false, // not extractable (we already have the JWK)
    ["sign"]
  );

  // 3. Convert payloadHex to Uint8Array
  const payloadBytes = hexToBytes(payloadHex);

  // 4. Sign with ECDSA P-256 + SHA-256
  //    This matches Flow's SHA2_256 hash algorithm for user accounts
  const signatureBuffer = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    payloadBytes
  );

  // 5. SubtleCrypto returns DER-encoded signature — convert to raw r||s (64 bytes)
  const rawSignature = derToRaw(new Uint8Array(signatureBuffer));

  // 6. Return base64-encoded
  return bytesToBase64(rawSignature);
}

// -----------------------------------------------------------------------
// Utilities
// -----------------------------------------------------------------------

/**
 * Convert hex string to Uint8Array.
 */
function hexToBytes(hex) {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(clean.substr(i * 2, 2), 16);
  }
  return bytes;
}

/**
 * Convert Uint8Array to base64 string.
 */
function bytesToBase64(bytes) {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

/**
 * Convert DER-encoded ECDSA signature to raw (r || s) format.
 * DER format: 30 <len> 02 <r_len> <r_bytes> 02 <s_len> <s_bytes>
 * Raw format: r (32 bytes, zero-padded) || s (32 bytes, zero-padded)
 */
function derToRaw(der) {
  // Parse DER structure
  if (der[0] !== 0x30) {
    throw new Error("Invalid DER signature: expected SEQUENCE tag 0x30");
  }

  let offset = 2; // Skip SEQUENCE tag and length

  // Parse r
  if (der[offset] !== 0x02) throw new Error("Invalid DER: expected INTEGER tag for r");
  offset++;
  const rLen = der[offset];
  offset++;
  let rBytes = der.slice(offset, offset + rLen);
  offset += rLen;

  // Parse s
  if (der[offset] !== 0x02) throw new Error("Invalid DER: expected INTEGER tag for s");
  offset++;
  const sLen = der[offset];
  offset++;
  let sBytes = der.slice(offset, offset + sLen);

  // Strip leading zero byte (DER uses it for positive sign on high-bit numbers)
  if (rBytes.length === 33 && rBytes[0] === 0x00) rBytes = rBytes.slice(1);
  if (sBytes.length === 33 && sBytes[0] === 0x00) sBytes = sBytes.slice(1);

  // Pad to 32 bytes each (in case they're shorter)
  const raw = new Uint8Array(64);
  raw.set(rBytes, 32 - rBytes.length); // right-aligned in first 32 bytes
  raw.set(sBytes, 64 - sBytes.length); // right-aligned in second 32 bytes

  return raw;
}
