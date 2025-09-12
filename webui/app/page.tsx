'use client';
import { useMemo, useState } from 'react';
import { ethers } from 'ethers';

const ABI = [
  "function proposeTrade(address seller,address buyer,bytes32 securityId,uint256 qty,bytes32 currencyCode,uint256 amount,uint256 deadline) returns (bytes32)",
  "function submitProofs((bytes32,bytes32,uint256,bytes32,uint256,uint256,uint8,uint256),bytes,(bytes32,bytes32,uint256,bytes32,uint256,uint256,uint8,uint256),bytes)",
  "function trigger(bytes32 tradeId)",
  "function stateOf(bytes32) view returns (uint8)"
];

type Attestation = {
  tradeId: string; securityId: string; qty: string; currencyCode: string; amount: string;
  expiry: number; party: number; nonce: string; signature: string;
};

export default function Home() {
  const [status, setStatus] = useState<string>('');
  const [tradeId, setTradeId] = useState<string>('');

  const [seller, setSeller] = useState('');
  const [buyer, setBuyer] = useState('');
  const [securityId, setSecurityId] = useState('');
  const [qty, setQty] = useState('');
  const [ccyBytes32, setCcyBytes32] = useState('');
  const [amount, setAmount] = useState('');
  const [deadline, setDeadline] = useState('');

  const [sellerAtt, setSellerAtt] = useState<Attestation | null>(null);
  const [buyerAtt, setBuyerAtt] = useState<Attestation | null>(null);

  const provider = useMemo(() => new ethers.JsonRpcProvider(process.env.NEXT_PUBLIC_RPC_URL!), []);
  const contract = useMemo(() => {
    const addr = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!;
    const wallet = ethers.Wallet.createRandom().connect(provider);
    return new ethers.Contract(addr, ABI, wallet);
  }, [provider]);

  function strToBytes32(s: string) {
    const buf = new TextEncoder().encode(s);
    const arr = new Uint8Array(32);
    arr.set(buf.slice(0, 32));
    return '0x' + Buffer.from(arr).toString('hex');
  }

  async function onPropose() {
    try {
      const signer = await getSigner();
      const c = contract.connect(signer);
      const tx = await c.proposeTrade(
        seller, buyer, securityId, qty, ccyBytes32, amount, deadline
      );
      await tx.wait();
      setStatus('Trade proposed. Check events for tradeId.');
    } catch (e: any) {
      setStatus('Propose error: ' + (e?.message || e));
    }
  }

  async function onSubmitProofs() {
    if (!sellerAtt || !buyerAtt) { setStatus('Load both attestations first'); return; }
    try {
      const signer = await getSigner();
      const c = contract.connect(signer);

      const sTuple = [sellerAtt.tradeId, sellerAtt.securityId, sellerAtt.qty, sellerAtt.currencyCode, sellerAtt.amount, sellerAtt.expiry, sellerAtt.party, sellerAtt.nonce];
      const bTuple = [buyerAtt.tradeId, buyerAtt.securityId, buyerAtt.qty, buyerAtt.currencyCode, buyerAtt.amount, buyerAtt.expiry, buyerAtt.party, buyerAtt.nonce];

      const tx = await c.submitProofs(sTuple, sellerAtt.signature, bTuple, buyerAtt.signature);
      await tx.wait();
      setStatus('Proofs submitted. State should be Ready.');
    } catch (e: any) {
      setStatus('submitProofs error: ' + (e?.message || e));
    }
  }

  async function onTrigger() {
    try {
      const signer = await getSigner();
      const c = contract.connect(signer);
      const tx = await c.trigger(tradeId);
      await tx.wait();
      setStatus('Triggered. Worker will call registrar.');
    } catch (e: any) {
      setStatus('Trigger error: ' + (e?.message || e));
    }
  }

  async function getSigner(): Promise<ethers.Signer> {
    if (!(window as any).ethereum) throw new Error('No injected wallet');
    const p = new ethers.BrowserProvider((window as any).ethereum);
    await p.send('eth_requestAccounts', []);
    return await p.getSigner();
  }

  function onLoadFile(setter: (a: Attestation)=>void) {
    return async (e: React.ChangeEvent<HTMLInputElement>) => {
      const f = e.target.files?.[0];
      if (!f) return;
      const t = await f.text();
      const obj = JSON.parse(t);
      setter(obj as Attestation);
    };
  }

  return (
    <main style={{ maxWidth: 900, margin: '40px auto', padding: 16 }}>
      <h1>DvP — Minimal UI</h1>
      <p style={{ opacity: 0.7 }}>RPC: {process.env.NEXT_PUBLIC_RPC_URL}</p>

      <section style={{ border: '1px solid #eee', padding: 16, borderRadius: 12, marginBottom: 24 }}>
        <h2>Create Trade</h2>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <input placeholder="Seller 0x..." value={seller} onChange={e=>setSeller(e.target.value)} />
          <input placeholder="Buyer 0x..." value={buyer} onChange={e=>setBuyer(e.target.value)} />
          <input placeholder="SecurityId (0x... bytes32)" value={securityId} onChange={e=>setSecurityId(e.target.value)} />
          <input placeholder="Qty (uint256)" value={qty} onChange={e=>setQty(e.target.value)} />
          <div>
            <input placeholder="Currency (e.g., EUR)" onChange={e=>setCcyBytes32(strToBytes32(e.target.value))} />
            <small>bytes32: {ccyBytes32}</small>
          </div>
          <input placeholder="Amount (uint256)" value={amount} onChange={e=>setAmount(e.target.value)} />
          <input placeholder="Deadline (unix seconds)" value={deadline} onChange={e=>setDeadline(e.target.value)} />
        </div>
        <button onClick={onPropose} style={{ marginTop: 12 }}>Propose Trade</button>
      </section>

      <section style={{ border: '1px solid #eee', padding: 16, borderRadius: 12, marginBottom: 24 }}>
        <h2>Submit Attestations</h2>
        <div style={{ display: 'flex', gap: 16 }}>
          <div>
            <label>Seller attestation JSON</label><br />
            <input type="file" accept="application/json" onChange={onLoadFile((a)=>setSellerAtt(a))} />
          </div>
          <div>
            <label>Buyer attestation JSON</label><br />
            <input type="file" accept="application/json" onChange={onLoadFile((a)=>setBuyerAtt(a))} />
          </div>
        </div>
        <button onClick={onSubmitProofs} style={{ marginTop: 12 }}>Submit Proofs</button>
      </section>

      <section style={{ border: '1px solid #eee', padding: 16, borderRadius: 12 }}>
        <h2>Trigger Registrar Call</h2>
        <input placeholder="tradeId (0x... bytes32)" value={tradeId} onChange={e=>setTradeId(e.target.value)} />
        <button onClick={onTrigger} style={{ marginLeft: 12 }}>Trigger</button>
      </section>

      <p style={{ marginTop: 24 }}><b>Status:</b> {status}</p>
    </main>
  );
}
