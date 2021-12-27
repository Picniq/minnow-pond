// SPDX-License-Identifier: MIT
// Author: danq.eth (QFinance/Picniq)

pragma solidity ^0.8.0;

import "./utils/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/IUniswapRouter.sol";
import "./libraries/MerkleProof.sol";

/**
 * @dev This contract is intended to be deployed on a cheaper network.
 */

// solhint-disable not-rely-on-time, no-empty-blocks
contract SwapAndClaim {
    using SafeMath for uint256;
    using MerkleProof for bytes32[];

    IUniswapRouter private _uniswapRouter =
        IUniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // Mapping to track claims. Track by ID, then user.
    mapping(uint256 => mapping(address => bool)) private _claimed;

    // Mapping to track swaps per token and period.
    mapping(IERC20 => mapping(uint256 => SwapData)) private _swaps;

    // Total swaps used to manage swap IDs
    uint64 private _totalSwaps;

    // In deposit switch to prevent reentrancy bugs. 1 = false, 2 = true
    uint256 private _inSwapSwitch = 1;

    struct SwapData {
        bytes32 merkleRoot;
        uint64 id;
        uint256 amountReceived;
    }

    struct ClaimData {
        uint8 claimed;
        uint32 period;
    }

    constructor() {}

    fallback() external payable {}

    receive() external payable {}

    modifier _inSwap() {
        require(_inSwapSwitch == 1, "Deposit in progress");
        _inSwapSwitch = 2;
        _;
        _inSwapSwitch = 1;
    }

    /**
     * @dev Checks if an address has already claimed their portion. Will equal false if not registered.
     */
    function checkClaimed(
        IERC20 token,
        address claimant,
        uint256 period
    ) public view returns (bool) {
        uint256 id = _swaps[token][period].id;
        return _claimed[id][claimant];
    }

    /**
     * @dev Checks proof and if valid, claims token for the claimant.
     */
    function claimTokens(
        IERC20 token,
        uint256 period,
        bytes32[] calldata proof,
        uint256 percent
    ) external returns (bool) {
        SwapData storage swap = _swaps[token][period];
        require(swap.id != 0, "Swap not found");
        require(!checkClaimed(token, msg.sender, period), "Already claimed");

        bytes32 leaf = keccak256(abi.encodePacked(percent, msg.sender));
        require(
            MerkleProof.verify(proof, swap.merkleRoot, leaf),
            "Proof failed"
        );

        _claimed[swap.id][msg.sender] = true;
        uint256 amountToSend = swap.amountReceived.mul(percent).div(1e18);
        require(
            amountToSend <= token.balanceOf(address(this)),
            "Amount greater than balance"
        );
        token.transfer(msg.sender, amountToSend);

        return true;
    }

    /**
     * @dev Privileged function to create swap and add it to the index, along with merkle root for period.
     */
    function makeSwap(
        IERC20 token,
        uint256 ethAmount,
        uint256 expected,
        uint256 period,
        bool isFeeOnTransfer,
        bytes32 merkleRoot
    ) external payable _inSwap {
        require(_swaps[token][period].id == 0, "Swap made for period");
        require(ethAmount <= address(this).balance, "Swap exceeds balance");

        uint256 prevBalance = token.balanceOf(address(this));

        _totalSwaps += 1;

        address[] memory path = new address[](2);
        path[0] = _uniswapRouter.WETH();
        path[1] = address(token);

        if (isFeeOnTransfer) {
            _uniswapRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{
                value: ethAmount
            }(expected, path, address(this), block.timestamp + 10);
        } else {
            _uniswapRouter.swapExactETHForTokens{ value: ethAmount }(
                expected,
                path,
                address(this),
                block.timestamp + 10
            );
        }

        uint256 newBalance = token.balanceOf(address(this));

        _swaps[token][period] = SwapData({
            merkleRoot: merkleRoot,
            id: _totalSwaps,
            amountReceived: newBalance.sub(prevBalance)
        });
    }
}
