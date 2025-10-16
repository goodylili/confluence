module confluence::confluence;

use sui::package::{Self, Publisher};

public struct CONFLUENCE has drop {}


fun init(otw: CONFLUENCE,ctx: &mut TxContext){
    let publisher : Publisher = package::claim(otw, ctx);
    transfer::public_transfer(publisher, ctx.sender());
}