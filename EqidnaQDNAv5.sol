
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import ".deps/npm/@openzeppelin/contracts/token/ERC20/ERC20.sol";
import ".deps/npm/@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import ".deps/npm/@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import ".deps/npm/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import ".deps/npm/@openzeppelin/contracts/access/Ownable.sol";
import ".deps/npm/@openzeppelin/contracts/utils/math/SafeMath.sol";
import ".deps/npm/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import ".deps/npm/@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract EqidnaToken is ERC20, ERC20Snapshot, ERC20Capped, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant MINTING_INTERVAL = 30 days;
    uint256 private constant INITIAL_SUPPLY = 690420999 * (10 ** 18);
    uint256 private constant MAX_SUPPLY = 11500070000 * (10 ** 18); // Max Supply is 69,000,420,000 which is split among the Blockchains that $QDNA operates on.  
    uint256 private constant AIRDROP_SUPPLY = 6000000000 * (10 ** 18);
    uint256 private AIRDROP_AMOUNT = 10000 * (10 ** 18);
    uint256 private constant MIN_STAKING_AMOUNT = 100 * (10 ** 18);
    uint256 private MIN_STAKING_PERIOD = 60 days;
    uint256 private constant MAX_STAKING_PERIOD = 365 days;
    uint256 private constant MINTING_REWARD_RATE = 369; // 3.69% in basis points
    uint256 private STAKING_REWARD_RATE = 690; // 6.9% in basis points
    uint256 private constant BASIS_POINTS_DIVISOR = 10000;
   

    struct StakingInfo {
        uint256 stakedAmount;
        uint256 stakingTimestamp;
    }

    mapping(address => uint256) private _mintingTimestamps;
    mapping(address => bool) private _airdropClaimed;
    mapping(address => StakingInfo) private _stakingInfo;

    uint256 private _airdropRemainingSupply;

    event StakingRewardRateUpdated(uint256 newRate);
    event StakingMinimumPeriodUpdated(uint256 newPeriod);
    event AirdropClaimed(address indexed user, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    constructor() ERC20("Eqidna Token", "QDNA") ERC20Capped(MAX_SUPPLY) {
        _mint(msg.sender, INITIAL_SUPPLY);
        _airdropRemainingSupply = AIRDROP_SUPPLY;
    }

    // 1. Minting

    function mint() external {
        uint256 lastMintingTimestamp = _mintingTimestamps[msg.sender];
        require(block.timestamp >= lastMintingTimestamp.add(MINTING_INTERVAL), "Minting not available yet");

        uint256 reward = balanceOf(msg.sender).mul(MINTING_REWARD_RATE).div(BASIS_POINTS_DIVISOR);
        _mintingTimestamps[msg.sender] = block.timestamp;

        _mint(msg.sender, reward);
    }

    // 2. Airdrop

    function claimAirdrop() external {
        require(!_airdropClaimed[msg.sender], "Airdrop already claimed");
        require(_airdropRemainingSupply >= AIRDROP_AMOUNT, "Not enough airdrop supply remaining");

        _airdropClaimed[msg.sender] = true;
        _airdropRemainingSupply = _airdropRemainingSupply.sub(AIRDROP_AMOUNT);

        _mint(msg.sender, AIRDROP_AMOUNT);
        emit AirdropClaimed(msg.sender, AIRDROP_AMOUNT);
    }

    function setAirdropAmount(uint256 newAmount) external onlyOwner {
        require(newAmount <= AIRDROP_SUPPLY, "Amount exceeds airdrop supply");
        AIRDROP_AMOUNT = newAmount;
    }

    function isEligibleForAirdrop(address user) external view returns (bool) {
        return !_airdropClaimed[user];
    }

    // 3. Staking

    function stake(uint256 amount) external {
        require(amount >= MIN_STAKING_AMOUNT, "Amount below minimum staking requirement");

        _transfer(msg.sender, address(this), amount);

        StakingInfo storage stakingInfo = _stakingInfo[msg.sender];
        if (stakingInfo.stakedAmount > 0) {
            claimReward();
        }

        stakingInfo.stakedAmount = stakingInfo.stakedAmount.add(amount);
        stakingInfo.stakingTimestamp = block.timestamp;

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        StakingInfo storage stakingInfo = _stakingInfo[msg.sender];
        require(stakingInfo.stakedAmount >= amount, "Amount exceeds staked balance");

        claimReward();

        stakingInfo.stakedAmount = stakingInfo.stakedAmount.sub(amount);
        if (stakingInfo.stakedAmount == 0) {
            stakingInfo.stakingTimestamp = 0;
        }

        _transfer(address(this), msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    function claimReward() public {
        StakingInfo storage stakingInfo = _stakingInfo[msg.sender];
        require(stakingInfo.stakedAmount > 0, "No staked balance");

        uint256 stakingDuration = block.timestamp.sub(stakingInfo.stakingTimestamp);
        require(stakingDuration >= MIN_STAKING_PERIOD, "Staking period not met");

        uint256 reward = stakingInfo.stakedAmount.mul(STAKING_REWARD_RATE).div(BASIS_POINTS_DIVISOR);
        stakingInfo.stakingTimestamp = block.timestamp;

        _mint(msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

    function setStakingRewardRate(uint256 newRate) external onlyOwner {
        STAKING_REWARD_RATE = newRate;
        emit StakingRewardRateUpdated(newRate);
    }

    function setStakingMinimumPeriod(uint256 newPeriod) external onlyOwner {
        MIN_STAKING_PERIOD = newPeriod;
        emit StakingMinimumPeriodUpdated(newPeriod);
    }

    function stakedBalanceOf(address account) external view returns (uint256) {
        return _stakingInfo[account].stakedAmount;
    }

    function mintingTimestampOf(address account) external view returns (uint256) {
        return _mintingTimestamps[account];
    }

    function stakingTimestampOf(address account) external view returns (uint256) {
        return _stakingInfo[account].stakingTimestamp;
    }

    // 4. Withdrawing

    function withdrawTokens(IERC20 token, uint256 amount) external onlyOwner {
        require(token != IERC20(address(this)), "Cannot withdraw EqidnaToken");

        token.safeTransfer(msg.sender, amount);
    }

    function withdrawEther(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Not enough Ether in contract");

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Ether withdrawal failed");
    }

    // 5. Additional Functions

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Snapshot) {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal override(ERC20, ERC20Capped) {
        super._mint(account, amount);
    }


      uint256 private _currentSnapshotId;

  function snapshot() external onlyOwner returns (uint256) {
    _currentSnapshotId++;
    _snapshot();
    return _currentSnapshotId;
    }

    function getSnapshotId() external view onlyOwner returns (uint256) {
    return _currentSnapshotId;
    }
}