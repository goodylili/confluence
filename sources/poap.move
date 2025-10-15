module confluence::poap;

use std::string::{Self, String, utf8};

use sui::{
    clock::{Self, Clock},
    event,
    package,
    display
};


public struct POAP has drop {}

// ====== ERROR CONSTANTS ======
const EEmptyName: u64 = 2;
const EEmptyDescription: u64 = 3;
const EEmptyUrl: u64 = 4;
const EInvalidAmount: u64 = 5;

// ====== POAP OBJECT ======
public struct POAPNFT has key, store {
    id: UID,
    campaign_id: ID,
    name: String,
    description: String,
    amount_contributed: u64,
    url: String,
}

// ====== EVENTS ======
public struct POAPIssued has copy, drop {
    poap_id: ID,
    campaign_id: ID,
    recipient: address,
    timestamp: u64,
    url: String,
}

fun init(otw: POAP, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let keys = vector[
        utf8(b"name"),
        utf8(b"description"),
        utf8(b"image_url"),
        utf8(b"link"),
        utf8(b"project_url"),
        utf8(b"creator"),
    ];

    let values = vector[
        utf8(b"{name}"),
        utf8(b"{description}"),
        utf8(b"{url}"),
        utf8(b"{url}"),
        utf8(b"https://confluence.app"),
        utf8(b"Confluence"),
    ];

    let mut disp = display::new_with_fields<confluence::poap::POAPNFT>(&publisher, keys, values, ctx);
    display::update_version(&mut disp);

    transfer::public_transfer(publisher, tx_context::sender(ctx));
    transfer::public_transfer(disp, tx_context::sender(ctx));
}

// ====== CORE MINT/ISSUE ======
fun mint_internal(
    campaign_id: ID,
    name: String,
    description: String,
    amount_contributed: u64,
    url: String,
    ctx: &mut TxContext
): POAPNFT {
    let uid = object::new(ctx);
    POAPNFT {
        id: uid,
        campaign_id,
        name,
        description,
        amount_contributed,
        url,
    }
}

/// Issue a POAP to `recipient` for a contribution to `campaign`.
/// Only the campaign creator can issue.
public(package) fun issue_for_contribution(
    campaign_id: ID,
    recipient: address,
    name: String,
    description: String,
    amount_contributed: u64,
    url: String,
    clock: &Clock,
    ctx: &mut TxContext
) {
    // Basic validations
    assert!(string::length(&name) > 0, EEmptyName);
    assert!(string::length(&description) > 0, EEmptyDescription);
    assert!(string::length(&url) > 0, EEmptyUrl);
    assert!(amount_contributed > 0, EInvalidAmount);

    let poap = mint_internal(
        campaign_id,
        name,
        description,
        amount_contributed,
        url,
        ctx
    );

    let ts = clock::timestamp_ms(clock);
    event::emit(POAPIssued {
        poap_id: get_id(&poap),
        campaign_id,
        recipient,
        timestamp: ts,
        url,
    });

    transfer::public_transfer(poap, recipient);
}

// ====== TRANSFER & BURN ======
public(package) fun transfer_poap(poap: POAPNFT, recipient: address) {
    transfer::public_transfer(poap, recipient);
}

public(package) fun burn(poap: POAPNFT) {
    let POAPNFT { id, campaign_id: _, name: _, description: _, amount_contributed: _, url: _ } = poap;
    object::delete(id);
}

// ====== GETTERS ======
public(package) fun get_id(poap: &POAPNFT): ID {
    object::uid_to_inner(&poap.id)
}

public(package) fun get_campaign_id(poap: &POAPNFT): ID {
    poap.campaign_id
}

public(package) fun get_name(poap: &POAPNFT): String {
    poap.name
}

public(package) fun get_description(poap: &POAPNFT): String {
    poap.description
}

public(package) fun get_amount_contributed(poap: &POAPNFT): u64 {
    poap.amount_contributed
}

public(package) fun get_url(poap: &POAPNFT): String {
    poap.url
}