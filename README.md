# DvP (Variant B) — Minimal Implementation Pack

This repo contains:
- Solidity contract `DvP.sol` with EIP-712 attestation checks (variant B: off-chain balances).
- Foundry tests.
- JSON Schemas for attestations.
- Off-chain worker (TypeScript) to call external registrar and confirm on-chain.
- Minimal Next.js web UI.
- GitHub Actions (CI + Release), Dockerfile, Helm chart, Terraform example.
- Example attestations and a script to sign them with EIP-712.

## Quick start

### Solidity (Foundry)
```bash
cd solidity
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2
forge build
forge test -vv
```

### Off-chain worker
```bash
cd offchain
npm i
cp .env.example .env  # fill in RPC_URL, ORACLE_PRIVATE_KEY, CONTRACT_ADDRESS, REGISTRAR_API_URL, REGISTRAR_API_TOKEN
npm start
```

### Web UI
```bash
cd webui
npm i
cp .env.local.example .env.local  # fill RPC and contract
npm run dev
```

### Release
Create a tag `vX.Y.Z` and push. GitHub Actions will build, test, export ABIs, generate TypeChain, and attach `dist/dvp-pack.tgz` to the GitHub Release.
Optional: GHCR Docker image for off-chain worker.

### Deploy (K8s)
- Build/push worker image to GHCR (or use workflow).
- Edit `terraform/terraform.tfvars`.
- `cd terraform && terraform init && terraform apply`.

### Attestations
Use `scripts/sign-attestation.ts` to sign EIP-712 payloads in `examples/attestations/*.json`.
