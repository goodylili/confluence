#[test_only]
module confluence::poap_tests;
use std::string::{String, utf8};
use sui::clock;
use sui::test_scenario;

use confluence::poap;

#[test]
fun issue_success_and_getters() {
    let creator = @0xA;
    let recipient = @0xB;

    let mut scenario = test_scenario::begin(creator);

    // Create a test Clock and advance it
    let mut clk = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    clock::increment_for_testing(&mut clk, 42);

    // Dummy campaign id from an address
    let campaign_id: ID = object::id_from_address(@0x100);

    let name: String = utf8(b"Test POAP");
    let description: String = utf8(b"Contribution POAP");
    let url: String = utf8(b"https://example.com/poap.png");

    poap::issue_for_contribution(
        campaign_id,
        recipient,
        name,
        description,
        100,
        url,
        &clk,
        test_scenario::ctx(&mut scenario)
    );

    test_scenario::next_tx(&mut scenario, recipient);

    {
        let poap_nft = test_scenario::take_from_sender<poap::POAPNFT>(&scenario);
        assert!(poap::get_campaign_id(&poap_nft) == campaign_id, 100);
        assert!(std::string::length(&poap::get_name(&poap_nft)) > 0, 101);
        assert!(std::string::length(&poap::get_description(&poap_nft)) > 0, 102);
        assert!(poap::get_amount_contributed(&poap_nft) == 100, 103);
        assert!(std::string::length(&poap::get_url(&poap_nft)) > 0, 104);

        test_scenario::return_to_address<poap::POAPNFT>(recipient, poap_nft);
    };

    clock::destroy_for_testing(clk);

    test_scenario::end(scenario);
}

// ===== Positive boundary validations =====
#[test]
fun issue_min_nonempty_name() {
    let creator = @0xA;
    let recipient = @0xB;
    let mut scenario = test_scenario::begin(creator);
    let clk = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    let campaign_id: ID = object::id_from_address(@0x201);

    poap::issue_for_contribution(
        campaign_id,
        recipient,
        utf8(b"N"), // minimal non-empty name
        utf8(b"desc"),
        1,
        utf8(b"url"),
        &clk,
        test_scenario::ctx(&mut scenario)
    );

    test_scenario::next_tx(&mut scenario, recipient);
    {
        let poap_nft = test_scenario::take_from_sender<poap::POAPNFT>(&scenario);
        assert!(std::string::length(&poap::get_name(&poap_nft)) > 0, 210);
        test_scenario::return_to_address<poap::POAPNFT>(recipient, poap_nft);
    };

    clock::destroy_for_testing(clk);
    test_scenario::end(scenario);
}

#[test]
fun issue_min_nonempty_description() {
    let creator = @0xA;
    let recipient = @0xB;
    let mut scenario = test_scenario::begin(creator);
    let clk = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    let campaign_id: ID = object::id_from_address(@0x202);

    poap::issue_for_contribution(
        campaign_id,
        recipient,
        utf8(b"name"),
        utf8(b"D"), // minimal non-empty description
        1,
        utf8(b"url"),
        &clk,
        test_scenario::ctx(&mut scenario)
    );

    test_scenario::next_tx(&mut scenario, recipient);
    {
        let poap_nft = test_scenario::take_from_sender<poap::POAPNFT>(&scenario);
        assert!(std::string::length(&poap::get_description(&poap_nft)) > 0, 211);
        test_scenario::return_to_address<poap::POAPNFT>(recipient, poap_nft);
    };

    clock::destroy_for_testing(clk);
    test_scenario::end(scenario);
}

#[test]
fun issue_min_nonempty_url() {
    let creator = @0xA;
    let recipient = @0xB;
    let mut scenario = test_scenario::begin(creator);
    let clk = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    let campaign_id: ID = object::id_from_address(@0x203);

    poap::issue_for_contribution(
        campaign_id,
        recipient,
        utf8(b"name"),
        utf8(b"desc"),
        1,
        utf8(b"/"), // minimal non-empty url
        &clk,
        test_scenario::ctx(&mut scenario)
    );

    test_scenario::next_tx(&mut scenario, recipient);
    {
        let poap_nft = test_scenario::take_from_sender<poap::POAPNFT>(&scenario);
        assert!(std::string::length(&poap::get_url(&poap_nft)) > 0, 212);
        test_scenario::return_to_address<poap::POAPNFT>(recipient, poap_nft);
    };

    clock::destroy_for_testing(clk);
    test_scenario::end(scenario);
}

#[test]
fun issue_min_positive_amount() {
    let creator = @0xA;
    let recipient = @0xB;
    let mut scenario = test_scenario::begin(creator);
    let clk = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    let campaign_id: ID = object::id_from_address(@0x204);

    poap::issue_for_contribution(
        campaign_id,
        recipient,
        utf8(b"name"),
        utf8(b"desc"),
        1, // minimal positive amount
        utf8(b"url"),
        &clk,
        test_scenario::ctx(&mut scenario)
    );

    test_scenario::next_tx(&mut scenario, recipient);
    {
        let poap_nft = test_scenario::take_from_sender<poap::POAPNFT>(&scenario);
        assert!(poap::get_amount_contributed(&poap_nft) == 1, 213);
        test_scenario::return_to_address<poap::POAPNFT>(recipient, poap_nft);
    };

    clock::destroy_for_testing(clk);
    test_scenario::end(scenario);
}


#[test]
fun transfer_poap_between_addresses() {
    let creator = @0xA;
    let recipient1 = @0xB;
    let recipient2 = @0xC;

    let mut scenario = test_scenario::begin(creator);
    let clk = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    let campaign_id: ID = object::id_from_address(@0x120);

    poap::issue_for_contribution(
        campaign_id,
        recipient1,
        utf8(b"X"),
        utf8(b"Y"),
        10,
        utf8(b"url"),
        &clk,
        test_scenario::ctx(&mut scenario)
    );

    // Recipient1 takes and transfers to recipient2
    test_scenario::next_tx(&mut scenario, recipient1);
    {
        let poap_nft = test_scenario::take_from_sender<poap::POAPNFT>(&scenario);
        let old_id = poap::get_id(&poap_nft);
        poap::transfer_poap(poap_nft, recipient2);

        // Recipient2 retrieves and verifies same id
        test_scenario::next_tx(&mut scenario, recipient2);
        {
            let poap_nft2 = test_scenario::take_from_sender<poap::POAPNFT>(&scenario);
            assert!(poap::get_id(&poap_nft2) == old_id, 200);
            test_scenario::return_to_address<poap::POAPNFT>(recipient2, poap_nft2);
        };
    };

    clock::destroy_for_testing(clk);
    test_scenario::end(scenario);
}

// ===== Burn test =====
#[test]
fun burn_deletes_poap() {
    let creator = @0xA;
    let recipient = @0xB;

    let mut scenario = test_scenario::begin(creator);
    let clk = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    let campaign_id: ID = object::id_from_address(@0x130);

    poap::issue_for_contribution(
        campaign_id,
        recipient,
        utf8(b"X"),
        utf8(b"Y"),
        10,
        utf8(b"url"),
        &clk,
        test_scenario::ctx(&mut scenario)
    );

    test_scenario::next_tx(&mut scenario, recipient);
    {
        let poap_nft = test_scenario::take_from_sender<poap::POAPNFT>(&scenario);
        poap::burn(poap_nft);
        // Do not attempt to take again; success is not aborting during burn.
    };
    clock::destroy_for_testing(clk);
    test_scenario::end(scenario);
}
