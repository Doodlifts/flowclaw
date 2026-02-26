// get_account_keys.cdc
//
// Account Keys Query Script for FlowClaw
// This script retrieves all keys from a specified account and returns detailed key information.
//
// Purpose:
// - Audit and verify multi-key security setup
// - Monitor key weights and algorithm configurations
// - Validate that multi-signature thresholds are properly configured
//
// Returns:
// An array of AccountKey structures containing:
//   - index: The key index in the account's key list
//   - publicKey: The public key bytes in hex format
//   - signatureAlgorithm: The signing algorithm (1, 2, or 3)
//   - hashAlgorithm: The hashing algorithm (1-7)
//   - weight: The key weight for signature thresholds
//   - isRevoked: Whether the key has been revoked

access(all)
struct AccountKey {
    access(all) let index: Int
    access(all) let publicKey: String
    access(all) let signatureAlgorithm: UInt8
    access(all) let hashAlgorithm: UInt8
    access(all) let weight: UFix64
    access(all) let isRevoked: Bool

    init(
        index: Int,
        publicKey: String,
        signatureAlgorithm: UInt8,
        hashAlgorithm: UInt8,
        weight: UFix64,
        isRevoked: Bool
    ) {
        self.index = index
        self.publicKey = publicKey
        self.signatureAlgorithm = signatureAlgorithm
        self.hashAlgorithm = hashAlgorithm
        self.weight = weight
        self.isRevoked = isRevoked
    }
}

access(all)
fun main(address: Address): [AccountKey] {
    // Get the account from the given address
    let account = getAccount(address)

    // Initialize array to hold key information
    var keys: [AccountKey] = []

    // Iterate through all keys on the account
    let keyCount = account.keys.count
    var index = 0

    while index < keyCount {
        let key = account.keys.get(keyIndex: index)

        // Convert public key bytes to hex string for easier reading
        let publicKeyHex = key.publicKey.toString()

        // Create AccountKey struct with key information
        let accountKey = AccountKey(
            index: index,
            publicKey: publicKeyHex,
            signatureAlgorithm: key.signatureAlgorithm.rawValue,
            hashAlgorithm: key.hashAlgorithm.rawValue,
            weight: key.weight,
            isRevoked: key.isRevoked
        )

        // Add to results array
        keys.append(accountKey)

        index = index + 1
    }

    return keys
}
