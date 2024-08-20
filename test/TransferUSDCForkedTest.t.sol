// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console, Vm} from "forge-std/Test.sol";
import {TransferUSDC} from "src/TransferUSDC.sol";
import {SwapTestnetUSDC} from "src/SwapTestnetUSDC.sol";
import {CrossChainReceiver} from "src/CrossChainReceiver.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from
    "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {MockCCIPRouter} from "@chainlink/contracts-ccip/src/v0.8/ccip/test/mocks/MockRouter.sol";

contract TransferUSDCForkedTest is Test {
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    TransferUSDC public transferUSDCWithMockRouter;
    TransferUSDC public transferUSDC;
    SwapTestnetUSDC public swapTestnetUSDC;
    CrossChainReceiver public crossChainReceiverWithMockRouter;
    CrossChainReceiver public crossChainReceiver;
    MockCCIPRouter public router;

    address public sender = 0x8C244f0B2164E6A3BED74ab429B0ebd661Bb14CA; // my EOA having USDC on Avalanche Fuji
    // address public receiver = makeAddr("receiver");

    IERC20 public usdc_AvalancheFuji;
    IERC20 public usdc_EthereumSepolia;

    Register.NetworkDetails avalancheFujiNetworkDetails;
    Register.NetworkDetails ethereumSepoliaNetworkDetails;

    uint256 avalancheFujiFork;
    uint256 ethereumSepoliaFork;

    address constant usdcAddressOnAvalancheFuji = 0x5425890298aed601595a70AB815c96711a31Bc65;
    address constant usdcAddressOnEthereumSepolia = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant compoundUsdcTokenAddressOnEthereumSepolia = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant fauceteerAddressOnEthereumSepolia = 0x68793eA49297eB75DFB4610B68e076D2A5c7646C;
    address constant cometAddressOnEthereumSepolia = 0xAec1F48e02Cfb822Be958B68C7957156EB3F0b6e;

    function setUp() public {
        string memory AVALANCHE_FUJI_RPC_URL = vm.envString("AVALANCHE_FUJI_RPC_URL");
        string memory ETHEREUM_SEPOLIA_RPC_URL = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");

        avalancheFujiFork = vm.createSelectFork(AVALANCHE_FUJI_RPC_URL);
        ethereumSepoliaFork = vm.createFork(ETHEREUM_SEPOLIA_RPC_URL);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        router = new MockCCIPRouter();
        vm.makePersistent(address(ccipLocalSimulatorFork), address(router));

        avalancheFujiNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        usdc_AvalancheFuji = IERC20(usdcAddressOnAvalancheFuji);

        vm.startPrank(sender);
        transferUSDCWithMockRouter =
            new TransferUSDC(address(router), avalancheFujiNetworkDetails.linkAddress, usdcAddressOnAvalancheFuji);
        transferUSDC = new TransferUSDC(
            avalancheFujiNetworkDetails.routerAddress,
            avalancheFujiNetworkDetails.linkAddress,
            usdcAddressOnAvalancheFuji
        );
        vm.stopPrank();

        console.log("Sender USDC Balance (Initial): ", usdc_AvalancheFuji.balanceOf(address(sender)));

        ccipLocalSimulatorFork.requestLinkFromFaucet(address(transferUSDCWithMockRouter), 5 ether);
        ccipLocalSimulatorFork.requestLinkFromFaucet(address(transferUSDC), 5 ether);

        vm.selectFork(ethereumSepoliaFork);

        ethereumSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        usdc_EthereumSepolia = IERC20(usdcAddressOnEthereumSepolia);

        swapTestnetUSDC = new SwapTestnetUSDC(
            usdcAddressOnEthereumSepolia, compoundUsdcTokenAddressOnEthereumSepolia, fauceteerAddressOnEthereumSepolia
        );

        crossChainReceiverWithMockRouter =
            new CrossChainReceiver(address(router), cometAddressOnEthereumSepolia, address(swapTestnetUSDC));

        crossChainReceiver = new CrossChainReceiver(
            ethereumSepoliaNetworkDetails.routerAddress, cometAddressOnEthereumSepolia, address(swapTestnetUSDC)
        );

        crossChainReceiverWithMockRouter.allowlistSourceChain(ethereumSepoliaNetworkDetails.chainSelector, true);

        crossChainReceiver.allowlistSourceChain(ethereumSepoliaNetworkDetails.chainSelector, true);

        crossChainReceiverWithMockRouter.allowlistSender(address(transferUSDCWithMockRouter), true);

        crossChainReceiver.allowlistSender(address(transferUSDC), true);

        vm.makePersistent(address(crossChainReceiverWithMockRouter), address(crossChainReceiver));
    }

    function test_Fork() public {
        vm.selectFork(avalancheFujiFork);

        uint256 amountToSend = 1_000_000; // 1 USDC (as it contains 6 decimals)
        uint64 gasLimit = 500_000;

        vm.startPrank(sender);
        transferUSDCWithMockRouter.allowlistDestinationChain(ethereumSepoliaNetworkDetails.chainSelector, true);
        transferUSDC.allowlistDestinationChain(ethereumSepoliaNetworkDetails.chainSelector, true);
        usdc_AvalancheFuji.approve(address(transferUSDCWithMockRouter), amountToSend);
        usdc_AvalancheFuji.approve(address(transferUSDC), amountToSend);

        vm.recordLogs(); // Starts recording logs to capture events.
        transferUSDCWithMockRouter.transferUsdc(
            ethereumSepoliaNetworkDetails.chainSelector,
            address(crossChainReceiverWithMockRouter),
            amountToSend,
            gasLimit
        );
        // Fetches recorded logs to check for specific events and their outcomes.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 msgExecutedSignature = keccak256("MsgExecuted(bool,bytes,uint256)");

        // console.log(logs.length);
        uint256 totalGasConsumed;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == msgExecutedSignature) {
                (,, uint256 gasUsed) = abi.decode(logs[i].data, (bool, bytes, uint256));
                console.log("Gas used: %d", gasUsed);
                totalGasConsumed += gasUsed;
            }
        }

        uint64 totalGasConsumedPlusTenPercent = uint64((totalGasConsumed * 110) / 100); // Increase  by 10%

        console.log("Total Gas used (plus 10 percent): %d", totalGasConsumedPlusTenPercent);

        transferUSDC.transferUsdc(
            ethereumSepoliaNetworkDetails.chainSelector,
            address(crossChainReceiver),
            amountToSend,
            totalGasConsumedPlusTenPercent
        );
        vm.stopPrank();

        console.log("Sender USDC Balance (Final): ", usdc_AvalancheFuji.balanceOf(sender));

        // ccipLocalSimulatorFork.switchChainAndRouteMessage(ethereumSepoliaFork); // Uncommenting this line would result in the revert at executeSingleMessage() due to the empty (or non-function) input in the data field of ccipSend()
    }
}
