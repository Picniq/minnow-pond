// SPDX-License-Identifier: MIT
// Author: danq.eth (QFinance/Picniq)

pragma solidity ^0.8.0;

import "./utils/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/MerkleProof.sol";

/**
 * @dev This contract is intended to be deployed on a cheaper network.
 */

// solhint-disable not-rely-on-time, avoid-low-level-calls
contract MinnowPond is Ownable {
    using MerkleProof for bytes32[];
    using SafeMath for uint256;

    // Separate contract per token.
    // Should be address of token on destination network.
    IERC20 private _token;

    // Total deposits to loop through mapping
    uint256 private _totalDeposits;

    // Collect fees
    uint256 private _collectedFees;

    // Total periods - latest is always current
    uint256 private _totalPeriods;

    // In deposit switch to prevent reentrancy bugs. 1 = false, 2 = true
    uint256 private _inDepositSwitch = 1;

    // All deposits for reference
    mapping(uint256 => Deposit) private _deposits;
    // All periods for reference
    mapping(uint256 => Period) private _periods;
    // Maps user address to a deposit index
    mapping(address => uint256) private _userDeposits;

    // Save deposit data in struct.
    struct Deposit {
        uint32 timestamp;
        uint32 period;
        uint256 depositAmount;
        address depositor;
    }

    // Period data information
    struct Period {
        uint32 timeStart;
        uint32 timeEnd;
        uint32 firstDepositIndex;
        uint32 lastDepositIndex;
        bytes32 merkle;
        uint256 totalDeposits;
    }

    struct MerkleItem {
        uint256 percentOwned;
        address depositor;
    }

    constructor(IERC20 token) {
        _token = token;

        // First period created on launch
        _periods[1] = Period({
            timeStart: uint32(block.timestamp),
            timeEnd: uint32(0),
            firstDepositIndex: uint32(1),
            lastDepositIndex: uint32(1),
            merkle: bytes32(""),
            totalDeposits: uint192(0)
        });

        _totalPeriods = 1;
    }

    modifier _inDeposit() {
        require(_inDepositSwitch == 1, "Deposit in progress");
        _inDepositSwitch = 2;
        _;
        _inDepositSwitch = 1;
    }

    /**
     * @dev Pull up main details for currently active period.
     */
    function getCurrentPeriod()
        external
        view
        returns (
            uint32,
            uint32,
            uint256
        )
    {
        Period storage period = _periods[_totalPeriods];

        // period.timeEnd will equal 0 if currently active.
        // This function should always return 0 for period.timeEnd.
        return (period.timeStart, period.timeEnd, period.totalDeposits);
    }

    /**
     * @dev Pull up main details of past period.
     */
    function getPastPeriod(uint256 index)
        external
        view
        returns (
            uint32,
            uint32,
            uint256
        )
    {
        Period storage period = _periods[index];

        return (period.timeStart, period.timeEnd, period.totalDeposits);
    }

    /**
     * @dev List number of total periods.
     */
    function getTotalPeriods() external view returns (uint256) {
        return _totalPeriods;
    }

    /**
     * @dev Pull up last deposit for a user.
     */
    function getLastDeposit(address user) external view returns (uint256) {
        return _deposits[_userDeposits[user]].depositAmount;
    }

    /**
     * @dev Function to deposit funds to the pool for a period. Once the
     * deposit amount surpasses a threshold, the period closes and new one begins.
     */
    function makeDeposit() external payable _inDeposit returns (bool) {
        // We limit the amount of ETH in each period to prevent front-running bots
        require(
            msg.value > 0.005 ether && msg.value <= 1 ether,
            "Deposit must be 0.005 to 1 ETH"
        );

        // Get period from storage, save current deposit amount and calculate new amount
        Period storage period = _periods[_totalPeriods];
        uint256 currentAmount = period.totalDeposits;
        uint256 newTotal = currentAmount.add(msg.value);
        uint256 lastUserDeposit = _userDeposits[msg.sender];

        // If user already deposited this period, add to total
        if (_deposits[lastUserDeposit].period == _totalPeriods) {
            // Get current user deposit and update it
            Deposit storage userDeposit = _deposits[lastUserDeposit];
            userDeposit.depositAmount = userDeposit.depositAmount.add(
                msg.value
            );
            userDeposit.timestamp = uint32(block.timestamp);
        } else {
            // Add 1 to total deposits
            uint256 _newTotalDeposits = _totalDeposits + 1;
            // Add deposit index to user mapping
            _userDeposits[msg.sender] = _newTotalDeposits;
            // Set state variable to new total deposit number
            _totalDeposits = _newTotalDeposits;
            // Save new total deposit amount to period
            period.totalDeposits = newTotal;
            // Create new deposit item
            _deposits[_totalDeposits] = Deposit({
                timestamp: uint32(block.timestamp),
                period: uint32(_totalPeriods),
                depositAmount: msg.value,
                depositor: msg.sender
            });
        }

        // If total is greater than 1 ETH, close and create new period
        if (newTotal > 1e18) {
            period.timeEnd = uint32(block.timestamp);
            period.totalDeposits = currentAmount.add(msg.value);
            period.lastDepositIndex = uint32(_totalDeposits);
            _totalPeriods += 1;
            _periods[_totalPeriods] = Period({
                timeStart: uint32(block.timestamp),
                timeEnd: uint32(0),
                firstDepositIndex: uint32(_totalDeposits + 1),
                lastDepositIndex: uint32(_totalDeposits + 1),
                totalDeposits: 0,
                merkle: bytes32("")
            });
        }

        return true;
    }

    /**
     * @dev Allows a user to withdraw their funds in case they change
     * their mind about participating in a swap round.
     */
    function withdraw() external returns (bool) {
        Period storage period = _periods[_totalPeriods];
        Deposit storage userDeposit = _deposits[_userDeposits[msg.sender]];

        require(period.timeEnd == 0, "Not active");
        require(userDeposit.period == _totalPeriods, "No deposit for period");

        uint256 amountToSend = userDeposit.depositAmount;
        period.totalDeposits = period.totalDeposits.sub(
            userDeposit.depositAmount
        );
        userDeposit.depositAmount = 0;
        userDeposit.timestamp = uint32(block.timestamp);

        (bool success, ) = msg.sender.call{ value: amountToSend }("");

        return success;
    }

    /**
     * @dev Was used for easier testing. Will be removed in prod and moved to separate contract.
     */
    function setMerkleRoot(bytes32 root, uint256 periodNumber) external {
        Period storage period = _periods[periodNumber];

        if (period.timeEnd == 0) {
            period.timeEnd = uint32(block.timestamp);
        }

        period.merkle = root;
    }

    /**
     * @dev Was used for easier testing. Will be removed in prod and moved to separate contract.
     */
    function claim(
        bytes32[] memory proof,
        uint256 periodNumber,
        uint256 percent
    ) external view returns (bool) {
        bytes32 merkleRoot = _periods[periodNumber].merkle;
        bytes32 leaf = keccak256(abi.encodePacked(percent, msg.sender));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }

    /**
     * @dev Loops through all depositors for a particular period and creates the
     * base data used to generate the merkle root.
     */
    function getDepositors(uint256 periodNumber)
        external
        view
        returns (MerkleItem[] memory)
    {
        // Get period data from storage
        Period storage period = _periods[periodNumber];
        // Create new item list. Length is last - first + 1.
        MerkleItem[] memory items = new MerkleItem[](
            period.lastDepositIndex - period.firstDepositIndex + 1
        );
        // Create list index to save items in list
        uint256 listIndex;
        // Initial index should be first deposit index and loop runs until last deposit index.
        for (
            uint256 i = period.firstDepositIndex;
            i <= period.lastDepositIndex;
            i++
        ) {
            // Save item with percent owned
            MerkleItem memory entry = MerkleItem({
                depositor: _deposits[i].depositor,
                percentOwned: _deposits[i].depositAmount.mul(1e18).div(
                    period.totalDeposits
                )
            });
            items[listIndex] = entry;
            listIndex += 1;
        }

        return items;
    }
}
