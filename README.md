## Transfer-and-Deposit-USDC-estimateGas-CCIPLocalForked-Test

1. Add `AVALANCHE_FUJI_RPC_URL` and `ETHEREUM_SEPOLIA_RPC_URL` as environment variables in the **.env** file.

2. Execute the test:

    ```bash
    forge test --mt test_Fork -vvv
    ```
3. Output:

![test_Fork()-screenshot](./img/test_Fork()-screenshot.png)