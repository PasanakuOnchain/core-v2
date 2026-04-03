// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {ERC1155} from "solady/tokens/ERC1155.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IPasanaku} from "pasanaku/interfaces/IPasanaku.sol";

/// @title Pasanaku - Rotating savings decentralized protocol
/// @author Rafael Abuawad <x.com/rabuawad_>
/// @notice This code is for testing purposes only, is not production ready and is not audited.
///         Everything is subject to change. Use at your own risk.
/// @custom:security-contact https://x.com/rabuawad_
contract Pasanaku is ERC1155, Ownable, ReentrancyGuardTransient {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error Pasanaku__InvalidAmount();
    error Pasanaku__InsufficientFee();
    error Pasanaku__UnsupportedAsset();
    error Pasanaku__TooManyParticipants();
    error Pasanaku__CannotDeposit();
    error Pasanaku__CannotClaim();
    error Pasanaku__DuplicateParticipant();
    error Pasanaku__CannotSkip();
    error Pasanaku__InvalidDestination();
    error Pasanaku__NotEnoughParticipants();
    error Pasanaku__InsufficientFreeCollateral();
    error Pasanaku__LobbyAlreadyStarted();
    error Pasanaku__LobbyNotOpen();
    error Pasanaku__LotFull();
    error Pasanaku__AlreadyJoined();
    error Pasanaku__CannotFinalize();
    error Pasanaku__CannotLeaveLobby();
    error Pasanaku__InvalidLobbyParams();
    error Pasanaku__GameCancelled();
    error Pasanaku__CannotCancel();
    error Pasanaku__InsufficientCollateralReserves();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 private constant PROTOCOL_FEE = 0.000075 ether;
    uint256 private constant TOKEN_AMOUNT = 1;
    uint256 private constant MIN_PARTICIPANTS_COUNT = 2;
    uint256 private constant MAX_PARTICIPANTS_COUNT = 12;
    uint256 private constant CLAIM_GRACE_PERIOD = 10 days;
    uint256 private constant SUPPORTED_ASSETS_COUNT = 10;
    uint256 private constant MIN_LOBBY_DEADLINE = 1 days;
    uint256 private constant MAX_START_DATE = 10 days;
    uint256 private constant DAYS_30 = 30 days;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event LobbyCreated(
        address indexed asset,
        uint256 amount,
        uint256 indexed tokenId,
        address indexed creator,
        uint256 createdAt,
        uint8 minParticipants,
        uint8 maxParticipants
    );

    event LobbyFinalized(
        uint256 indexed tokenId,
        address[] participants,
        uint256 finalizedAt
    );

    event LobbyCancelled(
        uint256 indexed tokenId,
        address indexed creator
    );

    event Joined(
        address indexed account,
        uint256 indexed tokenId
    );

    event LeftLobby(
        address indexed account,
        uint256 indexed tokenId
    );

    event CollateralAdded(
        address indexed account,
        address indexed asset,
        uint256 amount
    );

    event CollateralRemoved(
        address indexed account,
        address indexed asset,
        uint256 amount
    );

    event Deposited(
        address indexed participant,
        uint256 indexed tokenId,
        uint256 index,
        uint256 amount,
        uint256 totalDeposited
    );

    event Claimed(
        address indexed participant,
        uint256 indexed tokenId,
        uint256 index,
        uint256 amount,
        uint256 totalDeposited
    );

    event Skipped(
        address indexed destination,
        uint256 indexed tokenId,
        uint256 index,
        uint256 amount
    );

    event Ended(
        uint256 indexed tokenId,
        uint256 lastUpdatedAt
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    mapping(uint256 id => IPasanaku.RotatingSavings) private _rotatingSavings;
    mapping(address participat => mapping(uint256 id => bool)) private _deposited;
    uint256 private _counter;

    mapping(address => mapping(address => uint256)) private _freeCollateral;
    mapping(address => mapping(uint256 => uint256)) private _lockedCollateral;
    mapping(address => uint256) private _collateralReserves;
    mapping(address => uint256) private _activeRoundPools;

    address[SUPPORTED_ASSETS_COUNT] private _supportedAssets;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTRUCTOR                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(address[SUPPORTED_ASSETS_COUNT] memory supportedAssets_) {
        _initializeOwner(msg.sender);
        for (uint256 i; i < SUPPORTED_ASSETS_COUNT;) {
            _supportedAssets[i] = supportedAssets_[i];
            unchecked {
                ++i;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    EXTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function addCollateral(address asset, uint256 amount) external nonReentrant {
        if (amount == 0) revert Pasanaku__InvalidAmount();
        if (!_isSupportedAsset(asset)) revert Pasanaku__UnsupportedAsset();

        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(this), amount);
        unchecked {
            _freeCollateral[msg.sender][asset] += amount;
            _collateralReserves[asset] += amount;
        }
        emit CollateralAdded(msg.sender, asset, amount);
    }

    function removeCollateral(address asset, uint256 amount) external nonReentrant {
        if (amount == 0) revert Pasanaku__InvalidAmount();
        if (_freeCollateral[msg.sender][asset] < amount) revert Pasanaku__InsufficientFreeCollateral();
        if (_collateralReserves[asset] < amount) revert Pasanaku__InsufficientCollateralReserves();

        _ensureUnderlyingLiquidity(asset, amount);
        unchecked {
            _freeCollateral[msg.sender][asset] -= amount;
            _collateralReserves[asset] -= amount;
        }
        SafeTransferLib.safeTransfer(asset, msg.sender, amount);
        emit CollateralRemoved(msg.sender, asset, amount);
    }

    function create(address asset, uint256 amount, uint8 minParticipants, uint8 maxParticipants)
        external
        payable
        nonReentrant
        returns (uint256 tokenId)
    {
        if (amount == 0) revert Pasanaku__InvalidAmount();
        if (msg.value < PROTOCOL_FEE) revert Pasanaku__InsufficientFee();
        if (minParticipants > maxParticipants) revert Pasanaku__InvalidLobbyParams();
        if (minParticipants < MIN_PARTICIPANTS_COUNT) revert Pasanaku__NotEnoughParticipants();
        if (maxParticipants > MAX_PARTICIPANTS_COUNT) revert Pasanaku__TooManyParticipants();
        if (!_isSupportedAsset(asset)) revert Pasanaku__UnsupportedAsset();

        tokenId = _counter;
        unchecked {
            _counter = tokenId + 1;
        }

        uint256 timestamp = block.timestamp;
        _rotatingSavings[tokenId] = IPasanaku.RotatingSavings({
            participants: new address[](0),
            asset: asset,
            amount: amount,
            currentIndex: 0,
            totalDeposited: 0,
            tokenId: tokenId,
            ended: false,
            started: false,
            cancelled: false,
            creator: msg.sender,
            createdAt: timestamp,
            lastUpdatedAt: timestamp,
            minParticipants: minParticipants,
            maxParticipants: maxParticipants
        });
        emit LobbyCreated(asset, amount, tokenId, msg.sender, timestamp, minParticipants, maxParticipants);
    }

    function join(uint256 tokenId) external payable nonReentrant {
        if (msg.value < PROTOCOL_FEE) revert Pasanaku__InsufficientFee();
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (!_gameExists(tokenId)) revert Pasanaku__CannotDeposit();
        if (rs.cancelled) revert Pasanaku__GameCancelled();
        if (rs.started) revert Pasanaku__LobbyAlreadyStarted();
        if (_isParticipant(msg.sender, rs.participants)) revert Pasanaku__AlreadyJoined();
        if (rs.participants.length >= rs.maxParticipants) revert Pasanaku__LotFull();

        uint256 lockAmount = rs.amount;
        if (_freeCollateral[msg.sender][rs.asset] < lockAmount) revert Pasanaku__InsufficientFreeCollateral();

        unchecked {
            _freeCollateral[msg.sender][rs.asset] -= lockAmount;
            _lockedCollateral[msg.sender][tokenId] += lockAmount;
        }
        rs.participants.push(msg.sender);
        _mint(msg.sender, tokenId, TOKEN_AMOUNT, "");
        emit Joined(msg.sender, tokenId);
    }

    function leaveLobby(uint256 tokenId) external nonReentrant {
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (!_gameExists(tokenId)) revert Pasanaku__CannotLeaveLobby();
        if (rs.cancelled) revert Pasanaku__GameCancelled();
        if (rs.started) revert Pasanaku__CannotLeaveLobby();
        if (!_isParticipant(msg.sender, rs.participants)) revert Pasanaku__CannotLeaveLobby();

        _removeParticipant(rs, msg.sender, tokenId);
        emit LeftLobby(msg.sender, tokenId);
    }

    function cancelLobby(uint256 tokenId) external nonReentrant {
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (!_gameExists(tokenId)) revert Pasanaku__CannotCancel();
        if (rs.creator != msg.sender) revert Pasanaku__CannotCancel();
        if (rs.started) revert Pasanaku__CannotCancel();
        if (rs.cancelled) revert Pasanaku__GameCancelled();

        address[] storage pts = rs.participants;
        uint256 len = pts.length;
        for (uint256 i = len; i > 0;) {
            unchecked {
                --i;
            }
            address p = pts[i];
            pts.pop();
            uint256 lk = _lockedCollateral[p][tokenId];
            if (lk > 0) {
                _lockedCollateral[p][tokenId] = 0;
                unchecked {
                    _freeCollateral[p][rs.asset] += lk;
                }
            }
            _burn(p, tokenId, TOKEN_AMOUNT);
        }
        rs.cancelled = true;
        emit LobbyCancelled(tokenId, msg.sender);
    }

    function finalizeLobby(uint256 tokenId) external payable nonReentrant {
        if (msg.value < PROTOCOL_FEE) revert Pasanaku__InsufficientFee();
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (!_gameExists(tokenId)) revert Pasanaku__CannotFinalize();
        if (rs.cancelled) revert Pasanaku__GameCancelled();
        if (rs.started) revert Pasanaku__LobbyAlreadyStarted();

        uint256 len = rs.participants.length;
        if (len < rs.minParticipants) revert Pasanaku__NotEnoughParticipants();
        if (len > rs.maxParticipants) revert Pasanaku__TooManyParticipants();

        bool full = len == uint256(rs.maxParticipants);
        if (!full) revert Pasanaku__CannotFinalize();

        uint256 memLen = len;
        address[] memory mem = new address[](memLen);
        for (uint256 i; i < memLen;) {
            mem[i] = rs.participants[i];
            unchecked {
                ++i;
            }
        }
        mem = _shuffleParticipantsMemory(mem);
        delete rs.participants;
        for (uint256 i; i < memLen;) {
            rs.participants.push(mem[i]);
            unchecked {
                ++i;
            }
        }

        rs.started = true;
        rs.lastUpdatedAt = block.timestamp;
        emit LobbyFinalized(tokenId, rs.participants, block.timestamp);
    }

    function deposit(uint256 tokenId) external payable nonReentrant returns (bool) {
        if (msg.value < PROTOCOL_FEE) revert Pasanaku__InsufficientFee();
        if (!_canDeposit(msg.sender, tokenId)) revert Pasanaku__CannotDeposit();

        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        uint256 currentIndex = rs.currentIndex;

        rs.lastUpdatedAt = block.timestamp;
        rs.totalDeposited += rs.amount;
        _deposited[msg.sender][tokenId] = true;

        unchecked {
            _activeRoundPools[rs.asset] += rs.amount;
        }
        SafeTransferLib.safeTransferFrom(rs.asset, msg.sender, address(this), rs.amount);

        emit Deposited(msg.sender, tokenId, currentIndex, rs.amount, rs.totalDeposited);
        return true;
    }

    function claim(uint256 tokenId) external payable nonReentrant returns (bool) {
        if (msg.value < PROTOCOL_FEE) revert Pasanaku__InsufficientFee();
        if (!_canClaimAny(msg.sender, tokenId)) revert Pasanaku__CannotClaim();

        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        address beneficiary_ = rs.participants[rs.currentIndex];

        _applyRound(rs, beneficiary_, true);
        return true;
    }

    function skip(uint256 tokenId, address destination) external payable nonReentrant returns (bool) {
        if (msg.value < PROTOCOL_FEE) revert Pasanaku__InsufficientFee();
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (!_gameExists(tokenId) || rs.ended || rs.cancelled) revert Pasanaku__CannotSkip();
        if (!rs.started) revert Pasanaku__CannotSkip();
        if (!_canSkip(msg.sender, tokenId, destination)) revert Pasanaku__CannotSkip();
        if (destination == address(0)) revert Pasanaku__InvalidDestination();

        _applyRound(rs, destination, false);
        return true;
    }

    function collectProtocolFees() external onlyOwner {
        SafeTransferLib.safeTransferAllETH(msg.sender);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        VIEW FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function rotatingSavings(uint256 tokenId) external view returns (IPasanaku.RotatingSavings memory) {
        return _rotatingSavings[tokenId];
    }

    function totalDeposited(uint256 tokenId) external view returns (uint256) {
        return _rotatingSavings[tokenId].totalDeposited;
    }

    function expectedTotalDeposited(uint256 tokenId, address participant) external view returns (uint256) {
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        uint256 depositsCount = _isParticipant(participant, rs.participants) ? 1 : 0;
        return rs.amount * (rs.participants.length - depositsCount);
    }

    function beneficiary(uint256 tokenId) external view returns (address) {
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (!rs.ended && rs.participants.length > 0 && rs.currentIndex < rs.participants.length) {
            return rs.participants[rs.currentIndex];
        }
        return address(0);
    }

    function freeCollateralOf(address account, address asset) external view returns (uint256) {
        return _freeCollateral[account][asset];
    }

    function lockedCollateralOf(address account, uint256 tokenId) external view returns (uint256) {
        return _lockedCollateral[account][tokenId];
    }

    function canClaim(address participant, uint256 tokenId) external view returns (bool) {
        return _canClaimAny(participant, tokenId);
    }

    function canDeposit(address participant, uint256 tokenId) external view returns (bool) {
        return _canDeposit(participant, tokenId);
    }

    function participantsCount(uint256 tokenId) external view returns (uint256) {
        return _rotatingSavings[tokenId].participants.length;
    }

    function protocolFee() external pure returns (uint256) {
        return PROTOCOL_FEE;
    }

    function claimGracePeriod() external pure returns (uint256) {
        return CLAIM_GRACE_PERIOD;
    }

    function supportedAssets() external view returns (address[SUPPORTED_ASSETS_COUNT] memory) {
        return _supportedAssets;
    }

    function hasDeposited(address account, uint256 tokenId) external view returns (bool) {
        return _deposited[account][tokenId];
    }

    function nextTokenId() external view returns (uint256) {
        return _counter;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         OVERRIDES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function uri(uint256) public pure override returns (string memory) {
        return "";
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _removeParticipant(IPasanaku.RotatingSavings storage rs, address account, uint256 tokenId) internal {
        uint256 len = rs.participants.length;
        uint256 idx = type(uint256).max;
        for (uint256 i; i < len;) {
            if (rs.participants[i] == account) {
                idx = i;
                break;
            }
            unchecked {
                ++i;
            }
        }
        if (idx == type(uint256).max) revert Pasanaku__CannotLeaveLobby();

        uint256 lk = _lockedCollateral[account][tokenId];
        if (lk > 0) {
            _lockedCollateral[account][tokenId] = 0;
            unchecked {
                _freeCollateral[account][rs.asset] += lk;
            }
        }
        if (idx != len - 1) {
            rs.participants[idx] = rs.participants[len - 1];
        }
        rs.participants.pop();
        _burn(account, tokenId, TOKEN_AMOUNT);
    }

    function _shuffleParticipantsMemory(address[] memory shuffled) internal view returns (address[] memory) {
        uint256 len = shuffled.length;
        if (len <= 1) return shuffled;

        uint256 _randomNumber = block.prevrandao;
        for (uint256 i = 0; i < len; i++) {
            uint256 n = i + (_randomNumber % (len - i));
            if (i != n) {
                address temp = shuffled[n];
                shuffled[n] = shuffled[i];
                shuffled[i] = temp;
            }
        }
        return shuffled;
    }

    function _applyRound(IPasanaku.RotatingSavings storage rs, address destination, bool isClaim) internal {
        uint256 amountToPay = rs.totalDeposited;
        uint256 currentIndex = rs.currentIndex;
        address asset = rs.asset;

        _ensureUnderlyingLiquidity(asset, amountToPay);
        unchecked {
            _activeRoundPools[asset] -= amountToPay;
        }

        rs.lastUpdatedAt = block.timestamp;
        unchecked {
            rs.currentIndex = currentIndex + 1;
        }
        rs.totalDeposited = 0;
        rs.ended = rs.currentIndex >= rs.participants.length;

        SafeTransferLib.safeTransfer(asset, destination, amountToPay);

        if (rs.ended) {
            emit Ended(rs.tokenId, block.timestamp);
            _releaseAllLockedCollateral(rs);
        }

        if (isClaim) {
            emit Claimed(destination, rs.tokenId, currentIndex, amountToPay, rs.totalDeposited);
        } else {
            emit Skipped(destination, rs.tokenId, currentIndex, amountToPay);
        }
    }

    function _releaseAllLockedCollateral(IPasanaku.RotatingSavings storage rs) internal {
        uint256 tid = rs.tokenId;
        address ast = rs.asset;
        uint256 n = rs.participants.length;
        for (uint256 i; i < n;) {
            address p = rs.participants[i];
            uint256 lk = _lockedCollateral[p][tid];
            if (lk > 0) {
                _lockedCollateral[p][tid] = 0;
                unchecked {
                    _freeCollateral[p][ast] += lk;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    function _ensureUnderlyingLiquidity(address asset, uint256 amount) internal view {
        if (_collateralReserves[asset] < amount) revert Pasanaku__InsufficientFreeCollateral();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  INTERNAL VIEW FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _isSupportedAsset(address asset) internal view returns (bool) {
        for (uint256 i; i < SUPPORTED_ASSETS_COUNT;) {
            if (_supportedAssets[i] == asset) return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }

    function _isParticipant(address participant, address[] storage participants) internal view returns (bool) {
        for (uint256 i; i < participants.length;) {
            if (participants[i] == participant) return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }

    function _gameExists(uint256 tokenId) internal view returns (bool) {
        return _rotatingSavings[tokenId].creator != address(0);
    }

    function _roundReady(IPasanaku.RotatingSavings storage rs) internal view returns (bool) {
        uint256 len = rs.participants.length;
        if (len < MIN_PARTICIPANTS_COUNT) return false;
        uint256 minAmountToClaim = rs.amount * (len - 1);
        return rs.totalDeposited >= minAmountToClaim;
    }

    function _canDeposit(address participant, uint256 tokenId) internal view returns (bool) {
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (rs.ended || rs.cancelled || !rs.started) return false;

        return (_gameExists(tokenId) && _isParticipant(participant, rs.participants)
                && participant != rs.participants[rs.currentIndex] && !_deposited[participant][tokenId]);
    }

    function _canClaimAny(address caller, uint256 tokenId) internal view returns (bool) {
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (!_gameExists(tokenId) || rs.ended || rs.cancelled || !rs.started) return false;
        if (!_roundReady(rs)) return false;

        address ben = rs.participants[rs.currentIndex];
        if (caller == ben) return true;
        return block.timestamp - rs.lastUpdatedAt >= CLAIM_GRACE_PERIOD;
    }

    function _canSkip(address caller, uint256 tokenId, address destination) internal view returns (bool) {
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (!_roundReady(rs)) return false;

        address ben = rs.participants[rs.currentIndex];
        if (destination != ben) return false;
        if (caller == ben) return true;
        return block.timestamp - rs.lastUpdatedAt >= CLAIM_GRACE_PERIOD;
    }

    receive() external payable {}
}
