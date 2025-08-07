# BitcoinBlocks

A Bitcoin block processing system that monitors the Bitcoin blockchain, extracts transaction data, and sends it to an Internet Computer (IC) canister for processing.

https://dashboard.internetcomputer.org/canister/3hfui-2aaaa-aaaal-qsrya-cai

## Overview

This system connects to a Bitcoin Core node via RPC, continuously monitors for new blocks, processes the block data to extract transactions without witness data, and forwards this processed data to an IC canister for storage and analysis.

Trusted headers come from the management canister (IC Bitcoin mainnet nodes) and if blocks get orphaned, they are deleted from memory and need to be added and processed again.

## Security

Each block is validated by hashing its transactions and confirming that the resulting hash matches the Merkle root in the trusted header. Governance is soon shifting to the Neutrinite DAO.

The off-chain relay can withhold blocks, but it cannot censor transactions, reorder or omit blocks, nor alter any transaction data.

## Warning

Still being tested.
get_blocks is likely going to require cycles in the future and will be accessible only from canisters.

## Architecture

The system consists of several key components:

### 1. Bitcoin Core Integration
- Connects to a local Bitcoin Core node via RPC (`bitcoin-core` library)
- Fetches blocks by height and retrieves raw block data
- Handles blockchain info queries to monitor for new blocks

### 2. Internet Computer Integration
- Connects to canister `3hfui-2aaaa-aaaal-qsrya-cai` for block processing
- Handles various canister response states and error conditions

### 3. Block Processing Pipeline
- **Raw Block Parsing**: Extracts the 80-byte header and transaction data
- **Transaction Processing**: Removes SegWit witness data to get pre-SegWit transaction format
- **Data Optimization**: Reduces block size by stripping witness data (typically 10-30% compression)
- **Canister Submission**: Sends processed blocks to IC canister with retry logic

## Key Features

### Transaction Processing
- Parses raw Bitcoin block data to extract individual transactions
- Removes SegWit witness data using `bitcoinjs-lib` for merkle tree compatibility
- Handles both legacy and SegWit transactions
- Provides compression statistics (witness vs non-witness data)

### Error Handling & Recovery
The system handles various canister response states:
- `NeedBlock`: Redirects to process a missing prerequisite block
- `AlreadyProcessed`: Skips blocks that have been processed
- `TemporarilyUnavailable`: Waits and retries with backoff
- `TooFarBehind`: Skips to more recent blocks
- `InvalidBlock`: Logs error and continues
- `ProcessingLocked`: Waits for canister to unlock
- `NoNewHeaders`: Normal state when caught up

### Monitoring & Automation
- Continuously monitors Bitcoin blockchain every minute
- Automatically processes new blocks as they arrive
- Maintains processing state to avoid reprocessing
- Graceful handling of network interruptions
