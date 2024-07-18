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