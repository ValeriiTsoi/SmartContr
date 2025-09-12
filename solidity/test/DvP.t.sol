// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {DvP} from "../contracts/DvP.sol";

contract DvPTest is Test {
    DvP dvp;

    address buyer = address(0xB0B);
    address seller = address(0xA11CE);

    uint256 SELLER_ATTESTOR_PK = 0xA11CE;
    uint256 BUYER_ATTESTOR_PK  = 0xB0B;
    uint256 ORACLE_PK          = 0xD00D;

    address sellerAttestor;
    address buyerAttestor;
    address oracle;

    function setUp() public {
        sellerAttestor = vm.addr(SELLER_ATTESTOR_PK);
        buyerAttestor  = vm.addr(BUYER_ATTESTOR_PK);
        oracle         = vm.addr(ORACLE_PK);

        dvp = new DvP(address(this));
        dvp.addAttestor(sellerAttestor);
        dvp.addAttestor(buyerAttestor);
        dvp.addOracle(oracle);
    }

    function _mkAtt(
        bytes32 tradeId,
        bytes32 securityId,
        uint256 qty,
        bytes32 currencyCode,
        uint256 amount,
        uint8 party,
        uint256 nonce,
        uint256 expiry
    ) internal pure returns (DvP.Attestation memory a) {
        a.tradeId = tradeId;
        a.securityId = securityId;
        a.qty = qty;
        a.currencyCode = currencyCode;
        a.amount = amount;
        a.expiry = expiry;
        a.party = party;
        a.nonce = nonce;
    }

    function test_FullHappyPath() public {
        bytes32 securityId = keccak256(abi.encodePacked("ISIN:TEST123"));
        bytes32 ccy = bytes32("EUR");
        vm.prank(buyer);
        bytes32 tradeId = dvp.proposeTrade(seller, buyer, securityId, 100, ccy, 1000 ether, block.timestamp + 7 days);

        DvP.Attestation memory sAtt = _mkAtt(tradeId, securityId, 100, ccy, 1000 ether, 0, 1, block.timestamp + 1 days);
        DvP.Attestation memory bAtt = _mkAtt(tradeId, securityId, 100, ccy, 1000 ether, 1, 2, block.timestamp + 1 days);

        bytes32 sDigest = dvp.attestationDigest(sAtt);
        bytes32 bDigest = dvp.attestationDigest(bAtt);

        (uint8 sv, bytes32 sr, bytes32 ss) = vm.sign(SELLER_ATTESTOR_PK, sDigest);
        bytes memory sSig = abi.encodePacked(sr, ss, sv);
        (uint8 bv, bytes32 br, bytes32 bs) = vm.sign(BUYER_ATTESTOR_PK, bDigest);
        bytes memory bSig = abi.encodePacked(br, bs, bv);

        dvp.submitProofs(sAtt, sSig, bAtt, bSig);
        assertEq(uint(dvp.stateOf(tradeId)), uint(DvP.State.Ready));

        vm.prank(buyer);
        dvp.trigger(tradeId);
        assertEq(uint(dvp.stateOf(tradeId)), uint(DvP.State.Triggered));

        vm.prank(oracle);
        dvp.confirmRegistration(tradeId, bytes32("REG123"));
        assertEq(uint(dvp.stateOf(tradeId)), uint(DvP.State.Settled));
    }

    function test_RevertOnExpiredAttestation() public {
        bytes32 securityId = keccak256(abi.encodePacked("ISIN:TEST123"));
        bytes32 ccy = bytes32("EUR");
        vm.prank(buyer);
        bytes32 tradeId = dvp.proposeTrade(seller, buyer, securityId, 10, ccy, 100 ether, block.timestamp + 7 days);

        DvP.Attestation memory sAtt = _mkAtt(tradeId, securityId, 10, ccy, 100 ether, 0, 1, block.timestamp - 1);
        DvP.Attestation memory bAtt = _mkAtt(tradeId, securityId, 10, ccy, 100 ether, 1, 2, block.timestamp + 1 days);

        bytes32 sDigest = dvp.attestationDigest(sAtt);
        bytes32 bDigest = dvp.attestationDigest(bAtt);
        (uint8 sv, bytes32 sr, bytes32 ss) = vm.sign(SELLER_ATTESTOR_PK, sDigest);
        bytes memory sSig = abi.encodePacked(sr, ss, sv);
        (uint8 bv, bytes32 br, bytes32 bs) = vm.sign(BUYER_ATTESTOR_PK, bDigest);
        bytes memory bSig = abi.encodePacked(br, bs, bv);

        vm.expectRevert("att expired");
        dvp.submitProofs(sAtt, sSig, bAtt, bSig);
    }

    function test_RevertOnUnauthorizedAttestor() public {
        bytes32 securityId = keccak256(abi.encodePacked("ISIN:TEST123"));
        bytes32 ccy = bytes32("EUR");
        vm.prank(buyer);
        bytes32 tradeId = dvp.proposeTrade(seller, buyer, securityId, 10, ccy, 100 ether, block.timestamp + 7 days);

        DvP.Attestation memory sAtt = _mkAtt(tradeId, securityId, 10, ccy, 100 ether, 0, 1, block.timestamp + 1 days);
        DvP.Attestation memory bAtt = _mkAtt(tradeId, securityId, 10, ccy, 100 ether, 1, 2, block.timestamp + 1 days);

        bytes32 sDigest = dvp.attestationDigest(sAtt);
        bytes32 bDigest = dvp.attestationDigest(bAtt);

        (uint8 sv, bytes32 sr, bytes32 ss) = vm.sign(SELLER_ATTESTOR_PK, sDigest);
        bytes memory sSig = abi.encodePacked(sr, ss, sv);
        (uint8 bv, bytes32 br, bytes32 bs) = vm.sign(0xDEAD, bDigest); // unauthorized
        bytes memory bSig = abi.encodePacked(br, bs, bv);

        vm.expectRevert("buyer attestor");
        dvp.submitProofs(sAtt, sSig, bAtt, bSig);
    }

    function test_Expire() public {
        bytes32 securityId = keccak256(abi.encodePacked("ISIN:TEST123"));
        bytes32 ccy = bytes32("EUR");
        vm.prank(buyer);
        bytes32 tradeId = dvp.proposeTrade(seller, buyer, securityId, 10, ccy, 100 ether, block.timestamp + 1);
        vm.warp(block.timestamp + 2);
        dvp.expire(tradeId);
        assertEq(uint(dvp.stateOf(tradeId)), uint(DvP.State.Expired));
    }
}
