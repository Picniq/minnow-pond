# Minnow Pond

_This application is still a work in progress._

Minnow Pond is a solution that allows users to pool funds together to perform one large group swap, thereby sharing the gas costs of the swap across many users. It is designed to pool money on a layer two solution such as Arbitrum where fees are cheaper and perform the group swap on mainnet. The solution can also be used purely on mainnet for a smaller cost savings.

Transferring standard ERC20 tokens costs less than 1/3 of the gas cost of a Uniswap swap. Used entirely on Ethereum mainnet, this solution could save approximately 40% on gas fees. Pooling funds on a cheaper EVM alternative such as Polygon or Arbitrum could save up to 65% of gas costs.

It is also possible to sell the acquired tokens directly from this contract, so the user is not required to hold the tokens in their wallet at any point in time.

This solution has some drawbacks:

- It is designed for small purchases (up to 1 ETH normally). If swapping more than that, you are probably better off making the swap directly yourself.
- Because these swaps are predictable in nature, they can be front-ran (to a small degree). To mitigate this, periods generally close after 1-2 ETH has been deposited. Using this solution for highly illiquid coins would increase this risk.
- Users must wait for others to join their pools. It could be possible that a trade will not close for a few hours. Tiny volume coins (under 1 ETH volume per day) may take a while to close. Users are able to withdraw their funds for open periods, so funds will never be stuck.

## Run and test

This project uses Yarn and Hardhat. Ensure Yarn is installed globally, then install project dependencies:

```bash
yarn
```

Run the deploy script on a fork of mainnet:

```bash
yarn deploy
```