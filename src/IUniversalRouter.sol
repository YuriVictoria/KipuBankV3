// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPermit2} from "https://github.com/Uniswap/permit2/blob/main/src/interfaces/IPermit2.sol";

interface IUniversalRouter {
    // Overloaded execute function to support different call types including Permit2
    function execute(
        bytes calldata commands, 
        bytes[] calldata inputs, 
        uint256 deadline
    ) external payable;

    function execute(
        bytes calldata commands, 
        bytes[] calldata inputs
    ) external payable;

    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        IPermit2.PermitSingle calldata permit,
        address payer
    ) external payable;

    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        IPermit2.PermitBatch calldata permit,
        address payer
    ) external payable;
}