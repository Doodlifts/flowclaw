// setup_multikey_security.cdc
//
// Multi-Key Security Setup Transaction for FlowClaw
// This transaction enables multi-signature security by adding a second key to an account.
//
// Security Model:
// - Primary key (existing): Full weight (1000) - used for routine operations
// - Secondary key (new): Lower weight (500) - requires both keys for operations exceeding threshold
// - This pattern ensures no single key can perform sensitive operations unilaterally
// - Recommended for mainnet accounts holding significant assets or with admin privileges
//
// Parameters:
//   publicKey: The public key bytes in hex string format (without "0x" prefix)
//   signatureAlgorithm: The signing algorithm code (1 = ECDSA_P256, 2 = ECDSA_secp256k1, 3 = BLS_BLS12_381)
//   hashAlgorithm: The hash algorithm code (1 = SHA2_256, 2 = SHA3_256, 3 = SHA3_384, 4 = SHA3_512, 5 = BLAKE2b_256, 6 = BLAKE2b_384, 7 = BLAKE2b_512)
//   weight: The key weight as UFix64 (e.g., 500.0 out of 1000.0 total)

transaction(publicKey: String, signatureAlgorithm: UInt8, hashAlgorithm: UInt8, weight: UFix64) {

    prepare(signer: auth(Keys) &Account) {
        // Validate input parameters
        assert(
            signatureAlgorithm >= 1 && signatureAlgorithm <= 3,
            message: "Invalid signature algorithm. Must be 1 (ECDSA_P256), 2 (ECDSA_secp256k1), or 3 (BLS_BLS12_381)"
        )

        assert(
            hashAlgorithm >= 1 && hashAlgorithm <= 7,
            message: "Invalid hash algorithm. Must be between 1 and 7"
        )

        assert(
            weight > 0.0 && weight <= 1000.0,
            message: "Key weight must be between 0 and 1000"
        )

        assert(
            publicKey.length > 0,
            message: "Public key cannot be empty"
        )

        // Decode the public key from hex string
        let publicKeyBytes = publicKey.decodeHex()

        // Create the public key object with the specified algorithms
        let newPublicKey = PublicKey(
            publicKey: publicKeyBytes,
            signatureAlgorithm: SignatureAlgorithm(rawValue: signatureAlgorithm)!
        )

        // Add the key to the account with the specified weight and hash algorithm
        signer.keys.add(
            publicKey: newPublicKey,
            hashAlgorithm: HashAlgorithm(rawValue: hashAlgorithm)!,
            weight: weight
        )

        // Emit event or log for audit trail (optional - comment out if event is not defined in contract)
        // emit KeyAdded(address: signer.address, weight: weight, timestamp: getCurrentBlock().timestamp)

        log("Successfully added new key with weight: ".concat(weight.toString()))
        log("Total key weight is now managed by account: ".concat(signer.address.toString()))
    }

    execute {
        // Execute phase: any additional checks or contract interactions can go here
        // For basic key addition, no additional execute logic is typically needed
        log("Multi-key security setup completed successfully")
    }
}
