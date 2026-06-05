# pragma version ~=0.4.3
"""
@title noop_contract
@custom:contract-name noop_contract
@notice Empty contract with no IERC1155 receiver — used to test _mint vs _safe_mint.
"""


@deploy
def __init__():
    pass
