module confluence::campaign;

use std::{
    string::{Self, String}, 
    type_name::{Self, TypeName}
};

use sui::{
    clock::{Self, Clock},
    sui::SUI

};

use usdc::usdc::USDC;

use confluence::funding::{Self, Fund};


// ====== CAMPAIGN STATUSES ======
const STATUS_ACTIVE: u8 = 1;
const STATUS_PAUSED: u8 = 2;
const STATUS_SUCCESSFUL: u8 = 3;
const STATUS_FAILED: u8 = 4;
const STATUS_CANCELLED: u8 = 5;
const STATUS_WITHDRAWN: u8 = 6;


const EUnsupportedCoinType: u64 = 1;

public struct Campaign<phantom T> has key {
    id: UID,
    creator: address,
    title: String,
    coin_type: TypeName,
    description: String,
    goal: u64,
    funding: Fund<T>,
    end: u64,
    creation_timestamp_ms: u64,
    status: u8
}

public fun create_campaign<T>(
    title: String,
    description: String,
    goal: u64,
    duration_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext
): Campaign<T> {
    let creation_time = clock::timestamp_ms(clock);
    let coin_type = type_name::with_defining_ids<T>();

    // Assert T is either SUI or USDC
    let sui_type = type_name::with_defining_ids<SUI>();
    let usdc_type = type_name::with_defining_ids<USDC>();

    if (&coin_type != &sui_type && &coin_type != &usdc_type) {
        abort EUnsupportedCoinType
    };

    // Create the fund via funding module
    let funding = funding::create<T>(ctx);

    // Prepare campaign id and creator
    let uid = object::new(ctx);
    let sender = ctx.sender();

    // Create campaign with the fund
    Campaign<T> {
        id: uid,
        creator: sender,
        title,
        coin_type: coin_type,
        description,
        goal,
        funding,
        end: creation_time + duration_ms,
        creation_timestamp_ms: creation_time,
        status: STATUS_ACTIVE
    }
}


// Example: Make campaign a shared object
public entry fun create_and_share_campaign<T>(
    title: String,
    description: String,
    goal: u64,
    duration_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let campaign = create_campaign<T>(
        title,
        description,
        goal,
        duration_ms,
        clock,
        ctx
    );
    
    transfer::share_object(campaign);
}






// update campaign


// delete campaign


// read campaign
// getter functions
// setter functions





