// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniversalRouter {
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