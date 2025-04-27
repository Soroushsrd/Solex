// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

// each token pair counts as a liquidity pool for a token pair
interface ITokenPair {
    event Mint(address indexed sender, uint256 amountA, uint256 amountB);
    event Burn(address indexed sender, uint256 amountA, uint256 amountB, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amountAIn,
        uint256 amountBIn,
        uint256 amountAOut,
        uint256 amountBOut,
        address indexed to
    );
    event Sync(uint256 reservedA, uint256 reservedB);

    /// returns the address of the pair factory that manufactored the token pair
    function factory() external view returns (address);

    /// returns the address of the first token of the pair
    function tokenA() external view returns (address);

    /// returns the address of the second token of the pair
    function tokenB() external view returns (address);

    /// returns the product of the two token reserves
    /// since we already are implementing ERC20 for our pair(totalsupply),
    /// this variable is only used when DEX needs to send
    /// deployers extra LP tokens as rewards
    function kLast() external view returns (uint256);

    function getReserves() external view returns (uint256 reserveA, uint256 reserveB);
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amountA, uint256 amountB);
    function swap(uint256 amountAOut, uint256 amountBOut, address to) external;
    function skim(address to) external;
    function sync() external;
    function initialize(address, address) external;

    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
}
