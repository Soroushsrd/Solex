// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ITokenPair} from "./interfaces/ITokenPair.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {UQ112x112} from "./libraries/UQ112x112.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";

// this type is minted and sent to liquidity providers to represent
// their share of  the liquidity pool
contract TokenPair is ITokenPair, ERC20, ReentrancyGuard {
    using UQ112x112 for uint224;

    address public factory;
    address public tokenA;
    address public tokenB;
    uint256 public kLast;

    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    uint256 private reserveA;
    uint256 private reserveB;
    uint256 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    error NotOwner();
    error FailedTransfer();
    error InsufficientMintedLiquidity();
    error InsufficientBurningLiquidity();
    error InsufficientReserves();
    error InsufficientLiquidity();
    error InvalidOutputAmount();
    error InvalidOutputAddress();
    error InsufficientInputAmount();
    error OverFlow();

    constructor() ERC20("DEX Token Pair", "DEX-TP") {
        factory = msg.sender;
    }

    function initialize(address _tokenA, address _tokenB) external {
        require(msg.sender == factory, NotOwner());
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function getReserves() public view returns (uint256 _reserveA, uint256 _reserveB) {
        _reserveA = reserveA;
        _reserveB = reserveB;
        // _blockTimestampLast = blockTimestampLast;
    }

    function _setReserves(uint256 balance0, uint256 balance1) private {
        reserveA = balance0;
        reserveB = balance1;
        blockTimestampLast = block.timestamp;
        emit Sync(reserveA, reserveB);
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, amount));

        require(success && (data.length == 0 || abi.decode(data, (bool))), FailedTransfer());
    }

    function _update(uint256 balanceA, uint256 balanceB, uint112 _reserveA, uint112 _reserveB) private {
        require(balanceA <= type(uint112).max && balanceB <= type(uint112).max, OverFlow());
        uint256 blockTimestamp = block.timestamp % 2 ** 32;
        // overflow is desired
        // expecting less than 2^32 seconds (~136 years) between 2 updates
        uint256 timeElapsed = blockTimestamp - blockTimestampLast;
        if (timeElapsed > 0 && _reserveA != 0 && _reserveB != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(UQ112x112.encode(_reserveB).uqdiv(_reserveA)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(_reserveA).uqdiv(_reserveB)) * timeElapsed;
        }

        reserveA = uint112(balanceA);
        reserveB = uint112(balanceB);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserveA, reserveB);
    }

    //1. Calculate the amounts of LP tokens to be minted.
    // 2. Mint the LP tokens and transfer them to the liquidity provider.
    // 3. Update the reserve amounts to match the current balance.
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        // calculate the amount of LP tokens to be minted
        (uint256 _reserveA, uint256 _reserveB) = getReserves();

        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));

        uint256 amountA = balanceA - _reserveA;
        uint256 amountB = balanceB - _reserveB;

        bool hasReward = _mintReward(_reserveA, _reserveB);

        uint256 _totalSupply = totalSupply();

        // in case the LP token total supply is zero, we must use the transfered amounts
        // to the token pair, as the initial reserves and calculate the number of shares
        if (_totalSupply == 0) {
            // if less than MINIMUM_LIQUIDITY, it will revert
            liquidity = Math.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            // dead address
            // since we dont want the LP tokens to be drained from token pair address
            // we need to lock some of it (MINIMUM_LIQUIDITY) in a dead address (not zero)
            _mint(address(0xdEaD), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min((amountA * _totalSupply) / _reserveA, (amountB * _totalSupply) / _reserveB);
        }

        require(liquidity > 0, InsufficientMintedLiquidity());

        // mint the Lp tokens and transfer them to the liquidity provider
        _mint(to, liquidity);

        // update the reserves
        _setReserves(balanceA, balanceB);

        // if a rewardTo is not set, no new LP tokens will be minted here
        // and the liquidity providers will share all the gains
        if (hasReward) kLast = reserveA * reserveB;

        emit Mint(msg.sender, amountA, amountB);
    }

    // this returns true if the code needs to mint rewards
    function _mintReward(uint256 _reserveA, uint256 _reserveB) private returns (bool hasReward) {
        // this is read from a pair factory because the reward receiver address
        // is the same for all the token pairs created by the factory
        address rewardTo = IPairFactory(factory).rewardTo();
        hasReward = rewardTo != address(0);
        uint256 _klast = kLast; // gas savings

        if (hasReward) {
            if (_klast != 0) {
                uint256 rootK = Math.sqrt(_reserveA * _reserveB);
                uint256 rootKLast = Math.sqrt(_klast);

                if (rootK > rootKLast) {
                    uint256 liquidity = (totalSupply() * (rootK - rootKLast)) / (rootKLast + rootK * 9);

                    if (liquidity > 0) {
                        _mint(rewardTo, liquidity);
                    }
                }
            }
        } else if (_klast != 0) {
            kLast = 0;
        }
    }

    // 1. For each of the tokens in the pair, it calculates how many tokens
    //  need to be transferred back to the user.
    // 2. It burns the LP tokens received from the user,
    //  then transfers the calculated amounts of tokens back to the user.
    // 3. It sets the reserves with the remaining token balances
    function burn(address to) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        // calculate the token amounts sent back to the user
        (uint256 _reserveA, uint256 _reserveB) = getReserves();

        address _tokenA = tokenA;
        address _tokenB = tokenB;

        uint256 balanceA = IERC20(_tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(_tokenB).balanceOf(address(this));

        uint256 liquidity = balanceOf(address(this));

        bool hasReward = _mintReward(_reserveA, _reserveB);

        uint256 _totalSupply = totalSupply();

        amountA = (liquidity * balanceA) / _totalSupply;
        amountB = (liquidity * balanceB) / _totalSupply;

        require(amountA > 0 && amountB > 0, InsufficientBurningLiquidity());

        // burn the LP tokens and send paired tokens
        _burn(address(this), liquidity);
        _safeTransfer(_tokenA, to, amountA);
        _safeTransfer(_tokenA, to, amountB);

        //set the reserves with token _balances
        balanceA = IERC20(_tokenA).balanceOf(address(this));
        balanceB = IERC20(_tokenB).balanceOf(address(this));

        _setReserves(balanceA, balanceB);

        if (hasReward) kLast = reserveA * reserveB;

        emit Burn(msg.sender, amountA, amountB, to);
    }

    // skim is used to truncate balance or reserves to make sure that
    // reserves and balance of the smart contract actually match each other
    // Forces balances to match reserves
    function skim(address to) external nonReentrant {
        address _tokenA = tokenA;
        address _tokenB = tokenB;

        _safeTransfer(_tokenA, to, IERC20(_tokenA).balanceOf(address(this)) - reserveA);
        _safeTransfer(_tokenB, to, IERC20(_tokenB).balanceOf(address(this)) - reserveB);
    }
    // sync is used to extend the reserves or balance of the smart contract
    // in order to make sure they match each other in case a transfer goes wrong
    // Forces reserves to match balances

    function sync() external nonReentrant {
        _setReserves(IERC20(tokenA).balanceOf(address(this)), IERC20(tokenB).balanceOf(address(this)));
    }

    function swap(uint256 amountAOut, uint256 amountBOut, address to) external {
        // pre transfer verifications
        // when called from AMM router, one of these values will be zero
        // the token with the zero amount, has had its balance transfered
        // into the smart contract, so we need to transfer the eq amount for the
        // other token to the address specified (to)
        require(amountAOut > 0 || amountBOut > 0, InvalidOutputAmount());

        (uint256 _reserveA, uint256 _reserveB) = getReserves();
        require(_reserveA > amountAOut && _reserveB > amountBOut, InsufficientReserves());

        address _tokenA = tokenA;
        address _tokenB = tokenB;

        require(to != _tokenA && to != _tokenB, InvalidOutputAddress());

        // doing the actual transfer
        if (amountAOut > 0) _safeTransfer(_tokenA, to, amountAOut);
        if (amountBOut > 0) _safeTransfer(_tokenB, to, amountBOut);
        // verifying that the input amount is sufficient
        uint256 balanceA = IERC20(_tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(_tokenB).balanceOf(address(this));
        uint256 amountAIn = balanceA > _reserveA - amountAOut ? balanceA - (_reserveA - amountAOut) : 0;
        uint256 amountBIn = balanceB > _reserveB - amountBOut ? balanceB - (_reserveB - amountBOut) : 0;

        require(amountBIn > 0 || amountAIn > 0, InsufficientInputAmount());
        // The adjusted amount should be balance − 0.2% * amountIn,
        // with 0.2% of the transaction fee to be kept in the reserves
        _checkLiquidity(balanceA, balanceB, amountAIn, amountBIn);

        _setReserves(balanceA, balanceB);
        emit Swap(msg.sender, amountAIn, amountBIn, amountAOut, amountBOut, to);
    }

    function _calculateInputAmounts(
        uint256 balanceA,
        uint256 balanceB,
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 amountAOut,
        uint256 amountBOut
    ) private pure returns (uint256 amountAIn, uint256 amountBIn) {
        amountAIn = balanceA > _reserveA - amountAOut ? balanceA - (_reserveA - amountAOut) : 0;
        amountBIn = balanceB > _reserveB - amountBOut ? balanceB - (_reserveB - amountBOut) : 0;
    }

    function _checkLiquidity(uint256 balanceA, uint256 balanceB, uint256 amountAIn, uint256 amountBIn) private view {
        uint256 balanceAAdjusted = balanceA * 1000 - amountAIn * 2;
        uint256 balanceBAdjusted = balanceB * 1000 - amountBIn * 2;
        require(balanceAAdjusted * balanceBAdjusted >= reserveA * reserveB * 1000 ** 2, InsufficientLiquidity());
    }
}

/// Reward distribution for liquidity providers and DEX owners
// Example: Dex sets up 0.2% fee on every transaction => 0.2% of each tx goes to
// Liquidity providers and Dex owners
// Since by every TX, more liquidity gets injected into reserves, their product will increase
// But the amount of LP shares remain the same thus their value increases.
