# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# Update dependencies
install         :; forge install
update          :; forge update

# Build & test
build           :; forge build
clean           :; forge clean
test			:; forge test --gas-report