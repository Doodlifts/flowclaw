// authorize_relay.cdc
// Authorize an off-chain relay address to post inference results for this account.
// The relay is the bridge between on-chain events and off-chain LLM providers.
// Each account controls exactly which relays can interact with their agent.

import "InferenceOracle"

transaction(relayAddress: Address, label: String) {
    prepare(signer: auth(Storage) &Account) {
        let oracleConfig = signer.storage.borrow<auth(InferenceOracle.ManageRelays) &InferenceOracle.OracleConfig>(
            from: InferenceOracle.OracleConfigStoragePath
        ) ?? panic("OracleConfig not found. Run initialize_account first.")

        oracleConfig.authorizeRelay(relayAddress: relayAddress, label: label)
    }

    execute {
        log("Relay authorized successfully")
    }
}
