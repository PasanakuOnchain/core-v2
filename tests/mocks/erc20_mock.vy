# pragma version ~=0.4.3
# pragma nonreentrancy off


from ethereum.ercs import IERC20
implements: IERC20


from ethereum.ercs import IERC20Detailed
implements: IERC20Detailed


from snekmate.tokens.interfaces import IERC20Permit
implements: IERC20Permit


from snekmate.utils.interfaces import IERC5267
implements: IERC5267


from snekmate.auth import ownable as ow
initializes: ow


from snekmate.tokens import erc20
initializes: erc20[ownable := ow]
exports: (
    erc20.owner,
    erc20.eip712Domain,
    erc20.transfer,
    erc20.approve,
    erc20.transferFrom,
    erc20.burn,
    erc20.burn_from,
    erc20.set_minter,
    erc20.permit,
    erc20.DOMAIN_SEPARATOR,
    erc20.transfer_ownership,
    erc20.renounce_ownership,
    erc20.name,
    erc20.symbol,
    erc20.decimals,
    erc20.balanceOf,
    erc20.allowance,
    erc20.totalSupply,
    erc20.is_minter,
    erc20.nonces
)


isMintableOrBurnable: public(constant(bool)) = True
initialSupply: public(uint256)


@deploy
@payable
def __init__(
    name_: String[25],
    symbol_: String[5],
    decimals_: uint8,
    initial_supply_: uint256,
    name_eip712_: String[50],
    version_eip712_: String[20],
):
    ow.__init__()
    erc20.__init__(name_, symbol_, decimals_, name_eip712_, version_eip712_)
    erc20._mint(msg.sender, initial_supply_ * 10**convert(decimals_, uint256))
    self.initialSupply = erc20.totalSupply


@external
def mint(to: address, amount: uint256) -> bool:
    erc20._mint(to, amount)
    return True


@external
def burnFrom(owner: address, amount: uint256):
    """
    @dev Destroys `amount` tokens from `owner`,
         deducting from the caller's allowance.
    @notice Note that `owner` cannot be the
            zero address. Also, the caller must
            have an allowance for `owner`'s tokens
            of at least `amount`.
    @param owner The 20-byte owner address.
    @param amount The 32-byte token amount to be destroyed.
    """
    erc20._spend_allowance(owner, msg.sender, amount)
    erc20._burn(owner, amount)
