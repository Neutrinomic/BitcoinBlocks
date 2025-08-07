import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Sha256 "mo:sha2/Sha256";
import Ver1 "./memory/v1";

module {

  public func doubleSHA256(data : [Nat8]) : [Nat8] {
    return Blob.toArray(Sha256.fromBlob(#sha256, Sha256.fromArray(#sha256, data)));
  };

  let VM = Ver1;

  public type Block = VM.Block;

  // Extract 32-byte Merkle root from block header (bytes 36 to 68)
  func extractMerkleRoot(header: [Nat8]) : [Nat8] {
    Iter.toArray(Array.slice(header, 36, 68));
  };

  // Convert Blob to [Nat8] for hashing
  func blobToBytes(blob: Blob) : [Nat8] {
    Blob.toArray(blob)
  };

  // Build merkle tree from transaction hashes (optimized)
  func buildMerkleRoot(txHashes: [[Nat8]]) : [Nat8] {
    if (txHashes.size() == 0) {
      return Array.tabulate<Nat8>(32, func(_) = 0); // Zero hash for empty block
    };
    
    if (txHashes.size() == 1) {
      return txHashes[0]; // Single transaction is the root
    };

    var level = txHashes;
    
    while (level.size() > 1) {
      let nextLevel = Array.init<[Nat8]>((level.size() + 1) / 2, []);
      var nextIndex = 0;
      
      var i = 0;
      while (i < level.size()) {
        let left = level[i];
        let right = if (i + 1 < level.size()) level[i + 1] else left; // Duplicate last if odd
        
        let combined = Array.append(left, right);
        let hashed = doubleSHA256(combined);
        nextLevel[nextIndex] := hashed;
        
        nextIndex += 1;
        i += 2;
      };
      
      level := Array.tabulate<[Nat8]>(nextIndex, func(i) = nextLevel[i]);
    };
    
    level[0]
  };

  // Optimized block verifier - verifies entire block merkle tree
  public func verifyBlock(block: Block, trusted_header: Blob) : {
    isValid: Bool;
    txCount: Nat;
  } {

    if (block.header.size() != 80 or trusted_header != block.header) {
      return {
        isValid = false;
        txCount = 0;
      };
    };
    
    let expectedRoot = extractMerkleRoot(Blob.toArray(trusted_header));
    
    // Step 1: Calculate all transaction hashes (txids) efficiently
    let txHashes = Array.map<Blob, [Nat8]>(block.transactions, func(tx: Blob) : [Nat8] {
      doubleSHA256(blobToBytes(tx))
    });
    
    // Step 2: Build merkle tree and get calculated root
    let calculatedRoot = buildMerkleRoot(txHashes);
    
    // Step 3: Compare roots
    let isValid = calculatedRoot == expectedRoot;
    
    {
      isValid;
      txCount = block.transactions.size();
    }
  };




};
