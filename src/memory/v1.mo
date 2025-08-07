import MU "mo:mosup";
import Blob "mo:base/Blob";
import Map "mo:core/Map";

module {

    public type Mem = {
        blocks : Map.Map<Height, Block>;
    };

    public func new() : MU.MemShell<Mem> = MU.new<Mem>({
        blocks = Map.empty();
    });

    public type Height = Nat32;
    public type BlockTransaction = Blob;

    public type Block = {
        header: Blob;
        transactions: [BlockTransaction]    
    };

}; 