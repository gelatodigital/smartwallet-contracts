## Deploy
1. export the deployer private key
   ```
   export PRIVATE_KEY=
   ```
2. add chain to `rpc_endpoints` [here](https://github.com/gelatodigital/smartwallet-contracts/blob/master/foundry.toml#L10)
3. run the deploy script
   ```
   forge script ./script/DeployDelegation.s.sol --rpc-url <CHAIN ADDED IN STEP #2> --broadcast
   ```
4. verify the contract
   ```
   forge verify-contract <ADDRESS> ./src/Delegation.sol:Delegation --chain-id <CHAIN_ID> --verifier <etherscan,blockscout> --verifier-url <VERIFIER_URL> --etherscan-api-key <API_KEY>
   ```
5. create a branch for the deployment with [broadcast logs](https://github.com/gelatodigital/smartwallet-contracts/tree/master/broadcast/DeployDelegation.s.sol) (e.g., [`chore/deploy-basecamp`](https://github.com/gelatodigital/smartwallet-contracts/pull/10))
