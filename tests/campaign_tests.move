module confluence::campaign_tests;

use std::string;


use sui::{ 
    clock::{Self, Clock},
    coin::{Self, Coin},
    sui::SUI,
    test_scenario
};


use confluence::campaign;

#[test]
fun create_campaign_sui_happy_path() {
    let creator = @0xA;
    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 1);

    let title = string::utf8(b"Test Campaign");
    let desc = string::utf8(b"A simple description");
    let goal = 100;
    let duration = 2_000; // ms

    let c = campaign::create_campaign<SUI>(title, desc, goal, duration, &clock, test_scenario::ctx(&mut scenario));

    // basic assertions
    assert!(campaign::get_goal(&c) == goal, 0);
    assert!(campaign::get_total_raised(&c) == 0, 1);
    assert!(campaign::is_active(&c, &clock), 2);
    // Finalization before end is covered by a dedicated expected-failure test.
    campaign::share_for_testing(c);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun contribute_and_goal_reach_marks_success() {
    let creator = @0xA;
    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 10);

    let mut c = campaign::create_campaign<SUI>(string::utf8(b"Test"), string::utf8(b"Desc"), 100u64, 5_000u64, &clock, test_scenario::ctx(&mut scenario));

    let amt1 = 60u64;
    let coin1: Coin<SUI> = coin::mint_for_testing<SUI>(amt1, test_scenario::ctx(&mut scenario));
    campaign::contribute<SUI>(&mut c, coin1, string::utf8(b"first"), &clock, test_scenario::ctx(&mut scenario));

    assert!(campaign::get_total_raised(&c) == 60, 10);
    assert!(!campaign::is_successful(&c), 11);

    let amt2 = 40u64;
    let coin2: Coin<SUI> = coin::mint_for_testing<SUI>(amt2, test_scenario::ctx(&mut scenario));
    campaign::contribute<SUI>(&mut c, coin2, string::utf8(b"second"), &clock, test_scenario::ctx(&mut scenario));

    // goal met => successful
    assert!(campaign::get_total_raised(&c) == 100, 12);
    assert!(campaign::is_successful(&c), 13);
    campaign::share_for_testing(c);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun pause_and_unpause_flow() {
    let creator = @0xA;
    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 20);
    let mut c = campaign::create_campaign<SUI>(string::utf8(b"Test"), string::utf8(b"Desc"), 100u64, 5_000u64, &clock, test_scenario::ctx(&mut scenario));

    // only creator can pause/unpause; the creator is ctx.sender() at creation
    campaign::pause_campaign<SUI>(&mut c, string::utf8(b"maintenance"), &clock, test_scenario::ctx(&mut scenario));
    assert!(campaign::is_paused(&c), 20);

    campaign::unpause_campaign<SUI>(&mut c, &clock, test_scenario::ctx(&mut scenario));
    assert!(campaign::is_active(&c, &clock), 21);
    campaign::share_for_testing(c);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun finalize_success_then_withdraw() {
    let creator = @0xA;
    let mut scenario = test_scenario::begin(creator);
    let mut clock = test_clock(test_scenario::ctx(&mut scenario), 30);
    let mut c = campaign::create_campaign<SUI>(string::utf8(b"Test"), string::utf8(b"Desc"), 100u64, 5_000u64, &clock, test_scenario::ctx(&mut scenario));

    // reach goal before end
    let coin1 = coin::mint_for_testing<SUI>(100, test_scenario::ctx(&mut scenario));
    campaign::contribute<SUI>(&mut c, coin1, string::utf8(b"full"), &clock, test_scenario::ctx(&mut scenario));
    assert!(campaign::is_successful(&c), 30);

    // move time to past end
    advance_clock(&mut clock, 10_000);

    campaign::finalize_campaign<SUI>(&mut c, &clock, test_scenario::ctx(&mut scenario));
    assert!(campaign::is_successful(&c), 31);

    // withdraw funds by creator
    campaign::withdraw_funds<SUI>(&mut c, 100, &clock, test_scenario::ctx(&mut scenario));
    assert!(campaign::is_withdrawn(&c), 32);
    campaign::share_for_testing(c);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
fun finalize_fail_then_refunds() {
    let creator = @0xA;
    let mut scenario = test_scenario::begin(creator);
    let mut clock = test_clock(test_scenario::ctx(&mut scenario), 40);
    let mut c = campaign::create_campaign<SUI>(string::utf8(b"Test"), string::utf8(b"Desc"), 100u64, 5_000u64, &clock, test_scenario::ctx(&mut scenario));

    // contribute but below goal
    let coin1 = coin::mint_for_testing<SUI>(30, test_scenario::ctx(&mut scenario));
    campaign::contribute<SUI>(&mut c, coin1, string::utf8(b"small"), &clock, test_scenario::ctx(&mut scenario));

    // time passes beyond end without reaching goal
    advance_clock(&mut clock, 10_000);
    campaign::finalize_campaign<SUI>(&mut c, &clock, test_scenario::ctx(&mut scenario));

    assert!(campaign::is_failed(&c), 40);
    campaign::share_for_testing(c);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure]
fun create_campaign_empty_title_fails() {
    let creator = @0xA;
    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 1001);
    let title = string::utf8(b""); // empty
    let desc = string::utf8(b"desc");
    let _c = campaign::create_campaign<SUI>(title, desc, 10, 2_000, &clock, test_scenario::ctx(&mut scenario));
    campaign::share_for_testing(_c);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure]
