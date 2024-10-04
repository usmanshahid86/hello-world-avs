// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IRewardsCoordinator} from "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {Vm} from "forge-std/Vm.sol";

library SetupPaymentsLib {

    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));


    struct PaymentLeaves {
        bytes32[] leaves;
        bytes32[] tokenLeaves;
    }

    function createPaymentSubmissions(
        IRewardsCoordinator rewardsCoordinator,
        address strategy,
        uint256 numPayments,
        uint256 amountPerPayment,
        uint32 duration
    ) public {
        IRewardsCoordinator.RewardsSubmission[] memory rewardsSubmissions = new IRewardsCoordinator.RewardsSubmission[](numPayments);
        for (uint256 i = 0; i < numPayments; i++) {
            IRewardsCoordinator.StrategyAndMultiplier[] memory strategiesAndMultipliers = new IRewardsCoordinator.StrategyAndMultiplier[](1);
            strategiesAndMultipliers[0] = IRewardsCoordinator.StrategyAndMultiplier({
                strategy: IStrategy(strategy),
                multiplier: 10000
            });

            IRewardsCoordinator.RewardsSubmission memory rewardsSubmission = IRewardsCoordinator.RewardsSubmission({
                strategiesAndMultipliers: strategiesAndMultipliers,
                token: IStrategy(strategy).underlyingToken(),
                amount: amountPerPayment,
                startTimestamp: uint32(block.timestamp),
                duration: duration
            });

            rewardsSubmissions[i] = rewardsSubmission;
        }

        rewardsCoordinator.createAVSRewardsSubmission(rewardsSubmissions);
    }

    function processClaim(
        IRewardsCoordinator rewardsCoordinator,
        string memory filePath,
        uint256 indexToProve,
        address recipient,
        IRewardsCoordinator.EarnerTreeMerkleLeaf calldata earnerLeaf,
        uint256 NUM_TOKEN_EARNINGS,
        address strategy
    ) public {
        PaymentLeaves memory paymentLeaves = parseLeavesFromJson(filePath);
        
        bytes memory proof = generateMerkleProof(paymentLeaves.leaves, indexToProve);
        bytes memory tokenProof = generateMerkleProof(paymentLeaves.tokenLeaves, 0);

        uint32[] memory tokenIndices = new uint32[](NUM_TOKEN_EARNINGS);
        bytes[] memory tokenProofs = new bytes[](NUM_TOKEN_EARNINGS);
        tokenProofs[0] = tokenProof;

        IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves = new IRewardsCoordinator.TokenTreeMerkleLeaf[](NUM_TOKEN_EARNINGS);
        tokenLeaves[0] = defaultTokenLeaf(100, strategy);

        IRewardsCoordinator.RewardsMerkleClaim memory claim = IRewardsCoordinator.RewardsMerkleClaim({
            rootIndex: 0,
            earnerIndex: uint32(indexToProve),
            earnerTreeProof: proof,
            earnerLeaf: earnerLeaf,
            tokenIndices: tokenIndices,
            tokenTreeProofs: tokenProofs,
            tokenLeaves: tokenLeaves
        });

        rewardsCoordinator.processClaim(claim, recipient);
    }

    function submitPaymentRoot(
        IRewardsCoordinator rewardsCoordinator,
        address[] calldata earners,
        address strategy,
         uint256 NUM_PAYMENTS,
        uint256 NUM_TOKEN_EARNINGS,
        uint256 TOKEN_EARNINGS
    ) public {
        bytes32 paymentRoot = createPaymentRoot(rewardsCoordinator, earners, NUM_PAYMENTS, NUM_TOKEN_EARNINGS, TOKEN_EARNINGS, strategy);
        uint32 rewardsCalculationEndTimestamp = rewardsCoordinator.currRewardsCalculationEndTimestamp() + 1 weeks;
        rewardsCoordinator.submitRoot(paymentRoot, rewardsCalculationEndTimestamp);
    }

    function createPaymentRoot(
        IRewardsCoordinator rewardsCoordinator,
        address[] calldata earners,
        uint256 NUM_PAYMENTS,
        uint256 NUM_TOKEN_EARNINGS,
        uint256 TOKEN_EARNINGS,
        address strategy
    ) public returns (bytes32) {
        require(earners.length == NUM_PAYMENTS, "Number of earners must match number of payments");
        bytes32[] memory leaves = new bytes32[](NUM_PAYMENTS);
        IRewardsCoordinator.EarnerTreeMerkleLeaf[] memory earnerLeaves = new IRewardsCoordinator.EarnerTreeMerkleLeaf[](NUM_PAYMENTS);
        
        bytes32[] memory tokenLeaves = createTokenLeaves(rewardsCoordinator, NUM_TOKEN_EARNINGS, TOKEN_EARNINGS, strategy);
        require(tokenLeaves.length == NUM_TOKEN_EARNINGS, "Number of token leaves must match number of token earnings");
        for (uint256 i = 0; i < NUM_PAYMENTS; i++) {
            address earner = earners[i];
            bytes32 earnerTokenRoot = createTokenRoot(tokenLeaves);
            IRewardsCoordinator.EarnerTreeMerkleLeaf memory leaf = IRewardsCoordinator.EarnerTreeMerkleLeaf({
                earner: earners[i],
                earnerTokenRoot: createTokenRoot(tokenLeaves)
            });
            leaves[i] = rewardsCoordinator.calculateEarnerLeafHash(leaf);
            earnerLeaves[i] = leaf;
        }
        writeLeavesToJson(leaves, tokenLeaves);
        return merkleizeKeccak(leaves);
    }

    function createTokenRoot(bytes32[] memory tokenLeaves) public pure returns (bytes32) {
        return merkleizeKeccak(tokenLeaves);   
    }

    function createTokenLeaves(
        IRewardsCoordinator rewardsCoordinator,
        uint256 NUM_TOKEN_EARNINGS,
        uint256 TOKEN_EARNINGS,
        address strategy
    ) public returns (bytes32[] memory) {
        bytes32[] memory leaves = new bytes32[](NUM_TOKEN_EARNINGS);
        for (uint256 i = 0; i < NUM_TOKEN_EARNINGS; i++) {
            IRewardsCoordinator.TokenTreeMerkleLeaf memory leaf = defaultTokenLeaf(TOKEN_EARNINGS, strategy);
            leaves[i] = rewardsCoordinator.calculateTokenLeafHash(leaf);
        }
        return leaves;
    }

    function defaultTokenLeaf(
        uint256 TOKEN_EARNINGS,
        address strategy
    ) public view returns (IRewardsCoordinator.TokenTreeMerkleLeaf memory) {
        IRewardsCoordinator.TokenTreeMerkleLeaf memory leaf = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: IStrategy(strategy).underlyingToken(),
            cumulativeEarnings: TOKEN_EARNINGS
        });
        return leaf;
    }

    function writeLeavesToJson(
        bytes32[] memory leaves,
        bytes32[] memory tokenLeaves
    ) public {
        string memory parent_object = "parent_object";
        vm.serializeBytes32(parent_object, "leaves", leaves);
        string memory finalJson = vm.serializeBytes32(parent_object, "tokenLeaves", tokenLeaves);
        vm.writeJson(finalJson, "payments.json");
    }

    function parseLeavesFromJson(string memory filePath) public returns (PaymentLeaves memory) {
        string memory json = vm.readFile(filePath);
        bytes memory data = vm.parseJson(json);
        return abi.decode(data, (PaymentLeaves));
    }

    function generateMerkleProof(bytes32[] memory leaves, uint256 index) public pure returns (bytes memory) {
        require(leaves.length > 0, "Leaves array cannot be empty");
        require(index < leaves.length, "Index out of bounds");

        leaves = padLeaves(leaves);

        uint256 n = leaves.length;
        uint256 depth = 0;
        while ((1 << depth) < n) {
            depth++;
        }

        bytes32[] memory proof = new bytes32[](depth);
        uint256 proofIndex = 0;

        for (uint256 i = 0; i < depth; i++) {
            uint256 levelSize = (n + 1) / 2;
            uint256 siblingIndex = (index % 2 == 0) ? index + 1 : index - 1;

            if (siblingIndex < n) {
                proof[proofIndex] = leaves[siblingIndex];
                proofIndex++;
            }

            for (uint256 j = 0; j < levelSize; j++) {
                if (2 * j + 1 < n) {
                    leaves[j] = keccak256(abi.encodePacked(leaves[2 * j], leaves[2 * j + 1]));
                } else {
                    leaves[j] = leaves[2 * j];
                }
            }

            n = levelSize;
            index /= 2;
        }

        return abi.encodePacked(proof);
    }

    /**
     * @notice this function returns the merkle root of a tree created from a set of leaves using keccak256 as its hash function
     *  @param leaves the leaves of the merkle tree
     *  @return The computed Merkle root of the tree.
     *  @dev This pads to the next power of 2. very inefficient! just for POC
     */
    function merkleizeKeccak(bytes32[] memory leaves) internal pure returns (bytes32) {
        // uint256 paddedLength = 2;
        // while(paddedLength < leaves.length) {
        //     paddedLength <<= 1;
        // }

        // bytes32[] memory paddedLeaves = new bytes32[](paddedLength);
        // for (uint256 i = 0; i < leaves.length; i++) {
        //     paddedLeaves[i] = leaves[i];
        // }
        leaves = padLeaves(leaves);

        //there are half as many nodes in the layer above the leaves
        uint256 numNodesInLayer = leaves.length / 2;
        //create a layer to store the internal nodes
        bytes32[] memory layer = new bytes32[](numNodesInLayer);
        //fill the layer with the pairwise hashes of the leaves
        for (uint256 i = 0; i < numNodesInLayer; i++) {
            layer[i] = keccak256(abi.encodePacked(leaves[2 * i], leaves[2 * i + 1]));
        }
        //the next layer above has half as many nodes
        numNodesInLayer /= 2;
        //while we haven't computed the root
        while (numNodesInLayer != 0) {
            //overwrite the first numNodesInLayer nodes in layer with the pairwise hashes of their children
            for (uint256 i = 0; i < numNodesInLayer; i++) {
                layer[i] = keccak256(abi.encodePacked(layer[2 * i], layer[2 * i + 1]));
            }
            //the next layer above has half as many nodes
            numNodesInLayer /= 2;
        }
        //the first node in the layer is the root
        return layer[0];
    }

    function padLeaves(bytes32[] memory leaves) internal pure returns (bytes32[] memory) {
        uint256 paddedLength = 2;
        while(paddedLength < leaves.length) {
            paddedLength <<= 1;
        }

        bytes32[] memory paddedLeaves = new bytes32[](paddedLength);
        for (uint256 i = 0; i < leaves.length; i++) {
            paddedLeaves[i] = leaves[i];
        }
        return paddedLeaves;
    }
}