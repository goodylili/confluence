module confluence::funding_tests;

use std::string;

use sui::{
    clock::{Self, Clock},
    coin::{Self, Coin},
    sui::SUI,
    test_scenario
};

use confluence::funding;

// ===== helpers =====

fun test_clock(ctx: &mut TxContext, seed: u64): Clock {
    let mut clk = clock::create_for_testing(ctx);
    clock::increment_for_testing(&mut clk, seed);
    clk
}

// A local holder to wrap Fund and allow sharing for testing
public struct FundHolder<phantom T> has key, store {
    id: UID,
    fund: funding::Fund<T>,
}

fun new_holder<T>(ctx: &mut TxContext): FundHolder<T> {
    FundHolder<T> { id: object::new(ctx), fund: funding::create<T>(ctx) }
}

public fun transfer_holder_to<T>(holder: FundHolder<T>, recipient: address) {
    transfer::public_transfer(holder, recipient)
}

// ===== tests =====

#[test]
fun create_and_add_contributions_happy_path() {
    let creator = @0xA;
    let contributor1 = @0xB;
    let contributor2 = @0xC;

    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 1);

    let mut holder = new_holder<SUI>(test_scenario::ctx(&mut scenario));

    let ts = clock::timestamp_ms(&clock);

    let coin1 = coin::mint_for_testing<SUI>(50, test_scenario::ctx(&mut scenario));
    funding::add_contribution<SUI>(&mut holder.fund, contributor1, coin1, string::utf8(b"first"), ts);

    let coin2 = coin::mint_for_testing<SUI>(75, test_scenario::ctx(&mut scenario));
    funding::add_contribution<SUI>(&mut holder.fund, contributor2, coin2, string::utf8(b"second"), ts);

    assert!(funding::get_balance(&holder.fund) == 125, 1);
    assert!(funding::get_contributor_count(&holder.fund) == 2, 2);
    assert!(funding::is_contributor(&holder.fund, contributor1), 3);
    assert!(funding::get_contribution_count(&holder.fund, contributor1) == 1, 4);
    assert!(funding::get_contributor_total(&holder.fund, contributor1) == 50, 5);

    // Another contribution from contributor1
    let coin3 = coin::mint_for_testing<SUI>(25, test_scenario::ctx(&mut scenario));
    funding::add_contribution<SUI>(&mut holder.fund, contributor1, coin3, string::utf8(b"third"), ts);
    assert!(funding::get_balance(&holder.fund) == 150, 6);
    assert!(funding::get_contributor_count(&holder.fund) == 2, 7);
    assert!(funding::get_contribution_count(&holder.fund, contributor1) == 2, 8);
    assert!(funding::get_contributor_total(&holder.fund, contributor1) == 75, 9);

    transfer_holder_to(holder, creator);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun withdraw_contribution_transfers_coin() {
    let creator = @0xA;
    let contributor = @0xB;

    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 2);
    let mut holder = new_holder<SUI>(test_scenario::ctx(&mut scenario));

    let ts = clock::timestamp_ms(&clock);
    let coin1 = coin::mint_for_testing<SUI>(60, test_scenario::ctx(&mut scenario));
    funding::add_contribution<SUI>(&mut holder.fund, contributor, coin1, string::utf8(b"once"), ts);
    assert!(funding::get_balance(&holder.fund) == 60, 10);

    let refunded = funding::withdraw_contribution<SUI>(&mut holder.fund, contributor, test_scenario::ctx(&mut scenario));
    assert!(refunded == 60, 11);
    assert!(funding::get_contributor_count(&holder.fund) == 0, 12);
    assert!(funding::get_balance(&holder.fund) == 0, 13);

    // Verify the coin was transferred to contributor
    test_scenario::next_tx(&mut scenario, contributor);
    {
        let refund_coin = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&refund_coin) == 60, 14);
        test_scenario::return_to_address<Coin<SUI>>(contributor, refund_coin);
    };

    transfer_holder_to(holder, creator);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun refund_all_contributors_emits_coins() {
    let creator = @0xA;
    let a = @0xB;
    let b = @0xC;
    let d = @0xD;

    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 3);
    let mut holder = new_holder<SUI>(test_scenario::ctx(&mut scenario));

    let ts = clock::timestamp_ms(&clock);
    funding::add_contribution<SUI>(&mut holder.fund, a, coin::mint_for_testing<SUI>(10, test_scenario::ctx(&mut scenario)), string::utf8(b"a"), ts);
    funding::add_contribution<SUI>(&mut holder.fund, b, coin::mint_for_testing<SUI>(20, test_scenario::ctx(&mut scenario)), string::utf8(b"b"), ts);
    funding::add_contribution<SUI>(&mut holder.fund, d, coin::mint_for_testing<SUI>(30, test_scenario::ctx(&mut scenario)), string::utf8(b"d"), ts);
    assert!(funding::get_balance(&holder.fund) == 60, 20);
    assert!(funding::get_contributor_count(&holder.fund) == 3, 21);

    let total = funding::refund_all_contributors<SUI>(&mut holder.fund, test_scenario::ctx(&mut scenario));
    assert!(total == 60, 22);
    assert!(funding::get_contributor_count(&holder.fund) == 0, 23);
    assert!(funding::get_balance(&holder.fund) == 0, 24);

    // Verify coins at recipients
    test_scenario::next_tx(&mut scenario, a);
    {
        let c1 = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&c1) == 10, 25);
        test_scenario::return_to_address<Coin<SUI>>(a, c1);
    };

    test_scenario::next_tx(&mut scenario, b);
    {
        let c2 = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&c2) == 20, 26);
        test_scenario::return_to_address<Coin<SUI>>(b, c2);
    };

    test_scenario::next_tx(&mut scenario, d);
    {
        let c3 = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&c3) == 30, 27);
        test_scenario::return_to_address<Coin<SUI>>(d, c3);
    };

    transfer_holder_to(holder, creator);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun refund_contributors_under_amount_batches() {
    let creator = @0xA;
    let a = @0xB; // 50
    let b = @0xC; // 150
    let d = @0xD; // 75

    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 4);
    let mut holder = new_holder<SUI>(test_scenario::ctx(&mut scenario));

    let ts = clock::timestamp_ms(&clock);
    funding::add_contribution<SUI>(&mut holder.fund, a, coin::mint_for_testing<SUI>(50, test_scenario::ctx(&mut scenario)), string::utf8(b"a"), ts);
    funding::add_contribution<SUI>(&mut holder.fund, b, coin::mint_for_testing<SUI>(150, test_scenario::ctx(&mut scenario)), string::utf8(b"b"), ts);
    funding::add_contribution<SUI>(&mut holder.fund, d, coin::mint_for_testing<SUI>(75, test_scenario::ctx(&mut scenario)), string::utf8(b"d"), ts);

    // Refund those under or equal to 100 in a batch
    let (total1, next_index, is_complete1) = funding::refund_contributors_under_amount<SUI>(&mut holder.fund, 100, 0, 3, test_scenario::ctx(&mut scenario));
    assert!(total1 == 125, 30);
    assert!(!is_complete1, 31);

    // Verify coins for a and d
    test_scenario::next_tx(&mut scenario, a);
    {
        let ca = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&ca) == 50, 32);
        test_scenario::return_to_address<Coin<SUI>>(a, ca);
    };
    test_scenario::next_tx(&mut scenario, d);
    {
        let cd = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&cd) == 75, 33);
        test_scenario::return_to_address<Coin<SUI>>(d, cd);
    };

    // Complete remaining refunds (should be only b left and above threshold)
    let (total2, _next_index2, is_complete2) = funding::refund_contributors_under_amount<SUI>(&mut holder.fund, 100, next_index, 10, test_scenario::ctx(&mut scenario));
    assert!(total2 == 0, 34);
    assert!(is_complete2, 35);

    // b should still be a contributor with 150
    assert!(funding::get_contributor_count(&holder.fund) == 1, 36);
    let addr0 = funding::get_contributor_at(&holder.fund, 0);
    assert!(addr0 == b, 37);
    assert!(funding::get_contributor_total(&holder.fund, b) == 150, 38);

    transfer_holder_to(holder, creator);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun withdraw_for_creator_happy_path() {
    let creator = @0xA;
    let a = @0xB;

    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 5);
    let mut holder = new_holder<SUI>(test_scenario::ctx(&mut scenario));

    let ts = clock::timestamp_ms(&clock);
    funding::add_contribution<SUI>(&mut holder.fund, a, coin::mint_for_testing<SUI>(200, test_scenario::ctx(&mut scenario)), string::utf8(b"a"), ts);
    assert!(funding::get_balance(&holder.fund) == 200, 40);

    let coin_out = funding::withdraw_for_creator<SUI>(&mut holder.fund, 150, test_scenario::ctx(&mut scenario));
    assert!(coin::value(&coin_out) == 150, 41);
    assert!(funding::get_balance(&holder.fund) == 50, 42);

    // Transfer coin to creator to avoid leak
    transfer::public_transfer(coin_out, creator);

    transfer_holder_to(holder, creator);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure]
fun get_contributor_at_invalid_index_fails() {
    let creator = @0xA;
    let a = @0xB;

    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 6);
    let mut holder = new_holder<SUI>(test_scenario::ctx(&mut scenario));

    let ts = clock::timestamp_ms(&clock);
    funding::add_contribution<SUI>(&mut holder.fund, a, coin::mint_for_testing<SUI>(10, test_scenario::ctx(&mut scenario)), string::utf8(b"a"), ts);
    // Expect failure: index 1 out of bounds
    let _ = funding::get_contributor_at(&holder.fund, 1);

    transfer_holder_to(holder, creator);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure]
fun withdraw_unknown_contributor_fails() {
    let creator = @0xA;
    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 7);
    let mut holder = new_holder<SUI>(test_scenario::ctx(&mut scenario));

    let _refunded = funding::withdraw_contribution<SUI>(&mut holder.fund, @0xB, test_scenario::ctx(&mut scenario));

    transfer_holder_to(holder, creator);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}