fun contribute_after_expiry_fails() {
    let creator = @0xA;
    let mut scenario = test_scenario::begin(creator);
    let mut clock = test_clock(test_scenario::ctx(&mut scenario), 1002);
    let mut c = campaign::create_campaign<SUI>(string::utf8(b"Test"), string::utf8(b"Desc"), 100u64, 5_000u64, &clock, test_scenario::ctx(&mut scenario));
    // push time past end
    advance_clock(&mut clock, 10_000);

    let coin1 = coin::mint_for_testing<SUI>(1, test_scenario::ctx(&mut scenario));
    campaign::contribute<SUI>(&mut c, coin1, string::utf8(b"late"), &clock, test_scenario::ctx(&mut scenario));
    campaign::share_for_testing(c);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure]
fun withdraw_before_end_fails() {
    let creator = @0xA;
    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 1003);
    let mut c = campaign::create_campaign<SUI>(string::utf8(b"Test"), string::utf8(b"Desc"), 100u64, 5_000u64, &clock, test_scenario::ctx(&mut scenario));

    // try withdraw before end
    campaign::withdraw_funds<SUI>(&mut c, 1, &clock, test_scenario::ctx(&mut scenario));
    campaign::share_for_testing(c);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

#[test]
#[expected_failure]
fun finalize_before_end_fails() {
    let creator = @0xA;
    let mut scenario = test_scenario::begin(creator);
    let clock = test_clock(test_scenario::ctx(&mut scenario), 1004);
    let mut c = campaign::create_campaign<SUI>(string::utf8(b"Test"), string::utf8(b"Desc"), 100u64, 5_000u64, &clock, test_scenario::ctx(&mut scenario));
    campaign::finalize_campaign<SUI>(&mut c, &clock, test_scenario::ctx(&mut scenario));
    campaign::share_for_testing(c);
    clock::destroy_for_testing(clock);
    test_scenario::end(scenario);
}

// ===== helpers =====

// Minimal testing clock helpers. Using mint_for_testing and a fake adjustable clock pattern.

fun test_clock(ctx: &mut TxContext, seed: u64): Clock {
    let mut clk = clock::create_for_testing(ctx);
    clock::increment_for_testing(&mut clk, seed);
    clk
}

fun advance_clock(clock: &mut Clock, delta_ms: u64) {
    clock::increment_for_testing(clock, delta_ms)
}

