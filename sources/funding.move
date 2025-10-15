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
// Fund does not carry its own UID; it lives inside Campaign
public struct Fund<phantom T> has store {
    registry: Table<address, vector<Contribution>>,
    contributors: vector<address>,
    balance: Balance<T>,
    total_registry: u64
}

// Constructor to create a new Fund inside another module
public  fun create<T>(ctx: &mut TxContext): Fund<T> {
    Fund<T> {
        registry: table::new(ctx),
        contributors: vector::empty<address>(),
        balance: balance::zero<T>(),
        total_registry: 0
    }
}


// credit a fund

/// Add a contribution to the fund
/// Add a contribution to the fund
public(package) fun add_contribution<T>(
    fund: &mut Fund<T>,
    contributor: address,
    payment: Coin<T>,
    remark: String,
    timestamp_ms: u64,
) {
    let amount = coin::value(&payment);
    
    assert!(amount > 0, EInvalidAmount);
    
    // Add coin to balance
    let coin_balance = coin::into_balance(payment);
    balance::join(&mut fund.balance, coin_balance);
    
    // Create contribution record
    let contribution = Contribution {
        amount,
        timestamp_ms,
        remark
    };
    
    // Update or create contributor record
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


// claims by fund creator


// withdraw contribution by contributor
public(package) fun withdraw_contribution<T>(
    fund: &mut Fund<T>,
    contributor: address,
    ctx: &mut TxContext
): u64 {
    assert!(table::contains(&fund.registry, contributor), ENoContribution);
    
    let contributions = table::borrow(&fund.registry, contributor);
    
    // Calculate total amount
    let total_amount = calculate_total_contributions(contributions);
    assert!(total_amount > 0, EInvalidAmount);
    assert!(balance::value(&fund.balance) >= total_amount, EInsufficientBalance);
    
    // Extract balance and create coin
    let withdrawal_balance = balance::split(&mut fund.balance, total_amount);
    let withdrawal_coin = coin::from_balance(withdrawal_balance, ctx);
    
    // Transfer to contributor
    transfer::public_transfer(withdrawal_coin, contributor);

    // Remove contributor record and explicitly destroy the vector
    let contributions = table::remove(&mut fund.registry, contributor);
    vector::destroy_empty(contributions); 
    
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

/// Calculate total amount from a vector of contributions
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


/// Refund all contributors their full contribution amounts
/// Returns the total amount refunded
public(package) fun refund_all_contributors<T>(
    fund: &mut Fund<T>,
    ctx: &mut TxContext
): u64 {
    let mut total_refunded = 0u64;
    
    // Process refunds for all contributors
    // We iterate in reverse to safely remove elements
    while (vector::length(&fund.contributors) > 0) {
        // Get the last contributor
        let contributor = *vector::borrow(&fund.contributors, vector::length(&fund.contributors) - 1);
        
        // Get their contributions
        let contributions = table::borrow(&fund.registry, contributor);
        let refund_amount = calculate_total_contributions(contributions);
        
        assert!(balance::value(&fund.balance) >= refund_amount, EInsufficientBalance);
        
        // Extract balance and create coin
        let refund_balance = balance::split(&mut fund.balance, refund_amount);
        let refund_coin = coin::from_balance(refund_balance, ctx);
        
        // Transfer to contributor
        transfer::public_transfer(refund_coin, contributor);
        
        // Remove contributor record
        let contributions = table::remove(&mut fund.registry, contributor);
        vector::destroy_empty(contributions);
        
        // Remove from contributors vector
        vector::pop_back(&mut fund.contributors);
        
        // Update totals
        total_refunded = total_refunded + refund_amount;
        fund.total_registry = fund.total_registry - 1;
    };
    
    total_refunded
}



/// Get total balance in the fund
public fun get_balance<T>(fund: &Fund<T>): u64 {
    balance::value(&fund.balance)
}


/// Get total number of contributors
public fun get_contributor_count<T>(fund: &Fund<T>): u64 {
    fund.total_registry
}

/// Get a contributor's total contribution amount
public fun get_contributor_total<T>(fund: &Fund<T>, contributor: address): u64 {
    if (!table::contains(&fund.registry, contributor)) {
        return 0
    };
    let contributions = table::borrow(&fund.registry, contributor);
    calculate_total_contributions(contributions)
}

/// Check if an address has contributed
public fun is_contributor<T>(fund: &Fund<T>, contributor: address): bool {
    table::contains(&fund.registry, contributor)
}

/// Get number of contributions by a contributor
public fun get_contribution_count<T>(fund: &Fund<T>, contributor: address): u64 {
    if (!table::contains(&fund.registry, contributor)) {
        return 0
    };
    let contributions = table::borrow(&fund.registry, contributor);
    vector::length(contributions)
}


/// Refund contributors up to a certain amount (e.g., small contributors first)
public(package) fun refund_contributors_under_amount<T>(
    fund: &mut Fund<T>,
    max_amount: u64,
    ctx: &mut TxContext
): u64 {
    let mut total_refunded = 0u64;
    let mut i = 0;
    
    while (i < vector::length(&fund.contributors)) {
        let contributor = *vector::borrow(&fund.contributors, i);
        let contributions = table::borrow(&fund.registry, contributor);
        let contribution_total = calculate_total_contributions(contributions);
        
        if (contribution_total <= max_amount) {
            // Refund this contributor
            let refund_amount = withdraw_contribution(fund, contributor, ctx);
            total_refunded = total_refunded + refund_amount;
        } else {
            i = i + 1;
        }
    };
    
    total_refunded
}