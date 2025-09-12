import 'dotenv/config';
import axios from 'axios';
import { ethers } from 'ethers';

const RPC_URL = process.env.RPC_URL!;
const PK = process.env.ORACLE_PRIVATE_KEY!;
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS!;
const REG_API = process.env.REGISTRAR_API_URL!;
const REG_TOKEN = process.env.REGISTRAR_API_TOKEN!;
const START_BLOCK = Number(process.env.START_BLOCK ?? 0);

if (!RPC_URL || !PK || !CONTRACT_ADDRESS || !REG_API) {
  console.error('Missing env vars');
  process.exit(1);
}

const ABI = [
  "event Triggered(bytes32 indexed tradeId)",
  "function stateOf(bytes32) view returns (uint8)",
  "function getTrade(bytes32) view returns (tuple(address seller,address buyer,bytes32 securityId,uint256 qty,bytes32 currencyCode,uint256 amount,uint256 deadline,uint8 state,bytes32 sellerProofHash,bytes32 buyerProofHash,address sellerAttestor,address buyerAttestor,bytes32 externalRegId,uint64 createdAt,uint64 readyAt,uint64 triggeredAt,uint64 registeredAt))",
  "function confirmRegistration(bytes32 tradeId, bytes32 externalRegId)",
  "function reject(bytes32 tradeId, string reason)"
];

type Trade = {
  seller: string;
  buyer: string;
  securityId: string;
  qty: bigint;
  currencyCode: string;
  amount: bigint;
  deadline: bigint;
  state: number;
  sellerProofHash: string;
  buyerProofHash: string;
  sellerAttestor: string;
  buyerAttestor: string;
  externalRegId: string;
  createdAt: bigint;
  readyAt: bigint;
  triggeredAt: bigint;
  registeredAt: bigint;
};

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PK, provider);
  const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, wallet);

  const current = await provider.getBlockNumber();
  const fromBlock = Math.max(START_BLOCK, current - 50000);
  const past = await contract.queryFilter(contract.filters.Triggered(), fromBlock, current);
  for (const ev of past) {
    const tradeId: string = (ev as any).args?.tradeId as string;
    await handleTriggered(contract, tradeId);
  }

  contract.on('Triggered', async (tradeId: string) => {
    try {
      await handleTriggered(contract, tradeId);
    } catch (e) {
      console.error('Triggered handler error', e);
    }
  });

  console.log('Worker running. Listening for Triggered events...');
}

async function handleTriggered(contract: any, tradeId: string) {
  const state: number = await contract.stateOf(tradeId);
  if (state !== 2) { // 2 = Triggered
    return;
  }

  const t = await contract.getTrade(tradeId) as Trade;

  const payload = {
    tradeId,
    seller: t.seller,
    buyer: t.buyer,
    securityId: t.securityId,
    qty: t.qty.toString(),
    currencyCode: t.currencyCode,
    amount: t.amount.toString(),
    triggeredAt: Number(t.triggeredAt)
  };

  try {
    const resp = await axios.post(`${REG_API}/register`, payload, {
      headers: { Authorization: `Bearer ${REG_TOKEN}` }
    });
    const externalRegIdHex: string = resp.data?.externalRegIdHex || ethers.hexlify(ethers.randomBytes(32));
    const tx = await contract.confirmRegistration(tradeId, externalRegIdHex);
    await tx.wait();
    console.log('Confirmed registration', tradeId, externalRegIdHex);
  } catch (err: any) {
    console.error('Registrar error -> reject', err?.response?.data || err?.message);
    const reason = String(err?.response?.data?.error || err?.message || 'registrar_failed').slice(0, 200);
    const tx = await contract.reject(tradeId, reason);
    await tx.wait();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
