// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract OperatorRegistry is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private operators;

    event OperatorAdded(address indexed operator);
    event OperatorRemoved(address indexed operator);

    modifier onlyOperator() {
        require(operators.contains(msg.sender), "Caller is not an operator");
        _;
    }

    function addOperator(address operator) external onlyOwner {
        require(operators.add(operator), "Operator already added");
        emit OperatorAdded(operator);
    }

    function removeOperator(address operator) external onlyOwner {
        require(operators.remove(operator), "Operator not found");
        emit OperatorRemoved(operator);
    }

    function isOperator(address operator) public view returns (bool) {
        return operators.contains(operator);
    }

    function getOperators() public view returns (address[] memory) {
        return operators.values();
    }
}

interface IPolymerHub {
    function sendPacket(
        bytes32 channelId,
        bytes calldata appData,
        uint64 timeoutTimestamp
    ) external;
}

contract CrossChainMultisig is Ownable {
    struct Transaction {
        address destination;
        uint256 value;
        bytes data;
        bool executed;
    }

    uint256 public transactionCount;
    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => mapping(address => bool)) public confirmations;
    OperatorRegistry public operatorRegistry;
    IPolymerHub public polymerHub;
    bytes32 public channelId;

    uint256 public required;

    event Confirmation(address indexed sender, uint256 indexed transactionId);
    event Revocation(address indexed sender, uint256 indexed transactionId);
    event Submission(uint256 indexed transactionId);
    event Execution(uint256 indexed transactionId);
    event ExecutionFailure(uint256 indexed transactionId);

    modifier onlyOperator() {
        require(operatorRegistry.isOperator(msg.sender), "Caller is not an operator");
        _;
    }

    modifier transactionExists(uint256 transactionId) {
        require(transactions[transactionId].destination != address(0), "Transaction does not exist");
        _;
    }

    modifier confirmed(uint256 transactionId, address operator) {
        require(confirmations[transactionId][operator], "Transaction not confirmed");
        _;
    }

    modifier notConfirmed(uint256 transactionId, address operator) {
        require(!confirmations[transactionId][operator], "Transaction already confirmed");
        _;
    }

    modifier notExecuted(uint256 transactionId) {
        require(!transactions[transactionId].executed, "Transaction already executed");
        _;
    }

    constructor(
        address _operatorRegistry,
        address _polymerHub,
        bytes32 _channelId,
        uint256 _required
    ) {
        operatorRegistry = OperatorRegistry(_operatorRegistry);
        polymerHub = IPolymerHub(_polymerHub);
        channelId = _channelId;
        required = _required;
    }

    function submitTransaction(address destination, uint256 value, bytes memory data) public onlyOperator returns (uint256) {
        uint256 transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false
        });
        transactionCount += 1;
        emit Submission(transactionId);
        confirmTransaction(transactionId);
        return transactionId;
    }

    function confirmTransaction(uint256 transactionId) public onlyOperator transactionExists(transactionId) notConfirmed(transactionId, msg.sender) {
        confirmations[transactionId][msg.sender] = true;
        emit Confirmation(msg.sender, transactionId);
        executeTransaction(transactionId);
    }

    function revokeConfirmation(uint256 transactionId) public onlyOperator transactionExists(transactionId) confirmed(transactionId, msg.sender) notExecuted(transactionId) {
        confirmations[transactionId][msg.sender] = false;
        emit Revocation(msg.sender, transactionId);
    }

    function executeTransaction(uint256 transactionId) public onlyOperator transactionExists(transactionId) notExecuted(transactionId) {
        if (isConfirmed(transactionId)) {
            Transaction storage txn = transactions[transactionId];
            txn.executed = true;
            (bool success, ) = txn.destination.call{value: txn.value}(txn.data);
            if (success) {
                emit Execution(transactionId);
            } else {
                txn.executed = false;
                emit ExecutionFailure(transactionId);
            }
        }
    }

    function isConfirmed(uint256 transactionId) public view returns (bool) {
        uint256 count = 0;
        address[] memory operators = operatorRegistry.getOperators();
        for (uint256 i = 0; i < operators.length; i++) {
            if (confirmations[transactionId][operators[i]]) {
                count += 1;
            }
            if (count == required) {
                return true;
            }
        }
        return false;
    }

    function crossChainSubmitTransaction(
        address destination,
        uint256 value,
        bytes memory data,
        uint64 timeoutTimestamp
    ) public onlyOperator returns (uint256) {
        uint256 transactionId = submitTransaction(destination, value, data);
        bytes memory appData = abi.encode(transactionId, destination, value, data);
        polymerHub.sendPacket(channelId, appData, timeoutTimestamp);
        return transactionId;
    }
}
