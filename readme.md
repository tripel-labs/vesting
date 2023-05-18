# Simple vesting contract using minimal proxies (ERC1167)

## Test
To run the tests, use the following command:

```bash
forge test
```

## Deployment
To deploy, run the following command:

```bash
forge create src/VestingFactory.sol:VestingFactory --rpc-url xxx --verify --etherscan-api-key xxx --private-key xxx
```

## Usage
Create a vesting stream by first approving the requested tokens to the factory and then calling the `createVestingSchedule` function on the factory.
