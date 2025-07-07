# Smart Wallet Contracts

This repository contains the smart contracts for the Gelato Smart Wallet.

## Prerequisites

Before you begin, ensure you have the following installed:

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [pnpm](https://pnpm.io/installation)
- [Git](https://git-scm.com/downloads)

If you want to deploy contracts, you also need to have a `SPONSOR_API_KEY` which you can get [here](https://app.gelato.network/relay).

## Setup Guide

Periphery contracts in this repository rely on several external contracts which are added as submodules in this repo.

To install submodules:

```bash
chmod +x install-submodules.sh

./install-submodules.sh
```

To install packages:
```bash
pnpm install
```


## Deployment Guide

### 1. Environment Setup

1. Create a `.env` file in the root directory:

```bash
cp .env.example .env
```

2. Configure your environment variables in `.env`:

```bash
SPONSOR_API_KEY="" # https://app.gelato.network/relay
TARGET_ENV="" # either 'testnet' or 'mainnet'
```

3. Load the environment variables:

```bash
source .env
```

### 2. Network Configuration

Add your target chain to the `deploy/chains.ts` configuration:

1. Open `deploy/chains.ts`
2. Locate the `testnets` or `mainnets` section
3. Add your chain object following the existing format

The chain object can be imported from `viem/chains`. If the chain is not exported by viem you can add it manually. An example of this is `thriveTestnet` and `abcTestnet`.

### 3. Deploy Contracts

Run the deployment script:

```bash
pnpm run deploy
```

### 4. Verify Contracts

After deployment, verify your contract on the network's block explorer:

```bash
forge verify-contract <DEPLOYED_ADDRESS> \
    ./src/Delegation.sol:Delegation \
    --chain-id <CHAIN_ID> \
    --verifier <etherscan|blockscout> \
    --verifier-url <VERIFIER_URL> \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

## Support

For questions or issues, please open an issue in this repository or contact the Gelato team.
