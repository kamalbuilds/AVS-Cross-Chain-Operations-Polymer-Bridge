### Key Changes made to the old contract

1. **Inheritance from `UniversalChanIbcApp`**: The `CrossChainMultisig` contract now inherits from `UniversalChanIbcApp`.
2. **Constructor**: The constructor now accepts an additional `_middleware` parameter for the `UniversalChanIbcApp` initialization.
3. **IBC Methods**: Added methods `crosschainConfirmTransaction`, `onRecvUniversalPacket`, `onUniversalAcknowledgement`, and `onTimeoutUniversalPacket` to handle cross-chain communication.
4. **Confirmation and Execution**: Updated the confirmation logic to handle cross-chain confirmations using IBC.