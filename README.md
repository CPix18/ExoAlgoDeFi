# DeFi Valuecoin Project Built With Foundry
1. The purpose it to build a Unit of Exchange that will hold its purchasing value for grocery items over time. Using Ethereum, smart contracts, exogeneous collateral, algorithms, and game theory I plan to create the solution for everyday people facing inflation at the grocery store.


## What kind of Valuecoin?
1. Relatively Stable in regards to purchasing power of time
2. Stability Mechanism - Minting/Burning
   1. Algorithmic
   2. Over-collateralized
3. Collateral - Exogenous (ETH/BTC/GOLD), Grocery Inventory Index
4. Governance - Game Theory, Monetary Incentives



## Components
1. Main Contracts
   1. Stablecoin
   2. Engine
   3. Treasury Smart Contract Wallet
2. Test Contracts
   1. Unit
      1. StableCoin
      2. Engine
      3. Smart Contract Wallet
      4. Oracle
   2. Mocks
      1. ERC20
      2. FailedMint
      3. FailedTransfer
      4. FailedTransferFrom
      5. MoreDebtThanCollateral
      6. V3Aggregator (Chainlink)
   3. Fuzz
      1. ContinueOnRevert
      2. FailOnRevert
3. Scripts
   1. HelperConfig
   2. DeployStableCoin
4. PriceFeed
   1. Oracle from Chainlink
5. Foundry.toml
   1. remappings
   2. block explorers
   3. rpc_endpoints


## Build Notes
1. Main Contracts - Coin and Engine
   1. Start with Valuecoin contract 
      1. burnable (minting process), and ownable (by the engine)
         1. part of script needs to be transferring ownership to engine
   2. From the engine, people are going to deposit collateral, mint coin, redeem collateral, burn coin, liquidate
      1. to move tokens use "bool success = IERC20(tokenAddress).transfer(msg.sender, tokenAmount)"
         1. use transfer when going from another contract that isn't you
         2. transferFrom is when its going from your wallet
   3. Checks, Effects, Interactions mental model for functions

2. Build deploy script first then realize need HelperConfig for network (constructor) args and contract address details (struct)
   1. scripts use function run() public view returns
   2. scripts import script from forge

3. HelperConfig is where all deployable networks, collateral tokens, and chainlink price feeds belong.
   1. for networks use if else statement with block.chainid
   2. use chainlink data feeds or v3aggregator interface with mockerc20 for token and pricefeed addresses

4. Internal functions allow calls to be made from anybody
   1. examples were from the liquidate function which called burn and redeem functions which needed to be moved to internal and variables shifted from msg.sender to "from" and "to"
   2. still kept the public functions but utlized the internal function logic

5. 


## Testing Notes
1. Import Test, console2, StdCheats, deploy scripts, main contracts, mock files
2. Mocks need to match the files in the lib folder
3. function setUp() external
   1. Got to start with deploying the script and setting up the "environment" to test
      1. vm.deal, vm.prank, vm.hoax

4. Could be a good idea to write unit tests before scripts and then right integration tests while you write scripts

5. Unit testing each one of the functions from engine contract
   1. Constructor tests, price tests, public function tests, view and pure function tests

6. Mock testing the mintable coin - transfer, mint, transferFrom, price fluctuations, and priceFeed
   
7. Use modifiers with unique names, not a function name from another contract
   1. modifiers can be used in numerous tests to keep from doing redundant work. for example pranking user with funds and approving a token

8. 




## Deployment Notes
1. Makefile setup for each deployable network
   1. use .env to advantage

2. Check out HelperConfig to make sure the right networks and configs are setup 


3. make deploy-base ARGS="--network base-sepolia"
   1. deployment on base testnet using makerfile setup


4. make sure to create .env file and source .env afterward to save

5. basescan api may be different than etherscan api


## Additional Code/Features
1. Treasury Address
   1. Simple Smart Contract Wallet
   2. Deployed during script with the other contracts
   3. Owned by private key used to deploy but would like to transfer ownership to SVCEngine and add functions to interact with it through the engine
   4. Treasury Fee could be implemented in some cool ways during liquidate function on SVCEngine
2. NFTs to represent healthFactor
   1. better the health factor, the cooler the NFT
3. 