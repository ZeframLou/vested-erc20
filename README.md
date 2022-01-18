# VestedERC20

A wrapper ERC20 token that linearly vests an underlying ERC20 token to its holders.

It's not really suited for trading, but it is a useful tool for plugging vesting into other primitives. One example is [Astrodrop](https://astrodrop.xyz), which is a tool for airdropping ERC20 tokens and more. Combining VestedERC20 with Astrodrop, one can airdrop vested tokens to arbitrarily many people for a constant cost.

## Installation

To install with [DappTools](https://github.com/dapphub/dapptools):

```
dapp install zeframlou/vested-erc20
```

To install with [Foundry](https://github.com/gakonst/foundry):

```
forge install zeframlou/vested-erc20
```

## Local development

VestedERC20 uses [Foundry](https://github.com/gakonst/foundry) as the development framework.

### Dependencies

```
make update
```

### Compilation

```
make build
```

### Testing

```
make test
```
