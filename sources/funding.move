module confluence::funding;

use sui::{
    table::{Self, Table},
    balance::{Self, Balance},
    coin::{Self, Coin}
};

use std::string::String;

const ENoContribution: u64 = 0;
const EInsufficientBalance: u64 = 1;
const EInvalidAmount: u64 = 2;

public struct Contribution has store {
    amount: u64,
    timestamp_ms: u64,
    remark: String
}

public struct Fund<phantom T> has store {
    registry: Table<address, vector<Contribution>>,
    contributors: vector<address>,
    balance: Balance<T>,
    total_registry: u64
}

public  fun create<T>(ctx: &mut TxContext): Fund<T> {
    Fund<T> {
        registry: table::new(ctx),
        contributors: vector::empty<address>(),
        balance: balance::zero<T>(),
        total_registry: 0
    }
}

public(package) fun add_contribution<T>(
    fund: &mut Fund<T>,
    contributor: address,
    payment: Coin<T>,
    remark: String,
    timestamp_ms: u64,
) {
    let amount = coin::value(&payment);
    
    assert!(amount > 0, EInvalidAmount);
    
    let coin_balance = coin::into_balance(payment);
    balance::join(&mut fund.balance, coin_balance);
    
    let contribution = Contribution {
        amount,
        timestamp_ms,
        remark
    };
    
    if (table::contains(&fund.registry, contributor)) {
        let contributions = table::borrow_mut(&mut fund.registry, contributor);
        vector::push_back(contributions, contribution);
    } else {
        let mut contributions = vector::empty<Contribution>();
        vector::push_back(&mut contributions, contribution);
        table::add(&mut fund.registry, contributor, contributions);
        vector::push_back(&mut fund.contributors, contributor);
        fund.total_registry = fund.total_registry + 1;
    };
}

public(package) fun withdraw_contribution<T>(
    fund: &mut Fund<T>,
    contributor: address,
    ctx: &mut TxContext
): u64 {
    assert!(table::contains(&fund.registry, contributor), ENoContribution);
    
    let contributions = table::borrow(&fund.registry, contributor);
    
    let total_amount = calculate_total_contributions(contributions);
    assert!(total_amount > 0, EInvalidAmount);
    assert!(balance::value(&fund.balance) >= total_amount, EInsufficientBalance);
    
    let withdrawal_balance = balance::split(&mut fund.balance, total_amount);
    let withdrawal_coin = coin::from_balance(withdrawal_balance, ctx);
    
    transfer::public_transfer(withdrawal_coin, contributor);

    let contributions = table::remove(&mut fund.registry, contributor);
    destroy_contributions_vec(contributions);
    
    let mut i = 0;
    let len = vector::length(&fund.contributors);
    while (i < len) {
        if (vector::borrow(&fund.contributors, i) == &contributor) {
            vector::remove(&mut fund.contributors, i);
            break
        };
        i = i + 1;
    };

    fund.total_registry = fund.total_registry - 1;
    
    total_amount
}

fun calculate_total_contributions(contributions: &vector<Contribution>): u64 {
    let mut total = 0u64;
    let mut i = 0;
    let len = vector::length(contributions);
    
    while (i < len) {
        let contribution = vector::borrow(contributions, i);
        total = total + contribution.amount;
        i = i + 1;
    };
    
    total
}

public(package) fun refund_all_contributors<T>(
    fund: &mut Fund<T>,
    ctx: &mut TxContext
): u64 {
    let mut total_refunded = 0u64;
    
    let contributors_count = vector::length(&fund.contributors);
    let mut i = contributors_count;
    
    while (i > 0) {
        i = i - 1;
        
        let contributor = *vector::borrow(&fund.contributors, i);
        
        let contributions = table::borrow(&fund.registry, contributor);
        let refund_amount = calculate_total_contributions(contributions);
        
        assert!(balance::value(&fund.balance) >= refund_amount, EInsufficientBalance);
        
        let contributor_contributions = table::remove(&mut fund.registry, contributor);

        // Consume and destroy the contributor's contributions vector
        destroy_contributions_vec(contributor_contributions);
        
        vector::remove(&mut fund.contributors, i);
        
        total_refunded = total_refunded + refund_amount;
        fund.total_registry = fund.total_registry - 1;
        
        let refund_balance = balance::split(&mut fund.balance, refund_amount);
        let refund_coin = coin::from_balance(refund_balance, ctx);
        
        transfer::public_transfer(refund_coin, contributor);
    };
    
    total_refunded
}

// Helper to safely destroy a contributions vector regardless of its length
fun destroy_contributions_vec(contributions: vector<Contribution>) {
    // Work on a mutable local copy to consume elements
    let mut local = contributions;
    // Pop and drop each contribution element
    while (vector::length(&local) > 0) {
        let c = vector::pop_back(&mut local);
        let Contribution { amount: _, timestamp_ms: _, remark: _ } = c;
        // Fields are dropped; String remark has drop ability
    };
    // Now the vector is empty and can be destroyed
    vector::destroy_empty(local);
}

public fun get_balance<T>(fund: &Fund<T>): u64 {
    balance::value(&fund.balance)
}

public fun get_contributor_count<T>(fund: &Fund<T>): u64 {
    fund.total_registry
}

/// Get contributor address at a specific index for enumeration
public fun get_contributor_at<T>(fund: &Fund<T>, index: u64): address {
    let len = vector::length(&fund.contributors);
    assert!(index < len, EInvalidAmount);
    *vector::borrow(&fund.contributors, index)
}

public fun get_contributor_total<T>(fund: &Fund<T>, contributor: address): u64 {
    if (!table::contains(&fund.registry, contributor)) {
        return 0
    };
    let contributions = table::borrow(&fund.registry, contributor);
    calculate_total_contributions(contributions)
}

public fun is_contributor<T>(fund: &Fund<T>, contributor: address): bool {
    table::contains(&fund.registry, contributor)
}

public fun get_contribution_count<T>(fund: &Fund<T>, contributor: address): u64 {
    if (!table::contains(&fund.registry, contributor)) {
        return 0
    };
    let contributions = table::borrow(&fund.registry, contributor);
    vector::length(contributions)
}

public(package) fun refund_contributors_under_amount<T>(
    fund: &mut Fund<T>,
    max_amount: u64,
    start_index: u64,
    batch_size: u64,
    ctx: &mut TxContext
): (u64, u64, bool) {
    let mut total_refunded = 0u64;
    let mut i = start_index;
    let mut processed = 0u64;
    let contributors_length = vector::length(&fund.contributors);
    
    while (i < contributors_length && processed < batch_size) {
        let contributor = *vector::borrow(&fund.contributors, i);
        let contributions = table::borrow(&fund.registry, contributor);
        let contribution_total = calculate_total_contributions(contributions);
        
        if (contribution_total <= max_amount) {
            let refund_amount = withdraw_contribution(fund, contributor, ctx);
            total_refunded = total_refunded + refund_amount;
        } else {
            i = i + 1;
        };
        processed = processed + 1;
    };
    
    let is_complete = i >= contributors_length;
    
    (total_refunded, i, is_complete)
}

public(package) fun withdraw_for_creator<T>(
    fund: &mut Fund<T>,
    amount: u64,
    ctx: &mut TxContext
): Coin<T> {
    assert!(amount > 0, EInvalidAmount);
    assert!(balance::value(&fund.balance) >= amount, EInsufficientBalance);
    
    let withdrawal_balance = balance::split(&mut fund.balance, amount);
    let coin = coin::from_balance(withdrawal_balance, ctx);
    
    coin
}