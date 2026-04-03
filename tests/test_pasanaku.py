def test_protocol_fee(pasanaku_contract):
    assert pasanaku_contract.protocolFee() == int(0.000075*10**18)
