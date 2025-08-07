
import Blob "mo:base/Blob";
import Result "mo:base/Result";

import Cycles "mo:base/ExperimentalCycles";

import Reader "./reader";
import IC "mo:ic";
import Ver1 "./memory/v1";
import MU "mo:mosup";
import Map "mo:core/Map";
import Nat32 "mo:base/Nat32";
import Option "mo:base/Option";
import List "mo:core/List";
import Principal "mo:base/Principal";

persistent actor class BtcBlocks() = this {
    type R<A,B> = Result.Result<A,B>;

    let ic : IC.Service = actor("aaaaa-aa");

    transient let VM = Ver1;
    let mem_ver1 = Ver1.new();
    transient let mem = MU.access(mem_ver1);
 
    public query func cycles() : async Nat {
        Cycles.balance();
    };

    transient let GET_BLOCK_HEADER_COST_CYCLES : Nat = 10_000_000_000;
    transient let BLOCK_WINDOW_SIZE : Nat32 = 12;
    transient let MAX_BLOCKS_TO_KEEP = 576; // 4 days of blocks

    // Notifier passes blocks which get verified by the canister.
    // We should have redundancy here and staking/slashing to make it trustless.
    let notifier = Principal.fromText("mfjwu-hg5c2-7opxi-obhzg-kr5yd-gm62t-smwi7-qwtfo-ouqzu-mhj2j-7qe"); 

    public type BlockInput = VM.Block and {height: Nat32};
 
    public type ProcessingError = {
        #NeedBlock : (height: Nat32);
        #AlreadyProcessed;
        #UnknownHeight;
        #InvalidBlock;
        #TemporarilyUnavailable;
        #TooFarBehind;
        #ProcessingLocked;
        #NoNewHeaders;
    };


    public type BlockResponse = {
        tip : Nat32;
        block : ?VM.Block;
        prev_block_headers : [(Nat32, Blob)];
        total_stored_blocks : Nat32;
    };

    public type GetBlockError = {
        #UnknownHeight;
    };


    public query func get_block(height: Nat32) : async R<BlockResponse, ProcessingError> {
        let mem_block = Map.get(mem.blocks, Nat32.compare, height);

        let prev_block_headers = List.empty<(Nat32, Blob)>();

        label find_prev_headers for (block in Map.reverseEntriesFrom(mem.blocks, Nat32.compare, height - 1)) {
            List.add(prev_block_headers, (block.0, block.1.header));
            if (block.0 < height - BLOCK_WINDOW_SIZE) break find_prev_headers;
        };

        let tip = Option.get(do ? {Map.maxEntry(mem.blocks)!.0}, 0:Nat32);

        #ok({
            tip;
            block = mem_block;
            prev_block_headers = List.toArray(prev_block_headers);
            total_stored_blocks = Nat32.fromNat(Map.size(mem.blocks));
        });
    };

    var lock_processing = false;

    // Accepts one block at a time. Has to be the next missing block that's part of the chain.
    // Removes orphaned blocks.
    public shared({caller}) func process_block(block: BlockInput) : async R<(), ProcessingError> {
        assert(caller == notifier);

        if (lock_processing) return #err(#ProcessingLocked);

        // Check if already exists
        ignore do ? {
            let mem_block = Map.get(mem.blocks, Nat32.compare, block.height);
            if (mem_block!.header == block.header) return #err(#AlreadyProcessed);
        };

        // Check if we are too far behind
        ignore do ? {
            let current_max_height = Map.maxEntry(mem.blocks)!.0;
            if (block.height < current_max_height - BLOCK_WINDOW_SIZE) return #err(#TooFarBehind);
        };

        try {
            lock_processing := true;
            let start_height = block.height - BLOCK_WINDOW_SIZE;
            let resp = await (with cycles=GET_BLOCK_HEADER_COST_CYCLES) ic.bitcoin_get_block_headers({start_height; end_height = null; network = #mainnet});
            
            if (resp.block_headers.size() == 0) {
                lock_processing := false;
                return #err(#NoNewHeaders);
            };

            // Find the last valid height in the mem.blocks
            var next_needed_height = start_height;
            var resp_idx = 0;

            label find_next for (header in resp.block_headers.vals()) {
             
                switch(Map.get(mem.blocks, Nat32.compare, next_needed_height)) {
                    case null break find_next;
                    case (?mem_block) {
                        if (mem_block.header != header) break find_next;
                    };
                };
               
                resp_idx += 1;
                next_needed_height += 1;
            };

            

            if (resp_idx == resp.block_headers.size()) {
                lock_processing := false;
                return #err(#NoNewHeaders);
            };

            if (Nat32.fromNat(Map.size(mem.blocks)) > BLOCK_WINDOW_SIZE) { // This algo wont work if we have less than BLOCK_WINDOW_SIZE initially
                // Remove all orphaned blocks after next_needed_height
                ignore do ? {
                    let current_max_height = Map.maxEntry(mem.blocks)!.0;
                    var i = current_max_height;
                    while (i >= next_needed_height) {
                        Map.remove(mem.blocks, Nat32.compare, i);
                        i -= 1;
                    };
                };

                // What is the next block we need to get?
                if (next_needed_height != block.height) {
                    lock_processing := false;
                    return #err(#NeedBlock(next_needed_height));
                };
            };

            // Find the header for the block we are processing
            var trusted_header: ?Blob = null;
            var resp_header_height = start_height;
            label find_header for (header in resp.block_headers.vals()) {
                if (resp_header_height == block.height) {
                    trusted_header := ?header;
                    break find_header;
                };

                resp_header_height += 1;
            };

            let ?usable_trusted_header = trusted_header else {
                lock_processing := false;
                return #err(#UnknownHeight);
            };

            let vres = Reader.verifyBlock(block, usable_trusted_header);

            if (not vres.isValid) {
                lock_processing := false;
                return #err(#InvalidBlock);
            };

            Map.add(mem.blocks, Nat32.compare, block.height, block);


            // If we have more than MAX_BLOCKS_TO_KEEP, remove the oldest block
            if (Map.size(mem.blocks) > MAX_BLOCKS_TO_KEEP) {
                ignore do ? {
                    Map.remove(mem.blocks, Nat32.compare, Map.minEntry(mem.blocks)!.0);
                };
            };

            #ok();
        } catch (_) {
            lock_processing := false;
            return #err(#TemporarilyUnavailable);
        } finally {
            lock_processing := false;
        };
      
    };

    

}