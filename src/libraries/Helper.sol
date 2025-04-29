// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

library Helper {
    error IdenticalAddressesNotAllowed();
    error ZeroAddressNotAllowed();
    error InsufficientAmount();
    error InsufficientLiquidity();
    error InsufficientInput();
    error InsufficientOutput();
    error TransferFromFailed();
    error ETHTransferFailed();

    //returning sorted token addresses
    function sortTokens(address tokenA, address tokenB) internal pure returns (address _tokenA, address _tokenB) {
        require(tokenA != tokenB, IdenticalAddressesNotAllowed());

        (_tokenA, _tokenB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        require(_tokenA != address(0), ZeroAddressNotAllowed());
    }

    // given an amount of a token and pair reserves,
    // returns an equivalent of the amount of the other token
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, InsufficientAmount());
        require(reserveA > 0 && reserveB > 0, InsufficientLiquidity());

        amountB = (amountA * reserveB) / reserveA;
    }

    // Given an input amount of an asset and pair reserves,
    // returns the output amount of the other token after taking the fee
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, InsufficientInput());
        require(reserveIn > 0 && reserveOut > 0, InsufficientLiquidity());
        uint256 amountInWithFee = amountIn * 998;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output of an asset and pair reserves
    // returns the required input amount of the other
    // token after taking the fee
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, InsufficientOutput());
        require(reserveIn > 0 && reserveOut > 0, InsufficientLiquidity());

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 998; //2%

        amountIn = (numerator / denominator) + 1;
    }

    // Safe version of transfer
    function safeTransfer(address token, address to, uint256 value) internal {
        // 0xa9059cbb = bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), TransferFromFailed());
    }
    // creating CREATE2 address for a pair

    function pairFor(address factory, address tokenA, address tokenB, bytes32 initCodeHash)
        internal
        pure
        returns (address pair)
    {
        (address _tokenA, address _tokenB) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(hex"ff", factory, keccak256(abi.encodePacked(_tokenA, _tokenB)), initCodeHash)
                    )
                )
            )
        );
    }

    // safe version of transferFrom for ERC20
    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b862dd, from, to, amount));

        require(success && (data.length == 0 || abi.decode(data, (bool))), TransferFromFailed());
    }
    // safe version of ETH transfer to an account

    function safeTransferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, ETHTransferFailed());
    }
}
