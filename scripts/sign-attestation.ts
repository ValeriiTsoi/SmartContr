#!/usr/bin/env ts-node
import 'dotenv/config';
import { ethers } from 'ethers';
import fs from 'fs';

const RPC_URL = process.env.RPC_URL || 'http://localhost:8545';
const PK = process.env.PRIVATE_KEY!; // attestor key
const CONTRACT = process.env.CONTRACT_ADDRESS!;

if (!PK || !CONTRACT) {
  console.error('Set PRIVATE_KEY and CONTRACT_ADDRESS env vars');
  process.exit(1);
}

async function main() {
  const file = process.argv[2];
  if (!file) throw new Error('Usage: sign-attestation.ts <attestation.json>');
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PK, provider);
  const net = await provider.getNetwork();

  const domain = {
    name: 'DvP',
    version: '1',
    chainId: Number(net.chainId),
    verifyingContract: CONTRACT,
  };

  const types = {
    Attestation: [
      { name: 'tradeId', type: 'bytes32' },
      { name: 'securityId', type: 'bytes32' },
      { name: 'qty', type: 'uint256' },
      { name: 'currencyCode', type: 'bytes32' },
      { name: 'amount', type: 'uint256' },
      { name: 'expiry', type: 'uint256' },
      { name: 'party', type: 'uint8' },
      { name: 'nonce', type: 'uint256' }
    ]
  } as const;

  const message = {
    tradeId: raw.tradeId,
    securityId: raw.securityId,
    qty: BigInt(raw.qty),
    currencyCode: raw.currencyCode,
    amount: BigInt(raw.amount),
    expiry: BigInt(raw.expiry),
    party: raw.party,
    nonce: BigInt(raw.nonce)
  };

  const sig = await (wallet as any).signTypedData(domain, types as any, message);
  raw.signature = sig;
  const out = file.replace(/\.json$/, '.signed.json');
  fs.writeFileSync(out, JSON.stringify(raw, null, 2));
  console.log('Signed →', out);
}

main().catch((e) => { console.error(e); process.exit(1); });
