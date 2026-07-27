import boa

from src import Pasanaku as pasanaku

# Compile-time protocol constants from Titanoboa (no deploy required).
_c = pasanaku._constants

DAYS_3 = _c._3_DAYS
DAYS_7 = _c._7_DAYS
DAYS_40 = _c._40_DAYS
PARTICIPANT_COUNT = _c._MIN_PARTICIPANT_COUNT
PARTICIPANT_COUNTS = (_c._MIN_PARTICIPANT_COUNT, _c._MAX_PARTICIPANT_COUNT)
TOKEN_AMOUNT = _c._TOKEN_AMOUNT
MISS_PENALTY_BPS = _c._MISS_PENALTY_BPS
BPS_PRECISION = _c._BPS_PRECISION
MAX_YIELD_FEE = _c._MAX_YIELD_FEE
MAX_FEE = _c._MAX_FEE

# Test-only fixtures (not Vyper constants).
PASANAKU_AMOUNT_RAW = 100 * 10**6
MAINNET_USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
MAINNET_FLUID_FUSDC = "0x9Fb7b4477576Fe5B32be4C1843aFB1e55F251B33"

URI_NOT_CREATED = "ipfs://QmbcELYwEiVu6n6nJhHmdqTRPfWD6eNHiXZhixKvhjAznF"
URI_ENDED = "ipfs://QmYA1EK6dEujhcdZMWbjk1gVoHyqEYDZoptHMzL8ppTfWH"
URI_ONGOING = "ipfs://QmYvMoHxQSPLbCaofRHEyskb7U5UEyq31gwH9pyM1WSEc4"
URI_STALE = "ipfs://QmcGBA3PSwZxq6RQQsWbUe4NNtbLCbaxuVpx1Jnv5qRF98"
URI_PENDING = "ipfs://QmZ9PeXU9sUbax7SPAbyoBZawNqCrdgtEYXdipzMYi4Rsp"
