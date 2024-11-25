// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import "./TokenA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Staking is Ownable, ReentrancyGuard {
    uint256 public fee = 1; // Percentage of fee
    uint256 public start; // Start staking date
    TokenA public token; // Token Staking and Reward
    address[] public userAddresses; // Users addresses
    uint256 constant PRECISION = 1e18;

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
        token = TokenA(tokenAddress);
        
        // Set initial reward rates
        rewardRates[30 days] = 5000;
        rewardRates[60 days] = 8000;
        rewardRates[90 days] = 10000;
        rewardRates[120 days] = 12000;
        rewardRates[180 days] = 15000;

        // Set extra reward rates (scaled by 100 to allow fractional values)
        extraRewardRates[30 days][100] = 500;  // 0.5
        extraRewardRates[30 days][50] = 250;   // 0.25
        extraRewardRates[30 days][25] = 125;   // 0.125

        extraRewardRates[60 days][100] = 1000; // 1
        extraRewardRates[60 days][50] = 500;   // 0.5
        extraRewardRates[60 days][25] = 250;   // 0.25

        extraRewardRates[90 days][100] = 2000; // 2
        extraRewardRates[90 days][50] = 1000;  // 1

        extraRewardRates[120 days][100] = 3000; // 3
        extraRewardRates[120 days][50] = 1500;  // 1.5

        extraRewardRates[180 days][100] = 4000; // 4
        extraRewardRates[180 days][50] = 2000;  // 2
    }

    event Staked(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);

    // Log events
    event LogTokenBalance(string key, uint256 value, string newKey, uint256 newValue);

    // Validate lock period
    modifier validLockPeriod(uint256 lockPeriod) {
        require(
            lockPeriod == 30 days ||
                lockPeriod == 60 days ||
                lockPeriod == 90 days ||
                lockPeriod == 120 days ||
                lockPeriod == 180 days,
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

    // Get extra reward rate for each apy
    function getExtraRewardRateForExtendAPY(uint256 leftPercent, uint256 lockPeriod) public view returns (uint256) {
        return extraRewardRates[lockPeriod][leftPercent];
    }

    // Get my staked history (returns all stakes as an array)
    function getMyStakedHistory() external view returns (StakedData[] memory) {
        return users[msg.sender].stakes;
    }

    // Helper function to check if the rate is scaled (greater than 100)
    function isScaledRate(uint256 rate) public pure returns (bool) {
        return rate > 100;
    }

    // Calculate reward token
    function calculateReward(uint256 amount, uint256 rate) public pure returns (uint256) {
        return amount * rate / 100000;
    }

    // Helper function to remove a stake from the user's stakes array
    function removeStake(User storage user, uint256 index) internal {
        require(index < user.stakes.length, "Invalid index");

        // Move the last element to the index to remove and pop the array
        user.stakes[index] = user.stakes[user.stakes.length - 1];
        user.stakes.pop();
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

    function mintTokens(uint256 amount) internal {
        require(amount > 0, "Mint amount must be greater than zero");
        token.mint(address(this), amount);
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
        emit Staked(msg.sender, amount);
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

            // Check if this user gets permission to unstake
            require(hasLockPeriodPassed(selected.start, selected.apy), "You can't unstake yet");

            // Calculate the reward and total fee
            uint256 rewardAmount = calculateReward(selected.stakedAmount, selected.rewardRate);
            totalFee = ((selected.stakedAmount + rewardAmount) * fee) / 100;
            withdrawableAmount = selected.stakedAmount + rewardAmount;

            // Check if the contract has enough balance
            require(token.balanceOf(address(this)) > withdrawableAmount, "The staking contract does not have enough tokens available for withdrawal. Please wait until more tokens are available.");

            // Remove the stake from the user's stakes array
            removeStake(user, i); // Use the removeStake function here
            unstaked = true;
            break;
        }

        // Ensure the stake was found and unstaked
        require(unstaked, "No stake found for this lock period");

        // Transfer the withdrawable amount to the user
        token.transfer(msg.sender, withdrawableAmount - totalFee);

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
    ) external nonReentrant validLockPeriod(lockPeriod) {
        User storage user = users[msg.sender];
        require(user.account != address(0), "User not found");
        uint256 withdrawableAmount = 0;
        uint256 rewardAmount;
        uint256 totalFee = 0;
        bool foundStake = false;

        for (uint256 i = 0; i < user.stakes.length; i++) {
            StakedData storage selected = user.stakes[i];

            // Process only the stake with the matching lock period
            if (selected.apy != lockPeriod) continue;
            
            foundStake = true;
            
            // Ensure the lock period has passed
            require(hasLockPeriodPassed(selected.start, selected.apy), "You can't withdraw yet");

            
            // Partial withdrawal logic (stake not removed)
            rewardAmount = calculateReward(selected.stakedAmount, selected.rewardRate);
            uint256 unstakeAmount = (selected.stakedAmount * (100 - leftStakePercent)) / 100;
            withdrawableAmount = unstakeAmount + rewardAmount;

            // Check if the contract has enough balance
            require(token.balanceOf(address(this)) > withdrawableAmount, "The staking contract does not have enough tokens available for withdrawal. Please wait until more tokens are available.");

            // Update stake data before any array modifications
            selected.rewardRate += getExtraRewardRateForExtendAPY(leftStakePercent, lockPeriod);
            selected.rewardAmount += rewardAmount;
            selected.withdrawAmount += unstakeAmount + rewardAmount;
            selected.stakedAmount -= unstakeAmount;
            selected.start = block.timestamp;
            ////////////////////////////////////////////////////

            totalFee = (withdrawableAmount * fee) / 100;
            break;
        }

        require(foundStake, "No stake found for this lock period");
        // Transfer the withdrawable amount and fee
        token.transfer(msg.sender, withdrawableAmount - totalFee);
        token.transfer(owner(), totalFee);
        
        emit Withdraw(msg.sender, withdrawableAmount);
    }
}
