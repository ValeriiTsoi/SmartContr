// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title DvP (Variant B): Off-chain balances with on-chain attestation checks and external registrar callback
contract DvP is AccessControl, EIP712, ReentrancyGuard {
    using ECDSA for bytes32;

    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant ATTESTOR_ROLE = keccak256("ATTESTOR_ROLE");

    enum State { Draft, Ready, Triggered, Registered, Settled, Rejected, Expired, Canceled }

    struct Trade {
        address seller;
        address buyer;
        bytes32 securityId;
        uint256 qty;
        bytes32 currencyCode;
        uint256 amount;
        uint256 deadline;
        State state;
        bytes32 sellerProofHash;
        bytes32 buyerProofHash;
        address sellerAttestor;
        address buyerAttestor;
        bytes32 externalRegId;
        uint64 createdAt;
        uint64 readyAt;
        uint64 triggeredAt;
        uint64 registeredAt;
    }

    struct Attestation {
        bytes32 tradeId;
        bytes32 securityId;
        uint256 qty;
        bytes32 currencyCode;
        uint256 amount;
        uint256 expiry;
        uint8   party; // 0 seller, 1 buyer
        uint256 nonce;
    }

    bytes32 public constant ATTESTATION_TYPEHASH = keccak256(
        "Attestation(bytes32 tradeId,bytes32 securityId,uint256 qty,bytes32 currencyCode,uint256 amount,uint256 expiry,uint8 party,uint256 nonce)"
    );

    mapping(bytes32 => Trade) private _trades;
    mapping(bytes32 => bool) public tradeExists;
    mapping(bytes32 => bool) public usedAttestationDigest;
    uint256 private _tradeNonce;
    mapping(bytes32 => uint8) private _cancelVotes;

    event DealCreated(
        bytes32 indexed tradeId,
        address indexed buyer,
        address indexed seller,
        bytes32 securityId,
        uint256 qty,
        bytes32 currencyCode,
        uint256 amount,
        uint256 deadline
    );
    event ProofsAccepted(bytes32 indexed tradeId);
    event Triggered(bytes32 indexed tradeId);
    event Registered(bytes32 indexed tradeId, bytes32 externalRegId);
    event Settled(bytes32 indexed tradeId);
    event Rejected(bytes32 indexed tradeId, string reason);
    event Canceled(bytes32 indexed tradeId);
    event Expired(bytes32 indexed tradeId);

    constructor(address admin) EIP712("DvP", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function stateOf(bytes32 tradeId) external view returns (State) {
        return _trades[tradeId].state;
    }

    function getTrade(bytes32 tradeId) external view returns (Trade memory) {
        require(tradeExists[tradeId], "trade not found");
        return _trades[tradeId];
    }

    function attestationDigest(Attestation calldata a) external view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            ATTESTATION_TYPEHASH,
            a.tradeId,
            a.securityId,
            a.qty,
            a.currencyCode,
            a.amount,
            a.expiry,
            a.party,
            a.nonce
        ));
        return _hashTypedDataV4(structHash);
    }

    function proposeTrade(
        address seller,
        address buyer,
        bytes32 securityId,
        uint256 qty,
        bytes32 currencyCode,
        uint256 amount,
        uint256 deadline
    ) external returns (bytes32 tradeId) {
        require(buyer != address(0) && seller != address(0), "zero party");
        require(msg.sender == buyer || msg.sender == seller, "not party");
        require(qty > 0 && amount > 0, "qty/amount=0");
        require(deadline > block.timestamp, "bad deadline");

        tradeId = keccak256(abi.encodePacked(
            block.chainid,
            address(this),
            _tradeNonce++,
            seller,
            buyer,
            securityId,
            qty,
            currencyCode,
            amount,
            deadline
        ));
        require(!tradeExists[tradeId], "id clash");

        Trade storage t = _trades[tradeId];
        t.seller = seller;
        t.buyer = buyer;
        t.securityId = securityId;
        t.qty = qty;
        t.currencyCode = currencyCode;
        t.amount = amount;
        t.deadline = deadline;
        t.state = State.Draft;
        t.createdAt = uint64(block.timestamp);
        tradeExists[tradeId] = true;

        emit DealCreated(tradeId, buyer, seller, securityId, qty, currencyCode, amount, deadline);
    }

    function submitProofs(
        Attestation calldata sellerAtt,
        bytes calldata sellerSig,
        Attestation calldata buyerAtt,
        bytes calldata buyerSig
    ) external nonReentrant {
        require(tradeExists[sellerAtt.tradeId] && sellerAtt.tradeId == buyerAtt.tradeId, "trade mismatch");
        bytes32 tradeId = sellerAtt.tradeId;
        Trade storage t = _trades[tradeId];
        require(t.state == State.Draft, "bad state");
        require(block.timestamp <= t.deadline, "past deadline");

        require(sellerAtt.party == 0 && buyerAtt.party == 1, "party flags");

        require(sellerAtt.securityId == t.securityId && buyerAtt.securityId == t.securityId, "secId");
        require(sellerAtt.qty >= t.qty, "qty<req");
        require(buyerAtt.amount >= t.amount, "amt<req");
        require(sellerAtt.currencyCode == t.currencyCode && buyerAtt.currencyCode == t.currencyCode, "ccy");
        require(sellerAtt.expiry >= block.timestamp && buyerAtt.expiry >= block.timestamp, "att expired");

        bytes32 sDigest = _attDigest(sellerAtt);
        bytes32 bDigest = _attDigest(buyerAtt);
        address sSigner = ECDSA.recover(sDigest, sellerSig);
        address bSigner = ECDSA.recover(bDigest, buyerSig);

        require(hasRole(ATTESTOR_ROLE, sSigner), "seller attestor");
        require(hasRole(ATTESTOR_ROLE, bSigner), "buyer attestor");

        require(!usedAttestationDigest[sDigest] && !usedAttestationDigest[bDigest], "replay");
        usedAttestationDigest[sDigest] = true;
        usedAttestationDigest[bDigest]  = true;

        t.sellerProofHash = _attStructHash(sellerAtt);
        t.buyerProofHash  = _attStructHash(buyerAtt);
        t.sellerAttestor  = sSigner;
        t.buyerAttestor   = bSigner;
        t.state           = State.Ready;
        t.readyAt         = uint64(block.timestamp);

        emit ProofsAccepted(tradeId);
    }

    function trigger(bytes32 tradeId) external {
        require(tradeExists[tradeId], "not found");
        Trade storage t = _trades[tradeId];
        require(t.state == State.Ready, "bad state");
        require(msg.sender == t.buyer || msg.sender == t.seller, "not party");
        t.state = State.Triggered;
        t.triggeredAt = uint64(block.timestamp);
        emit Triggered(tradeId);
    }

    function confirmRegistration(bytes32 tradeId, bytes32 externalRegId) external onlyRole(ORACLE_ROLE) {
        require(tradeExists[tradeId], "not found");
        Trade storage t = _trades[tradeId];
        require(t.state == State.Triggered, "bad state");
        t.externalRegId = externalRegId;
        t.registeredAt = uint64(block.timestamp);
        t.state = State.Registered;
        emit Registered(tradeId, externalRegId);
        t.state = State.Settled;
        emit Settled(tradeId);
    }

    function reject(bytes32 tradeId, string calldata reason) external onlyRole(ORACLE_ROLE) {
        require(tradeExists[tradeId], "not found");
        Trade storage t = _trades[tradeId];
        require(t.state == State.Triggered, "bad state");
        t.state = State.Rejected;
        emit Rejected(tradeId, reason);
    }

    function cancel(bytes32 tradeId) external {
        require(tradeExists[tradeId], "not found");
        Trade storage t = _trades[tradeId];
        require(t.state == State.Draft || t.state == State.Ready, "bad state");
        uint8 bit = msg.sender == t.seller ? 1 : (msg.sender == t.buyer ? 2 : 0);
        require(bit != 0, "not party");
        uint8 m = _cancelVotes[tradeId] | bit;
        _cancelVotes[tradeId] = m;
        if (m == 3) {
            t.state = State.Canceled;
            emit Canceled(tradeId);
        }
    }

    function expire(bytes32 tradeId) external {
        require(tradeExists[tradeId], "not found");
        Trade storage t = _trades[tradeId];
        require(t.state == State.Draft || t.state == State.Ready, "bad state");
        require(block.timestamp > t.deadline, "not due");
        t.state = State.Expired;
        emit Expired(tradeId);
    }

    function addAttestor(address a) external onlyRole(DEFAULT_ADMIN_ROLE) { _grantRole(ATTESTOR_ROLE, a); }
    function removeAttestor(address a) external onlyRole(DEFAULT_ADMIN_ROLE) { _revokeRole(ATTESTOR_ROLE, a); }
    function addOracle(address a) external onlyRole(DEFAULT_ADMIN_ROLE) { _grantRole(ORACLE_ROLE, a); }
    function removeOracle(address a) external onlyRole(DEFAULT_ADMIN_ROLE) { _revokeRole(ORACLE_ROLE, a); }

    function _attStructHash(Attestation calldata a) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            ATTESTATION_TYPEHASH,
            a.tradeId,
            a.securityId,
            a.qty,
            a.currencyCode,
            a.amount,
            a.expiry,
            a.party,
            a.nonce
        ));
    }

    function _attDigest(Attestation calldata a) internal view returns (bytes32) {
        return _hashTypedDataV4(_attStructHash(a));
    }
}
