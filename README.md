# Smart Wallet Contracts

This repository contains the smart contracts for the Gelato Smart Wallet.

## Prerequisites

Before you begin, ensure you have the following installed:
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/downloads)

If you want to deploy contracts, you also need to have:
- An EOA with sufficient funds for deployment on the target network
- Access to an RPC endpoint for your target network

## Deployment Guide

### 1. Environment Setup

1. Create a `.env` file in the root directory:
```bash
cp .env.example .env
```

2. Configure your environment variables in `.env`:
```bash
# Required for deployment
PRIVATE_KEY=your_private_key_here
RPC_URL=your_rpc_url_here

# Required for verification
ETHERSCAN_API_KEY=your_etherscan_api_key_here
```

3. Load the environment variables:
```bash
source .env
```

### 2. Network Configuration

Add your target chain's RPC endpoint to the `foundry.toml` configuration:
1. Open `foundry.toml`
2. Locate the `rpc_endpoints` section
3. Add your chain's RPC URL following the existing format.

### 3. Deploy Contracts

Run the deployment script using Forge:
```bash
forge script ./script/DeployDelegation.s.sol \
    --rpc-url $RPC_URL \
    --broadcast
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

### 5. Documentation

Create a new branch for the deployment documentation:
1. Create a branch named `deployment/<chainId>`. Make sure to include the name of the network in the title of the PR.
2. Include the broadcast logs from `broadcast/DeployDelegation.s.sol`
3. Submit a pull request with the deployment details

## Support

For questions or issues, please open an issue in this repository or contact the Gelato team.
