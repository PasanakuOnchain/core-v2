import boa


def mint_token(owner, token, to, whole_amount: int) -> int:
    raw = int(whole_amount * 10 ** token.decimals())
    with boa.env.prank(owner):
        token.mint(to, raw)
    return raw
