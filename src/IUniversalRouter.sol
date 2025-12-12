// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniversalRouter {
    // Commands that can be used in the 'execute' function
    bytes1 V3_SWAP_EXACT_IN;
    bytes1 V3_SWAP_EXACT_OUT;
    bytes1 V2_SWAP_EXACT_IN;
    bytes1 V2_SWAP_EXACT_OUT;
    bytes1 WRAP_ETH;
    bytes1 UNWRAP_WETH;

    /// @notice Executa comandos codificados para fazer swaps
    /// @param commands Uma string de bytes onde cada byte é um comando (ex: V3_SWAP_EXACT_IN)
    /// @param inputs Um array de bytes onde cada item são os parâmetros decodificados do comando
    /// @param deadline O timestamp limite para a transação ocorrer
    function execute(
        bytes calldata commands, 
        bytes[] calldata inputs, 
        uint256 deadline
    ) external payable;
}