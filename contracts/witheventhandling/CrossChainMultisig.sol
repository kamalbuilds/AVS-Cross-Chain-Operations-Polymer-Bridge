// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../base/UniversalChanIbcApp.sol";
import "../OperatorRegistery.sol";

import "@openzeppelin/contracts/utils/Counters.sol";

contract CrossChainMultisig is UniversalChanIbcApp {
    using Counters for Counters.Counter;
    Counters.Counter private _transactionIds;

    struct Transaction {
        address destination;
        uint value;
        bytes data;
        bool executed;
    }

    struct Confirmation {
        bool exists;
        uint count;
    }

    OperatorRegistry public operatorRegistry;
    address[] public owners;
    uint public required;
    mapping(uint => mapping(address => bool)) public confirmations;
    Transaction[] public transactions;
    mapping(address => bool) public isOwner;

    event Submission(uint indexed transactionId);
    event ConfirmationReceived(address indexed sender, uint indexed transactionId);
    event Execution(uint indexed transactionId);
    event ExecutionFailure(uint indexed transactionId);
    event AVSVerificationRequested(uint indexed transactionId);
    event AVSVerificationResult(uint indexed transactionId, bool verified);
    event AVSSlashingInitiated(uint indexed transactionId, address[] owners);

    modifier onlyOwner() {
        require(operatorRegistry.isOperator(msg.sender), "Caller is not an operator");
        _;
    }

    modifier onlyOperator() {
        require(isOwner[msg.sender], "Not an owner");
        _;
    }

    modifier confirmed(uint transactionId, address owner) {
        require(confirmations[transactionId][owner], "Transaction not confirmed by this owner");
        _;
    }

    modifier notConfirmed(uint transactionId, address owner) {
        require(!confirmations[transactionId][owner], "Transaction already confirmed by this owner");
        _;
    }

    modifier notExecuted(uint transactionId) {
        require(!transactions[transactionId].executed, "Transaction already executed");
        _;
    }

    modifier transactionExists(uint transactionId) {
        require(transactions.length > transactionId, "Transaction does not exist");
        _;
    }

    constructor(address _middleware, address[] memory _owners, uint _required)
        UniversalChanIbcApp(_middleware)
    {
        require(_owners.length > 0, "Owners required");
        require(_required > 0 && _required <= _owners.length, "Invalid required number of confirmations");

        for (uint i = 0; i < _owners.length; i++) {
            require(_owners[i] != address(0), "Invalid owner");
            require(!isOwner[_owners[i]], "Owner not unique");

            isOwner[_owners[i]] = true;
            owners.push(_owners[i]);
        }
        required = _required;
    }

    function submitTransaction(address destination, uint value, bytes memory data) public onlyOperator returns (uint transactionId) {
        transactionId = _transactionIds.current();
        _transactionIds.increment();
        transactions.push(Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false
        }));
        emit Submission(transactionId);
        emit AVSVerificationRequested(transactionId);
        // Initiate AVS verification process
        // ...
        return transactionId;
    }

    function confirmTransaction(uint transactionId) public onlyOperator transactionExists(transactionId) notConfirmed(transactionId, msg.sender) {
        confirmations[transactionId][msg.sender] = true;
        emit ConfirmationReceived(msg.sender, transactionId);
        executeTransaction(transactionId);
    }

    function executeTransaction(uint transactionId) public onlyOperator confirmed(transactionId, msg.sender) notExecuted(transactionId) {
        if (isConfirmed(transactionId)) {
            Transaction storage txn = transactions[transactionId];
            txn.executed = true;
            (bool success, ) = txn.destination.call{value: txn.value}(txn.data);
            if (success)
                emit Execution(transactionId);
            else {
                emit ExecutionFailure(transactionId);
                txn.executed = false;
            }
            // Notify AVS about the execution result
            emit AVSVerificationResult(transactionId, success);
        }
    }

    function isConfirmed(uint transactionId) public view returns (bool) {
        uint count = 0;
        for (uint i = 0; i < owners.length; i++) {
            if (confirmations[transactionId][owners[i]])
                count += 1;
            if (count == required)
                return true;
        }
        return false;
    }

    // IBC methods

    function crosschainConfirmTransaction(
        address destPortAddr,
        bytes32 channelId,
        uint transactionId,
        address owner
    ) public onlyOperator transactionExists(transactionId) notConfirmed(transactionId, owner) {
        bytes memory payload = abi.encode(transactionId, owner);
        uint64 timeoutTimestamp = uint64(block.timestamp) + 2 hours;
        IbcUniversalPacketSender(mw).sendUniversalPacket(
            channelId,
            IbcUtils.toBytes32(destPortAddr),
            payload,
            timeoutTimestamp
        );
        confirmations[transactionId][owner] = true;
        emit ConfirmationReceived(owner, transactionId);
    }

    function onRecvUniversalPacket(bytes32 channelId, UniversalPacket calldata packet)
        external
        override
        onlyIbcMw
        returns (AckPacket memory ackPacket)
    {
        recvedPackets.push(UcPacketWithChannel(channelId, packet));

        (uint transactionId, address owner) = abi.decode(packet.appData, (uint, address));
        confirmations[transactionId][owner] = true;

        if (isConfirmed(transactionId)) {
            executeTransaction(transactionId);
        }

        return AckPacket(true, abi.encode(transactionId, owner));
    }

    function onUniversalAcknowledgement(bytes32 channelId, UniversalPacket memory packet, AckPacket calldata ack)
        external
        override
        onlyIbcMw
    {
        ackPackets.push(UcAckWithChannel(channelId, packet, ack));
    }

    function onTimeoutUniversalPacket(bytes32 channelId, UniversalPacket calldata packet)
        external
        override
        onlyIbcMw
    {
        timeoutPackets.push(UcPacketWithChannel(channelId, packet));
        (uint transactionId, address owner) = abi.decode(packet.appData, (uint, address));
        confirmations[transactionId][owner] = false;
    }

    // AVS Integration
    function initiateAVSSlashing(uint transactionId) internal {
        // Implement logic to initiate slashing on the AVS system
        address[] memory ownersToSlash = getOwnersForTransaction(transactionId);
        emit AVSSlashingInitiated(transactionId, ownersToSlash);
    }

    function getOwnersForTransaction(uint transactionId) internal view returns (address[] memory) {
        // Implement logic to get the owners who confirmed the transaction
        // and return them as an array
    }
}