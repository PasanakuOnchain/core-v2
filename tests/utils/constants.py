import boa

from src import Pasanaku as pasanaku

# Compile-time protocol constants from Titanoboa (no deploy required).
_c = pasanaku._constants

DAYS_3 = _c._DAYS_3
DAYS_7 = _c._DAYS_7
_MIN_TIME_INTERVAL = _c._MIN_TIME_INTERVAL
PARTICIPANT_COUNT = _c._MIN_PARTICIPANT_COUNT
PARTICIPANT_COUNTS = (_c._MIN_PARTICIPANT_COUNT, _c._MAX_PARTICIPANT_COUNT)
TOKEN_AMOUNT = _c._TOKEN_AMOUNT
MISS_PENALTY_BPS = _c._MISS_PENALTY_BPS
BPS_PRECISION = _c._BPS_PRECISION
MAX_YIELD_FEE = _c._MAX_YIELD_FEE
MAX_FEE = _c._MAX_FEE

# Test-only fixtures (not Vyper constants).
PASANAKU_AMOUNT_RAW = 100 * 10**6
BASE_CHAIN_ID = 8453
BASE_USDC = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
BASE_FLUID_FUSDC = "0xf42f5795D9ac7e9D757dB633D693cD548Cfd9169"

URI_INVALID = "ipfs://bafybeicxb3jsthydawpjye7arof5cjtqflnmpe6o3dln6yoqpwbf7hnsxa/pasanaku-invalid.png"
URI_VALID = "ipfs://bafybeicxb3jsthydawpjye7arof5cjtqflnmpe6o3dln6yoqpwbf7hnsxa/pasanaku.png"
