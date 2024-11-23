// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Staking is Ownable, ReentrancyGuard {
    uint256 public fee = 1; // Percentage of fee
    uint256 public start; // Start staking date
    IERC20 public token; // Token Staking and Reward
    address[] public userAddresses; // Users addresses

    mapping(uint256 => uint256) public rewardRates;
    mapping(uint256 => mapping(uint256 => uint256)) public extraRewardRates;

    struct StakedData {
        uint256 stakedAmount;
        uint256 withdrawAmount;
        uint256 rewardAmount;
        uint256 start;
        uint256 apy;
        uint256 rewardRate;
    }

    struct User {
        address account;
        StakedData[] stakes;
    }

    mapping(address => User) public users;

    constructor(uint256 _start, address tokenAddress) Ownable(msg.sender) {
        start = _start;
        token = IERC20(tokenAddress);
        
        // Set initial reward rates
        rewardRates[30 seconds] = 5;
        rewardRates[60 seconds] = 8;
        rewardRates[90 seconds] = 10;
        rewardRates[120 seconds] = 12;
        rewardRates[180 seconds] = 15;

        // Set extra reward rates (scaled by 100 to allow fractional values)
        extraRewardRates[30 seconds][100] = 50;  // 0.5
        extraRewardRates[30 seconds][50] = 25;   // 0.25
        extraRewardRates[30 seconds][25] = 12;   // 0.125

        extraRewardRates[60 seconds][100] = 100; // 1
        extraRewardRates[60 seconds][50] = 50;   // 0.5
        extraRewardRates[60 seconds][25] = 25;   // 0.25

        extraRewardRates[90 seconds][100] = 200; // 2
        extraRewardRates[90 seconds][50] = 100;  // 1

        extraRewardRates[120 seconds][100] = 300; // 3
        extraRewardRates[120 seconds][50] = 150;  // 1.5

        extraRewardRates[180 seconds][100] = 400; // 4
        extraRewardRates[180 seconds][50] = 200;  // 2
    }

    event Staked(address indexed user, uint256 amount, uint256 lockPeriod);
    event Withdraw(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);

    // Validate lock period
    modifier validLockPeriod(uint256 lockPeriod) {
        require(
            lockPeriod == 30 seconds ||
                lockPeriod == 60 seconds ||
                lockPeriod == 90 seconds ||
                lockPeriod == 120 seconds ||
                lockPeriod == 180 seconds,
            "Invalid lock period"
        );
        _;
    }

    // Function to check if the lock period has passed
    function hasLockPeriodPassed(uint256 _start, uint256 lockPeriod) public view returns (bool) {
        return block.timestamp >= _start + lockPeriod;
    }

    // Set reward rate with onlyOwner
    function setRewardRate(
        uint256 lockPeriod,
        uint256 rate
    ) external onlyOwner validLockPeriod(lockPeriod) {
        rewardRates[lockPeriod] = rate;
    }

    // Set fee function with onlyOwner
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    // Deposit the reward tokens to this staking contract with onlyOwner
    function depositRewards(uint256 amount) external onlyOwner {
        token.transferFrom(msg.sender, address(this), amount);
    }

    // Get reward rate for each apy
    function getInitialRewardRateForAPY(
        uint256 lockPeriod
    ) public view returns (uint256) {
       return rewardRates[lockPeriod];
    }

    // Get extra reward rate for each apy
    function getExtraRewardRateForExtendAPY(uint256 leftPercent, uint256 lockPeriod) public view returns (uint256) {
        return extraRewardRates[lockPeriod][leftPercent];
    }

    // Get all users
    function getAllUsers() public view returns (User[] memory) {
        User[] memory allUsers = new User[](userAddresses.length);
        for (uint256 i = 0; i < userAddresses.length; i++) {
            allUsers[i] = users[userAddresses[i]];
        }
        return allUsers;
    }

    // Get my staked history (returns all stakes as an array)
    function getMyStakedHistory() external view returns (StakedData[] memory) {
        return users[msg.sender].stakes;
    }

    // Get my current withdrawable reward amount
    function getMyCurrentRewardingAmount() public view returns (uint256 withdrawableAmount) {
        User storage user = users[msg.sender];

        // Loop through the user's stakes and sum up the rewards
        for (uint256 i = 0; i < user.stakes.length; i++) {
            StakedData storage selected = user.stakes[i];
            uint256 rewardAmount = calculateReward(
                selected.stakedAmount,
                selected.rewardRate
            );
            
            // Add the calculated reward to the total withdrawable amount
            withdrawableAmount += rewardAmount;
        }
    }

    // Calculate reward token
    function calculateReward(
        uint256 amount,
        uint256 rate
    ) public pure returns (uint256) {
        return (amount * rate) / 100;
    }

    // Helper function to remove a stake from the user's stakes array
    function removeStake(User storage user, uint256 index) internal {
        require(index < user.stakes.length, "Invalid index");

        // Move the last element to the index to remove and pop the array
        user.stakes[index] = user.stakes[user.stakes.length - 1];
        user.stakes.pop();
    }

    // Staking function
    function stake(uint256 amount, uint256 lockPeriod) external nonReentrant validLockPeriod(lockPeriod) {
        require(amount > 0, "Amount must be greater than 0");

        // Check if the user has already staked for the same lock period
        require(!hasStakedForLockPeriod(msg.sender, lockPeriod), "Already staked for this lock period");

        // Create a new stake
        StakedData memory newData = StakedData({
            stakedAmount: amount,
            withdrawAmount: 0,
            start: block.timestamp,
            apy: lockPeriod,
            rewardRate: rewardRates[lockPeriod],
            rewardAmount: 0
        });

        // Initialize user account if not already set
        if (users[msg.sender].account == address(0)) {
            users[msg.sender].account = msg.sender;
            userAddresses.push(msg.sender);
        }

        // Add the new stake to the user's staking data
        users[msg.sender].stakes.push(newData);

        // Transfer the staking tokens from the user to the contract
        token.transferFrom(msg.sender, address(this), amount);

        // Emit the Staked event
        emit Staked(msg.sender, amount, lockPeriod);
    }

    // Helper function to check if the user has already staked for the lock period
    function hasStakedForLockPeriod(address user, uint256 lockPeriod) internal view returns (bool) {
        User storage userData = users[user];
        for (uint256 i = 0; i < userData.stakes.length; i++) {
            if (userData.stakes[i].apy == lockPeriod) {
                return true;
            }
        }
        return false;
    }


    // Unstaking function
    function unstake(uint256 lockPeriod) external nonReentrant validLockPeriod(lockPeriod) returns (uint256) {
        User storage user = users[msg.sender];
        uint256 withdrawableAmount;
        uint256 totalFee;

        bool unstaked = false;

        // Iterate through the user's stakes to find the matching lockPeriod
        for (uint256 i = 0; i < user.stakes.length; i++) {
            StakedData storage selected = user.stakes[i];
            
            // Only process the stake with the matching lock period
            if (selected.apy != lockPeriod) continue;

            // Check this user gets the permission to unstake
            require(!hasLockPeriodPassed(selected.start, selected.apy), "You can't unstake yet");

            // Calculate the reward and total fee
            uint256 rewardAmount = calculateReward(selected.stakedAmount, selected.rewardRate);
            totalFee = ((selected.stakedAmount + rewardAmount) * fee) / 100;
            withdrawableAmount = selected.stakedAmount + rewardAmount - totalFee;

            // Swap with the last element and pop the stake
            if (i < user.stakes.length - 1) {
                user.stakes[i] = user.stakes[user.stakes.length - 1]; // Replace with last element
            }
            user.stakes.pop(); // Remove the last element

            unstaked = true;
            break;
        }

        // Ensure the stake was found and unstaked
        require(unstaked, "No stake found for this lock period");

        // Transfer the withdrawable amount to the user
        token.transfer(msg.sender, withdrawableAmount);

        // Transfer the fee to the owner
        token.transfer(owner(), totalFee);

        // Emit the Unstaked event
        emit Unstaked(msg.sender, withdrawableAmount);

        return withdrawableAmount;
    }

    // Withdraw reward function
    function withdraw(
        uint256 lockPeriod,
        uint256 leftStakePercent
    ) external nonReentrant validLockPeriod(lockPeriod) returns (bool) {
        User storage user = users[msg.sender];
        require(user.account != address(0), "User not found");

        uint256 withdrawableAmount = 0;
        uint256 rewardAmount;
        uint256 totalFee = 0;
        bool foundStake = false;
        bool stakeRemoved = false;

        for (uint256 i = 0; i < user.stakes.length; i++) {
            StakedData storage selected = user.stakes[i];

            // Process only the stake with the matching lock period
            if (selected.apy != lockPeriod) continue;

            foundStake = true;

            // Ensure the lock period has passed
            require(hasLockPeriodPassed(selected.start, selected.apy), "You can't withdraw yet");

            // Check if the stake should be removed
            if (selected.rewardRate > rewardRates[lockPeriod]) {
                // Calculate full withdrawable amount and fee before removal
                rewardAmount = calculateReward(selected.stakedAmount, selected.rewardRate);
                withdrawableAmount = selected.stakedAmount + rewardAmount;
                totalFee = (withdrawableAmount * fee) / 100;

                // Remove the stake from the array
                removeStake(user, i);
                stakeRemoved = true;
                break;
            }

            // Partial withdrawal logic (stake not removed)
            rewardAmount = calculateReward(selected.stakedAmount, selected.rewardRate);
            uint256 unstakeAmount = (selected.stakedAmount * (100 - leftStakePercent)) / 100;

            // Update stake data before any array modifications
            uint256 _extraRewardRate = getExtraRewardRateForExtendAPY(leftStakePercent, lockPeriod);
            selected.rewardRate += _extraRewardRate / 100;
            selected.rewardAmount += rewardAmount;
            selected.withdrawAmount += unstakeAmount + rewardAmount;
            selected.stakedAmount -= unstakeAmount;

            withdrawableAmount = unstakeAmount + rewardAmount;
            totalFee = (withdrawableAmount * fee) / 100;

            break;
        }

        require(foundStake, "No stake found for this lock period");

        // Transfer the withdrawable amount and fee
        token.transfer(msg.sender, withdrawableAmount - totalFee);
        token.transfer(owner(), totalFee);

        emit Withdraw(msg.sender, withdrawableAmount);

        return stakeRemoved;
    }


}
