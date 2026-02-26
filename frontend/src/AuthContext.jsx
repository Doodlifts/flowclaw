// FlowClaw — Auth Context
// Manages wallet connection, passkey auth, and session tokens.
// Three auth methods: passkey (recommended), FCL wallet, email (stub)

import { createContext, useContext, useState, useEffect } from "react";
import { fcl } from "./flow-config";

const AuthContext = createContext(null);

const API_BASE = window.location.hostname === 'localhost'
  ? 'http://localhost:8000'
  : 'https://web-production-9784a.up.railway.app';

// -----------------------------------------------------------------------
// WebAuthn / Passkey Helpers
// -----------------------------------------------------------------------

function bufferToBase64url(buffer) {
  const bytes = new Uint8Array(buffer);
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlToBuffer(base64url) {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

function extractP256PublicKey(attestationResponse) {
  // The public key is in the attestation object's authData
  // For PoC, we extract from getPublicKey() which returns a SubjectPublicKeyInfo
  const pubKeyDer = attestationResponse.getPublicKey();
  if (!pubKeyDer) throw new Error("No public key in attestation response");

  // SubjectPublicKeyInfo for P256: 26 bytes header + 65 bytes uncompressed point
  // The uncompressed point starts with 0x04 followed by 64 bytes (X || Y)
  const pubKeyBytes = new Uint8Array(pubKeyDer);

  // Find the 0x04 prefix that marks uncompressed EC point
  let offset = -1;
  for (let i = 0; i < pubKeyBytes.length - 64; i++) {
    if (pubKeyBytes[i] === 0x04) {
      // Verify this looks like a valid EC point (remaining bytes)
      if (pubKeyBytes.length - i >= 65) {
        offset = i;
        break;
      }
    }
  }

  if (offset === -1) throw new Error("Could not find uncompressed EC point in public key");

  // Extract X || Y (64 bytes, without the 04 prefix)
  const xyBytes = pubKeyBytes.slice(offset + 1, offset + 65);
  // Convert to hex
  return Array.from(xyBytes).map(b => b.toString(16).padStart(2, "0")).join("");
}

// -----------------------------------------------------------------------
// Auth Provider
// -----------------------------------------------------------------------

export function AuthProvider({ children }) {
  const [user, setUser] = useState({ loggedIn: null, addr: null });
  const [initialized, setInitialized] = useState(false);
  const [loading, setLoading] = useState(true);
  const [authMethod, setAuthMethod] = useState(null); // "passkey", "wallet", "email"
  const [custodyType, setCustodyType] = useState("standalone");
  const [sessionToken, setSessionToken] = useState(null);
  const [passkeyCreating, setPasskeyCreating] = useState(false);

  // Subscribe to FCL current user (for wallet-connected users)
  useEffect(() => {
    const unsub = fcl.currentUser.subscribe((currentUser) => {
      if (currentUser.loggedIn && !authMethod) {
        setUser(currentUser);
        setAuthMethod("wallet");
      }
      setLoading(false);
    });
    return () => unsub();
  }, [authMethod]);

  // Restore session from localStorage on mount
  useEffect(() => {
    const storedToken = localStorage.getItem("flowclaw_session_token");
    const storedAddr = localStorage.getItem("flowclaw_address");
    const storedMethod = localStorage.getItem("flowclaw_auth_method");
    const storedCredential = localStorage.getItem("flowclaw_credential_id");

    if (storedToken && storedAddr) {
      // Verify token is still valid
      fetch(`${API_BASE}/account/status`, {
        headers: { Authorization: `Bearer ${storedToken}` },
      })
        .then((r) => r.ok ? r.json() : null)
        .then((data) => {
          if (data) {
            setUser({ loggedIn: true, addr: storedAddr });
            setAuthMethod(storedMethod || "passkey");
            setSessionToken(storedToken);
            setCustodyType(data.custodyType || "standalone");
            setInitialized(true);
          } else {
            // Token expired, clear
            localStorage.removeItem("flowclaw_session_token");
          }
          setLoading(false);
        })
        .catch(() => setLoading(false));
    } else {
      setLoading(false);
    }
  }, []);

  // Check if account has FlowClaw resources
  useEffect(() => {
    if (user.loggedIn && user.addr) {
      checkInitialized(user.addr);
    } else {
      setInitialized(false);
    }
  }, [user.loggedIn, user.addr]);

  const checkInitialized = async (addr) => {
    try {
      const res = await fetch(`${API_BASE}/status`);
      const status = await res.json();
      setInitialized(status.connected);
    } catch {
      setInitialized(false);
    }
  };

  // ------------------------------------------------------------------
  // Passkey: Create Account
  // ------------------------------------------------------------------
  const createPasskeyAccount = async (displayName = "FlowClaw User") => {
    if (!window.PublicKeyCredential) {
      throw new Error("WebAuthn is not supported in this browser");
    }

    setPasskeyCreating(true);
    try {
      // Generate a random user ID
      const userId = new Uint8Array(32);
      crypto.getRandomValues(userId);

      // Create WebAuthn credential with P256 key
      const credential = await navigator.credentials.create({
        publicKey: {
          challenge: crypto.getRandomValues(new Uint8Array(32)),
          rp: {
            name: "FlowClaw",
            id: window.location.hostname,
          },
          user: {
            id: userId,
            name: displayName,
            displayName: displayName,
          },
          pubKeyCredParams: [
            { type: "public-key", alg: -7 }, // ES256 = ECDSA with P-256 and SHA-256
          ],
          authenticatorSelection: {
            residentKey: "preferred",
            userVerification: "required",
          },
          timeout: 60000,
          attestation: "none", // We don't need attestation for this use case
        },
      });

      if (!credential) throw new Error("Passkey creation cancelled");

      // Extract the P256 public key
      const publicKeyHex = extractP256PublicKey(credential.response);
      const credentialId = bufferToBase64url(credential.rawId);

      // Send to relay to create Flow account
      const res = await fetch(`${API_BASE}/account/create-passkey`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          publicKey: publicKeyHex,
          credentialId: credentialId,
          displayName: displayName,
        }),
      });

      if (!res.ok) {
        const err = await res.text();
        throw new Error(`Account creation failed: ${err}`);
      }

      const data = await res.json();

      // Store credentials locally
      localStorage.setItem("flowclaw_credential_id", credentialId);
      localStorage.setItem("flowclaw_address", data.address);
      localStorage.setItem("flowclaw_auth_method", "passkey");
      if (data.token) {
        localStorage.setItem("flowclaw_session_token", data.token);
        setSessionToken(data.token);
      }

      // Update state
      setUser({ loggedIn: true, addr: data.address });
      setAuthMethod("passkey");
      setInitialized(true);

      return data;
    } finally {
      setPasskeyCreating(false);
    }
  };

  // ------------------------------------------------------------------
  // Passkey: Sign In (returning user)
  // ------------------------------------------------------------------
  const authenticatePasskey = async () => {
    if (!window.PublicKeyCredential) {
      throw new Error("WebAuthn is not supported in this browser");
    }

    const storedCredentialId = localStorage.getItem("flowclaw_credential_id");

    try {
      // Request assertion — let the browser find the right passkey
      const assertionOptions = {
        publicKey: {
          challenge: crypto.getRandomValues(new Uint8Array(32)),
          timeout: 60000,
          userVerification: "required",
          rpId: window.location.hostname,
        },
      };

      // If we have a stored credential, provide it as allowCredentials
      if (storedCredentialId) {
        assertionOptions.publicKey.allowCredentials = [
          {
            type: "public-key",
            id: base64urlToBuffer(storedCredentialId),
          },
        ];
      }

      const assertion = await navigator.credentials.get(assertionOptions);
      if (!assertion) throw new Error("Passkey authentication cancelled");

      const credentialId = bufferToBase64url(assertion.rawId);

      // Verify with relay
      const res = await fetch(`${API_BASE}/account/verify-passkey`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          credentialId: credentialId,
          clientDataJSON: bufferToBase64url(assertion.response.clientDataJSON),
          authenticatorData: bufferToBase64url(assertion.response.authenticatorData),
          signature: bufferToBase64url(assertion.response.signature),
        }),
      });

      if (!res.ok) throw new Error("Passkey verification failed");

      const data = await res.json();

      // Store session
      localStorage.setItem("flowclaw_credential_id", credentialId);
      localStorage.setItem("flowclaw_address", data.address);
      localStorage.setItem("flowclaw_auth_method", "passkey");
      if (data.token) {
        localStorage.setItem("flowclaw_session_token", data.token);
        setSessionToken(data.token);
      }

      setUser({ loggedIn: true, addr: data.address });
      setAuthMethod("passkey");
      setCustodyType(data.custodyType || "standalone");
      setInitialized(true);

      return data;
    } catch (err) {
      console.error("Passkey auth failed:", err);
      throw err;
    }
  };

  // ------------------------------------------------------------------
  // FCL Wallet Connect
  // ------------------------------------------------------------------
  const connectWallet = () => {
    setAuthMethod("wallet");
    return fcl.authenticate();
  };

  // ------------------------------------------------------------------
  // Disconnect
  // ------------------------------------------------------------------
  const disconnectWallet = () => {
    fcl.unauthenticate();
    setUser({ loggedIn: false, addr: null });
    setInitialized(false);
    setAuthMethod(null);
    setSessionToken(null);
    setCustodyType("standalone");

    // Clear stored session
    localStorage.removeItem("flowclaw_session_token");
    localStorage.removeItem("flowclaw_address");
    localStorage.removeItem("flowclaw_auth_method");
    localStorage.removeItem("flowclaw_credential_id");
  };

  // ------------------------------------------------------------------
  // Email login (stub)
  // ------------------------------------------------------------------
  const loginWithEmail = async (email) => {
    try {
      const res = await fetch(`${API_BASE}/auth/email`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      if (res.ok) {
        const data = await res.json();
        setUser({ loggedIn: true, addr: data.address, custodial: true });
        setAuthMethod("email");
        setInitialized(true);
        return data;
      }
    } catch (err) {
      console.error("Email login failed:", err);
    }
    return null;
  };

  // ------------------------------------------------------------------
  // Account Linking (Hybrid Custody)
  // ------------------------------------------------------------------
  const initiateLink = async (parentAddress) => {
    try {
      const res = await fetch(`${API_BASE}/account/initiate-link`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(sessionToken ? { Authorization: `Bearer ${sessionToken}` } : {}),
        },
        body: JSON.stringify({ parentAddress }),
      });
      if (res.ok) {
        const data = await res.json();
        if (data.success) setCustodyType("linking");
        return data;
      }
    } catch (err) {
      console.error("Link initiation failed:", err);
    }
    return null;
  };

  const checkCustodyStatus = async () => {
    try {
      const res = await fetch(`${API_BASE}/account/custody-status`, {
        headers: sessionToken ? { Authorization: `Bearer ${sessionToken}` } : {},
      });
      if (res.ok) {
        const data = await res.json();
        setCustodyType(data.type || "standalone");
        return data;
      }
    } catch {}
    return null;
  };

  // ------------------------------------------------------------------
  // Context value
  // ------------------------------------------------------------------
  const value = {
    user,
    loading,
    initialized,
    isLoggedIn: user.loggedIn === true,
    address: user.addr,
    authMethod,
    custodyType,
    sessionToken,
    isCustodial: user.custodial || false,
    passkeyCreating,
    hasStoredPasskey: !!localStorage.getItem("flowclaw_credential_id"),

    // Auth methods
    connectWallet,
    disconnectWallet,
    loginWithEmail,
    createPasskeyAccount,
    authenticatePasskey,

    // Account linking
    initiateLink,
    checkCustodyStatus,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
};
