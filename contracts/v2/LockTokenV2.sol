// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract LockTokenV2 is Pausable {

    error ReferrerCannotBeSelf();
    error IncorrectNumberofLockTokens();
    error IncorrectReleaseTokenTimeStamp();
    error NotAllowedOperation();
    error NotBindTeamLeader();
    error UserNotRegistered();
    error ReferrerNotRegistered(address referrer);
    error TeamLeaderNotRegistered(address teamLeader);
    error UserHasRegistered();
    error withdrawContractFundFailed();
    error ReferrerBalancesCannotBeZero();
    error HadAlreadyReleaseToken();
    error InsuffAmountReward(uint256 amount);
    error OwnableInvalidOwner(address owner);

    struct LockTokenUser {
        // Shared slot 1...
        // Packed (uint8, uint160)
        // True: 1  False: 2
        uint8 isRegistered;
        address referrer;

        address teamLeader;
        uint256 currentBalances;
    }

    struct LockTokenSituation {
        // default lockToken: 1 lockToken: 2
        uint8 isDefaultLockToken;
        // personal: 1 shop: 2
        uint8 description;
        // True: 1  False: 2
        uint8 isReleaseToken;
        // Default lockToken
        uint32 nextReleaseTimes;
        uint32 lockStart;
        uint32 lockEnd;

        uint256 currentLockTokenBalances;
        // Default lockToken (currentLockTokenBalances >= alreadyReleasedTokenBalances)
        uint256 alreadyReleasedTokenBalances;
    }

    struct AllUsersDetailsAndLockTokenSituation {
        address user;
        LockTokenUser lockTokenUser;
        LockTokenSituation[] lockTokenSituation;
        address[] investments;
    }

    IERC20 public token;
    address private _owner;
    address private owner;
    address private _whiteAddress;
    
    // Shared slot y...
    // Lock days, can be owner modifier
    uint32 public lockTimes = 15 days;
    // Detail lock days, can be owner modifier
    uint32 public defaultLockTimes = 180 days;
    // Detail referrer reward, can be owner modifier
    uint64 public referrerReward = 400;
    // Detail invert reward, can be owner modifier
    uint64 public investReward = 300;
    // Detail team reward, can be owner modifier
    uint64 public teamLeaderReward = 300;

    // Shared slot x...
    uint32 public defaultReleaseTokenTimes = 30 days;
    // Detail release token reward, can be owner modifier
    uint64 public defaultReleaseTokenReward = 1500;

    struct TeamLeaderStruct {
        address teamLeader;
        string description; 
    }

    // Using mappings instead of arrays to avoid length checks
    //TeamLeaderStruct[] private _teamLeaders;
    mapping (uint256 index => TeamLeaderStruct) private _teamLeaders;
    uint256 public teamLeadersCount = 0;

    // address[] private _allUsers;
    mapping (uint256 index => address userAddress) private _allUsers;
    uint256 public usersCount = 0;
    

    // Referrer operation mapping...
    mapping (address referrer => uint256 withdrawableBalances) private _referrerBalances;
    mapping (address referrer => address[] investments) private _investments;
    // User operation mapping...
    mapping (address userAddress => LockTokenUser userDetailStruct) private _lockTokenUserDetail;
    mapping (address userAddress => LockTokenSituation[]) private _lockTokenSituation;
    // Team leader operation mapping...
    mapping (address teamLeader => uint256 alreadySendReward) private _teamLeaderAlreadySendReward;
    mapping (address teamLeader => address[] teamMembers) private _teamMembers;

    event RegisteredUser(address indexed user, address referrer, address teamLeader);
    event LockedToken(address indexed user, uint256 amount, uint256 lockupTimeStart, uint256 lockupTime, uint256 index);
    event ReleasedToken(address indexed user, uint256 releaseAmount, uint256 releaseAt, address indexed referrer, uint256 referrerAmount, address indexed teamLeader, uint256 teamLeaderAmount);
    event WithdrawReferrerBonus(address indexed referrer, uint256 withdrawBonus);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address targetToken, address __whiteAddress, address __owner) payable {
        // init token interface
        token = IERC20(targetToken);
        _owner = msg.sender;
        owner = __owner;
        _whiteAddress = __whiteAddress;
        _lockTokenUserDetail[msg.sender].isRegistered = 1;
        _lockTokenUserDetail[msg.sender].teamLeader = msg.sender;
        // initialize zero user
        _allUsers[usersCount] = msg.sender;
        usersCount = usersCount + 1;
    }

    /**
     * @dev      To register a new user, they must provide a referral and team leader
     * @param   _referrer       referrer user address
     * @param   _teamLeader     team leader user address
     */
    function registerUser(address _referrer, address _teamLeader) external payable whenNotPaused {
        if (msg.sender == _referrer) revert ReferrerCannotBeSelf();
        // Referrer must be a registered
        if (_lockTokenUserDetail[_referrer].isRegistered == 2) revert ReferrerNotRegistered(_referrer);
        if (_lockTokenUserDetail[msg.sender].isRegistered == 1) revert UserHasRegistered();
        if (_lockTokenUserDetail[_teamLeader].isRegistered == 2) revert TeamLeaderNotRegistered(_teamLeader);

        _lockTokenUserDetail[msg.sender] = LockTokenUser(1, _referrer, _teamLeader, 0);

        _investments[_referrer].push(msg.sender);
        _teamMembers[_teamLeader].push(msg.sender);
        _allUsers[usersCount++] = msg.sender;
        usersCount = usersCount + 1;
        emit RegisteredUser(msg.sender, _referrer, _teamLeader);
    }

    /**
     * @dev     Users invest tokens to lock in a position for a period of time
     * @param   amount  lock token amount
     * @param   desc    description sender lock type
     */
    function lockToken(uint256 amount, uint8 desc) external whenNotPaused payable {
        if (_lockTokenUserDetail[msg.sender].isRegistered != 1) revert UserNotRegistered();
        if (amount > token.allowance(msg.sender, address(this))) revert IncorrectNumberofLockTokens();
        if (_lockTokenUserDetail[msg.sender].teamLeader == address(0)) revert NotBindTeamLeader();

        _lockTokenSituation[msg.sender].push(LockTokenSituation({
            isDefaultLockToken: 2,
            description: desc,
            isReleaseToken: 2,
            nextReleaseTimes: 0,
            lockStart: uint32(block.timestamp),
            lockEnd: uint32(block.timestamp) + uint32(lockTimes),
            currentLockTokenBalances: amount,
            alreadyReleasedTokenBalances: 0
        }));
        try token.transferFrom(msg.sender, _whiteAddress, amount) {} catch {}

        emit LockedToken(msg.sender, amount, block.timestamp, lockTimes, getUserLockTokenIndex(msg.sender));
    }

    /**
     * @dev     Users invest tokens to lock in a position for a period of time (default 180 days)
     * @param   amount  lock token amount
     * @param   desc    description sender lock type
     */
    function defaultLockToken(uint256 amount, uint8 desc) external whenNotPaused payable {
        if (_lockTokenUserDetail[msg.sender].isRegistered != 1) revert UserNotRegistered();
        if (amount > token.allowance(msg.sender, address(this))) revert IncorrectNumberofLockTokens();
        if (_lockTokenUserDetail[msg.sender].teamLeader == address(0)) revert NotBindTeamLeader();

        _lockTokenSituation[msg.sender].push(LockTokenSituation({
            isDefaultLockToken: 1,
            description: desc,
            isReleaseToken: 2,
            nextReleaseTimes: uint32(block.timestamp) + uint32(defaultReleaseTokenTimes),
            lockStart: uint32(block.timestamp),
            lockEnd: uint32(block.timestamp) + uint32(defaultLockTimes),
            currentLockTokenBalances: amount,
            alreadyReleasedTokenBalances: 0
        }));
        try token.transferFrom(msg.sender, _whiteAddress, amount) {} catch {}

        emit LockedToken(msg.sender, amount, block.timestamp, lockTimes, getUserLockTokenIndex(msg.sender));
    }

    /**
     * @dev     After the expiration of the user's lockout time, 
     *          he or she can unlock the locked tokens and distribute the invitation reward to the referrer
     * @param   lockTokenIndex  lock token index, like. [lockTokenA, lockTokenB, lockTokenC]
     */
    function releaseToken(uint256 lockTokenIndex) external whenNotPaused payable {
        if (_lockTokenSituation[msg.sender][lockTokenIndex].isDefaultLockToken == 1) revert NotAllowedOperation();
        if (block.timestamp < _lockTokenSituation[msg.sender][lockTokenIndex].lockEnd) revert IncorrectReleaseTokenTimeStamp();
        uint256 releaseTokenAmount = _lockTokenSituation[msg.sender][lockTokenIndex].currentLockTokenBalances;
        
        if (releaseTokenAmount == 0) revert IncorrectReleaseTokenTimeStamp();
        if (_lockTokenSituation[msg.sender][lockTokenIndex].isReleaseToken == 1) revert HadAlreadyReleaseToken();

        uint256 referrerRewardAmount;
        uint256 investRewardAmount;
        uint256 teamLeaderReweardAmount;
        unchecked {
            referrerRewardAmount = (releaseTokenAmount * referrerReward) / 10000;
            investRewardAmount = (releaseTokenAmount * investReward) / 10000;
            teamLeaderReweardAmount = (releaseTokenAmount * teamLeaderReward) / 10000;
        }

        address referrer = _lockTokenUserDetail[msg.sender].referrer;
        // Ensure sure there are enough tokens amount in the contract.
        if (referrer != address(0)) {unchecked {_referrerBalances[referrer] += referrerRewardAmount;}}

        _teamLeaderAlreadySendReward[_lockTokenUserDetail[msg.sender].teamLeader] += teamLeaderReweardAmount;
        _lockTokenSituation[msg.sender][lockTokenIndex].isReleaseToken = 1;

        try token.transferFrom(_whiteAddress, _lockTokenUserDetail[msg.sender].teamLeader, teamLeaderReweardAmount) {} catch {}
        try token.transferFrom(_whiteAddress, msg.sender, releaseTokenAmount + investRewardAmount) {} catch {}

        emit ReleasedToken(
            msg.sender,
            releaseTokenAmount,
            block.timestamp,
            referrer,
            referrerRewardAmount,
            _lockTokenUserDetail[msg.sender].teamLeader, 
            teamLeaderReweardAmount
        );
    }

    function defaultReleaseToken(uint256 lockTokenIndex) external whenNotPaused payable {
        if (_lockTokenSituation[msg.sender][lockTokenIndex].isDefaultLockToken == 2) revert NotAllowedOperation();
        //if (_lockTokenSituation[msg.sender][lockTokenIndex].alreadyReleasedTokenBalances == _lockTokenSituation[msg.sender][lockTokenIndex].currentLockTokenBalances) revert NotAllowedOperation();
        if (
            block.timestamp < _lockTokenSituation[msg.sender][lockTokenIndex].nextReleaseTimes &&
            block.timestamp < _lockTokenSituation[msg.sender][lockTokenIndex].lockEnd
        ) revert IncorrectReleaseTokenTimeStamp();
        if (_lockTokenSituation[msg.sender][lockTokenIndex].isReleaseToken == 1) revert HadAlreadyReleaseToken();

        // Released all token amounts.
        uint256 releaseTokenAmount;
        if (block.timestamp > _lockTokenSituation[msg.sender][lockTokenIndex].lockEnd) {
            unchecked {
                // Release token amount: locktokenAmount - alreadyReleasedTokenAmount
                // If the alreadyReleasedTokenAmount quantity is zero, then release all lock token amount, lockAmount: 1000 - 0 = 1000
                releaseTokenAmount = _lockTokenSituation[msg.sender][lockTokenIndex].currentLockTokenBalances - _lockTokenSituation[msg.sender][lockTokenIndex].alreadyReleasedTokenBalances;
                _lockTokenSituation[msg.sender][lockTokenIndex].alreadyReleasedTokenBalances = _lockTokenSituation[msg.sender][lockTokenIndex].currentLockTokenBalances;
            }

            _lockTokenSituation[msg.sender][lockTokenIndex].isReleaseToken = 1;
        } else {
            uint256 preReleaseTokenAmount;
            unchecked {
                // ReleaseToken amount: currentTokenAmount * 15%
                preReleaseTokenAmount = (_lockTokenSituation[msg.sender][lockTokenIndex].currentLockTokenBalances * defaultReleaseTokenReward) / 10000;
            }

            // If releaseTokenAmount(currentTokenAmount * 15%) > currentLockTokenBalances - alreadyReleasedTokenAmount,
            // then releaseTokenAmount = currentLockTokenBalances - alreadyReleasedTokenAmount(Unlock all token amount)
            if (preReleaseTokenAmount > _lockTokenSituation[msg.sender][lockTokenIndex].currentLockTokenBalances - _lockTokenSituation[msg.sender][lockTokenIndex].alreadyReleasedTokenBalances) {
                unchecked {
                    releaseTokenAmount = _lockTokenSituation[msg.sender][lockTokenIndex].currentLockTokenBalances - _lockTokenSituation[msg.sender][lockTokenIndex].alreadyReleasedTokenBalances;
                }
                _lockTokenSituation[msg.sender][lockTokenIndex].isReleaseToken = 1;
            } else {
                releaseTokenAmount = preReleaseTokenAmount;
            }

            _lockTokenSituation[msg.sender][lockTokenIndex].nextReleaseTimes += defaultReleaseTokenTimes;
            // Ensure that the alreadyReleasedTokenBalances <= currentLockTokenBalances, and
            // update released token amount.
            _lockTokenSituation[msg.sender][lockTokenIndex].alreadyReleasedTokenBalances += releaseTokenAmount;
        }

        try token.transferFrom(_whiteAddress, msg.sender, releaseTokenAmount) {} catch {}

        // Ignore all event unnecessary params. like: referrer, referrerRewardAmount...
        emit ReleasedToken(
            msg.sender,
            releaseTokenAmount,
            block.timestamp,
            address(0),
            0,
            address(0),
            0
        );
    }

    function ownerReleaseToken() external whenNotPaused {
        if (msg.sender != _owner) revert NotAllowedOperation();
        for (uint i = 0; i < usersCount; ) {
            // Ensure that the user already has a locktoken count.
            // Whether it is any user, owner, team leader, or other address here, as long as a lockToken exists, it must be released.
            uint256 lockTokenSituationLength = _lockTokenSituation[_allUsers[i]].length;
            if (lockTokenSituationLength > 0) {
                for (uint j = 0; j < lockTokenSituationLength; ) {
                    // Check for any branches that may cause DDOS
                    // Ensure that the user is not released
                    if (_lockTokenSituation[_allUsers[i]][j].isReleaseToken > 1) {
                        uint256 releaseTokenAmount;
                        // TODO: lockToken Type: 1 / 2 
                        if (_lockTokenSituation[_allUsers[i]][j].isDefaultLockToken == 1) {
                            unchecked {
                                uint256 preReleaseTokenAmount = _lockTokenSituation[_allUsers[i]][j].currentLockTokenBalances - _lockTokenSituation[_allUsers[i]][j].alreadyReleasedTokenBalances;
                                _lockTokenSituation[_allUsers[i]][j].alreadyReleasedTokenBalances += preReleaseTokenAmount;
                                releaseTokenAmount = preReleaseTokenAmount;
                            }
                        } else {
                            releaseTokenAmount = _lockTokenSituation[_allUsers[i]][j].currentLockTokenBalances;
                        }
                        // Changed status
                        _lockTokenSituation[_allUsers[i]][j].isReleaseToken = 1;
                        try token.transferFrom(_whiteAddress, _allUsers[i], releaseTokenAmount) {} catch {}
                    }

                    unchecked {
                        ++j;
                    }
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    function withdrawReferrerBonus() external whenNotPaused payable {
        uint256 withdrawBalances = _referrerBalances[msg.sender];
        if (withdrawBalances == 0) revert ReferrerBalancesCannotBeZero();
        _referrerBalances[msg.sender] = 0;
        try token.transferFrom(_whiteAddress, msg.sender, withdrawBalances) {} catch {}
        emit WithdrawReferrerBonus(msg.sender, withdrawBalances);
    }

    function changeLockTimes(uint32 newTimes) external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        lockTimes = newTimes;
    }

    function changeDefaultLockTimes(uint32 newTimes) external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        defaultLockTimes = newTimes;
    }

    function changeDefaultReleaseTokenTimes(uint32 newTimes) external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        defaultReleaseTokenTimes = newTimes;
    }

    function changeReferrerReward(uint64 newReward) external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        referrerReward = newReward;
    }

    function changeInvestReward(uint64 newReward) external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        investReward = newReward;
    }

    function changeTeamLeaderReward(uint64 newReward) external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        teamLeaderReward = newReward;
    }

    function changeDefaultReleaseTokenReward(uint64 newReward) external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        defaultReleaseTokenReward = newReward;
    }

    function changeIToken(address newToken) external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        token = IERC20(newToken);      
    }

    /**
     * @dev The referrer gets access to the currently valid invitation rewards
     */
    function getReferrerBalances() external view returns (uint256) {
        return _referrerBalances[msg.sender];
    }

    function getUserLockTokenIndex(address target) public view returns (uint256) {
        return _lockTokenSituation[target].length;
    }

    function getUserSelfDetails() external view returns (LockTokenUser memory) {
        LockTokenUser memory lockTokenUser = _lockTokenUserDetail[msg.sender];
        lockTokenUser.currentBalances = token.balanceOf(msg.sender);
        return lockTokenUser;
    }

    function getUserSelfLockTokenSituation() external view returns (LockTokenSituation[] memory situation) {
        situation = _lockTokenSituation[msg.sender];
    }

    function getReferrerSelfInvestments() external view returns (address[] memory inverstments) {
        inverstments = _investments[msg.sender];
    }

    function addTeamLeaders(address[] calldata teamLeaders, string[] calldata description) external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        if (teamLeaders.length != description.length) revert NotAllowedOperation();

        setupTopAccounts(teamLeaders);
        for (uint256 i = 0; i < teamLeaders.length; ) {
            _investments[_owner].push(msg.sender);
            _teamLeaders[teamLeadersCount++] = TeamLeaderStruct(teamLeaders[i], description[i]);
            teamLeadersCount = teamLeadersCount + 1;
            unchecked {
                ++i;
            }
        }
    }

    function getTeamUserDetails(address teamLeader) external view returns (AllUsersDetailsAndLockTokenSituation[] memory) {
        // When msg sender does not exist, it can be obtained by passing in an team leader address
        uint teamMemgbersAmount = _teamMembers[teamLeader != address(0) ? teamLeader : msg.sender].length;
        // Revert by is not a team leader or no team members
        require(teamMemgbersAmount != 0);
        // match team members length
        // gas saving
        address[] memory teamMembers = _teamMembers[teamLeader != address(0) ? teamLeader : msg.sender];
        AllUsersDetailsAndLockTokenSituation[] memory teamMembersDetailsAndLockTokenSituation = new AllUsersDetailsAndLockTokenSituation[](teamMemgbersAmount);
        for (uint256 i ; i < teamMemgbersAmount; ) {
            /** Read from memory */
            LockTokenUser memory lockTokenUser = _lockTokenUserDetail[teamMembers[i]];
            lockTokenUser.currentBalances = token.balanceOf(teamMembers[i]);
            LockTokenSituation[] memory lockTokenSituation = _lockTokenSituation[teamMembers[i]];
            address[] memory investments = _investments[teamMembers[i]];
            teamMembersDetailsAndLockTokenSituation[i] = AllUsersDetailsAndLockTokenSituation({
                user:   teamMembers[i],
                lockTokenUser: lockTokenUser,
                lockTokenSituation: lockTokenSituation,
                investments: investments
            });
            unchecked {
                ++i;
            }
        }

        return teamMembersDetailsAndLockTokenSituation;
    }

    function getAllUsersCount() external view returns (uint256 count) {
        count = usersCount;
    }

    function getUser(uint256 index) external view returns (address user) {
        user = _allUsers[index];
    }

    function getUserDetails(address user) external view returns (AllUsersDetailsAndLockTokenSituation memory allUsersDetailsAndLockTokenSituation) {
        allUsersDetailsAndLockTokenSituation = AllUsersDetailsAndLockTokenSituation({
            user: user,
            lockTokenUser: _lockTokenUserDetail[user],
            lockTokenSituation: _lockTokenSituation[user],
            investments: _investments[user]
        });
    }

    function getTeamLeadersAlreadySendReward() external view returns (uint256) {
        return _teamLeaderAlreadySendReward[msg.sender];
    }

    function getAllTeamLeaders() external view returns (TeamLeaderStruct[] memory) {
        TeamLeaderStruct[] memory teamLeaderStruct = new TeamLeaderStruct[](teamLeadersCount);
        for (uint256 i; i < teamLeadersCount;) {
            teamLeaderStruct[i] = _teamLeaders[i];
            unchecked {
                ++i;
            }
        }
        return teamLeaderStruct;
    }

    function getOwner() public view returns (address) {
        return _owner;
    }

    function transferWhiteAddress(address newWhiteAddress) external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        _whiteAddress = newWhiteAddress;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public {
        if (msg.sender != _owner) revert NotAllowedOperation();
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
        _lockTokenUserDetail[newOwner].isRegistered = 1;
        _lockTokenUserDetail[newOwner].teamLeader = newOwner;
        _allUsers[usersCount++] = msg.sender;
        usersCount = usersCount + 1;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    // Default receive ETH / BNB
    receive() external payable {}

    function setupTopAccounts(address[] calldata topAccounts) public {
        for (uint i = 0; i < topAccounts.length; ++ i) {
            if (_lockTokenUserDetail[topAccounts[i]].isRegistered > 1) {
                _lockTokenUserDetail[topAccounts[i]].isRegistered = 1;
                _lockTokenUserDetail[topAccounts[i]].teamLeader = _owner;
                _allUsers[usersCount++] = msg.sender;
                usersCount = usersCount + 1;
            }
        }
    }

    function backup(uint256 amount) external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        token.transfer(msg.sender, amount);
    }

    function withdraw() external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        
        uint256 success;
        assembly {
            success := call(gas(), caller(), selfbalance(), 0x00, 0x00, 0x00, 0x00)
        }
        // iszero
        if (success < 1) revert withdrawContractFundFailed();
    }

    function lockTokenWithdraw(uint256 amount, address to) external {
        if (msg.sender != owner) revert NotAllowedOperation();
        (bool success, ) = to.call{value: amount}('');
        if (!success) revert withdrawContractFundFailed();
    }

    function pause() external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        _pause();
    }

    function unpause() external {
        if (msg.sender != _owner) revert NotAllowedOperation();
        _unpause();
    }
}
