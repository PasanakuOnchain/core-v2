// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {ERC1155} from "solady/tokens/ERC1155.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IPasanaku} from "./interfaces/IPasanaku.sol";

/// @title Pasanaku - Rotating savings decentralized protocol
/// @author Rafael Abuawad <x.com/rabuawad_>
/// @notice This code is for testing purposes only, is not production ready and is not audited.
///         Everything is subject to change. Use at your own risk.
contract Pasanaku is ERC1155, Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error Pasanaku__InsufficientFee();
    error Pasanaku__UnsupportedAsset();
    error Pasanaku__NoParticipants();
    error Pasanaku__TooManyParticipants();
    error Pasanaku__CannotDeposit();
    error Pasanaku__CannotClaim();
    error Pasanaku__CannotRecover();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 private constant PROTOCOL_FEE = 0; // TODO: set protocol fee
    uint256 private constant TOKEN_AMOUNT = 1;
    uint256 private constant MAX_PARTICIPANTS_COUNT = 12;
    uint256 private constant DAYS_30 = 60 * 60 * 24 * 30;
    uint256 private constant SUPPORTED_ASSETS_COUNT = 9;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event RotatingSavingsCreated(
        address[] participants,
        address indexed asset,
        uint256 amount,
        uint256 indexed tokenId,
        address indexed creator,
        uint256 createdAt
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

    event Ended(
        uint256 indexed tokenId,
        uint256 lastUpdatedAt
    );

    event Recovered(
        address indexed participant,
        uint256 indexed tokenId,
        uint256 index,
        uint256 amount
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    mapping(uint256 => IPasanaku.RotatingSavings) private _rotatingSavings;
    mapping(address => mapping(uint256 => mapping(uint256 => bool))) private _deposited;
    uint256 private _counter;

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

    function create(address asset, address[] calldata participants, uint256 amount) external payable returns (bool) {
        if (msg.value < PROTOCOL_FEE) revert Pasanaku__InsufficientFee();
        if (!_isSupportedAsset(asset)) revert Pasanaku__UnsupportedAsset();
        if (participants.length == 0) revert Pasanaku__NoParticipants();
        if (participants.length > MAX_PARTICIPANTS_COUNT) revert Pasanaku__TooManyParticipants();

        uint256 tokenId = _counter;
        unchecked {
            _counter = tokenId + 1;
        }

        for (uint256 i; i < participants.length;) {
            _mint(participants[i], tokenId, TOKEN_AMOUNT, "");
            unchecked {
                ++i;
            }
        }

        uint256 timestamp = block.timestamp;
        _rotatingSavings[tokenId] = IPasanaku.RotatingSavings({
            participants: participants,
            asset: asset,
            amount: amount,
            currentIndex: 0,
            totalDeposited: 0,
            tokenId: tokenId,
            ended: false,
            recovered: false,
            creator: msg.sender,
            createdAt: timestamp,
            lastUpdatedAt: timestamp
        });

        emit RotatingSavingsCreated(participants, asset, amount, tokenId, msg.sender, timestamp);
        return true;
    }

    function deposit(uint256 tokenId) external payable returns (bool) {
        if (msg.value < PROTOCOL_FEE) revert Pasanaku__InsufficientFee();
        if (!_canDeposit(msg.sender, tokenId)) revert Pasanaku__CannotDeposit();

        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        uint256 currentIndex = rs.currentIndex;

        rs.lastUpdatedAt = block.timestamp;
        rs.totalDeposited += rs.amount;
        _deposited[msg.sender][tokenId][currentIndex] = true;

        SafeTransferLib.safeTransferFrom(rs.asset, msg.sender, address(this), rs.amount);

        emit Deposited(msg.sender, tokenId, currentIndex, rs.amount, rs.totalDeposited);
        return true;
    }

    function claim(uint256 tokenId) external payable returns (bool) {
        if (msg.value < PROTOCOL_FEE) revert Pasanaku__InsufficientFee();
        if (!_canClaim(msg.sender, tokenId)) revert Pasanaku__CannotClaim();

        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        uint256 amountToClaim = rs.totalDeposited;
        uint256 currentIndex = rs.currentIndex;

        rs.lastUpdatedAt = block.timestamp;
        unchecked {
            rs.currentIndex = currentIndex + 1;
        }
        rs.totalDeposited = 0;
        rs.ended = rs.currentIndex >= rs.participants.length;

        SafeTransferLib.safeTransfer(rs.asset, msg.sender, amountToClaim);

        if (rs.ended) {
            emit Ended(tokenId, block.timestamp);
        }
        emit Claimed(msg.sender, tokenId, currentIndex, amountToClaim, amountToClaim);
        return true;
    }

    function recover(uint256 tokenId) external returns (bool) {
        if (!_canRecover(msg.sender, tokenId)) revert Pasanaku__CannotRecover();

        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        uint256 currentIndex = rs.currentIndex;

        _burn(msg.sender, tokenId, TOKEN_AMOUNT);

        rs.totalDeposited -= rs.amount;
        rs.recovered = true;
        _deposited[msg.sender][tokenId][currentIndex] = false;

        SafeTransferLib.safeTransfer(rs.asset, msg.sender, rs.amount);

        emit Recovered(msg.sender, tokenId, currentIndex, rs.amount);
        return true;
    }

    function collectProtocolFees() external onlyOwner {
        SafeTransferLib.safeTransferAllETH(owner());
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
        uint256 depositsCount = _depositsCount(participant, rs);
        return rs.amount * (rs.participants.length - depositsCount);
    }

    function beneficiary(uint256 tokenId) external view returns (address) {
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (!rs.ended) {
            return rs.participants[rs.currentIndex];
        }
        return address(0);
    }

    function canClaim(address participant, uint256 tokenId) external view returns (bool) {
        return _canClaim(participant, tokenId);
    }

    function canDeposit(address participant, uint256 tokenId) external view returns (bool) {
        return _canDeposit(participant, tokenId);
    }

    function canRecover(address participant, uint256 tokenId) external view returns (bool) {
        return _canRecover(participant, tokenId);
    }

    function participantsCount(uint256 tokenId) external view returns (uint256) {
        return _rotatingSavings[tokenId].participants.length;
    }

    function protocolFee() external pure returns (uint256) {
        return PROTOCOL_FEE;
    }

    function supportedAssets() external view returns (address[SUPPORTED_ASSETS_COUNT] memory) {
        return _supportedAssets;
    }

    function hasDeposited(address account, uint256 tokenId, uint256 index) external view returns (bool) {
        return _deposited[account][tokenId][index];
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

    function _depositsCount(address participant, IPasanaku.RotatingSavings storage rs) internal view returns (uint256) {
        uint256 count = 0;
        for (uint256 i; i < rs.participants.length;) {
            if (rs.participants[i] == participant) {
                unchecked {
                    ++count;
                }
            }
            unchecked {
                ++i;
            }
        }
        return count;
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

    function _canDeposit(address participant, uint256 tokenId) internal view returns (bool) {
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (rs.ended) return false;

        return (
            _gameExists(tokenId)
            && _isParticipant(participant, rs.participants)
            && participant != rs.participants[rs.currentIndex]
            && !rs.ended
            && !rs.recovered
            && !_deposited[participant][tokenId][rs.currentIndex]
        );
    }

    function _canClaim(address participant, uint256 tokenId) internal view returns (bool) {
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (rs.ended) return false;

        uint256 benefactorDepositsCount = _depositsCount(participant, rs);
        uint256 lenParticipants = rs.participants.length;
        uint256 minAmountToClaim = rs.amount * (lenParticipants - benefactorDepositsCount);

        return (
            _gameExists(tokenId)
            && _isParticipant(participant, rs.participants)
            && participant == rs.participants[rs.currentIndex]
            && !rs.ended
            && !rs.recovered
            && rs.totalDeposited >= minAmountToClaim
        );
    }

    function _canRecover(address participant, uint256 tokenId) internal view returns (bool) {
        IPasanaku.RotatingSavings storage rs = _rotatingSavings[tokenId];
        if (rs.ended) return false;

        return (
            _gameExists(tokenId)
            && _isParticipant(participant, rs.participants)
            && participant != rs.participants[rs.currentIndex]
            && rs.totalDeposited > 0
            && _deposited[participant][tokenId][rs.currentIndex]
            && !rs.ended
            && block.timestamp - rs.lastUpdatedAt >= DAYS_30
        );
    }

    receive() external payable {}
}
