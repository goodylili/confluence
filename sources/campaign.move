module confluence::campaign;

use std::{
    string::{Self, String},
    type_name::{Self, TypeName}
};

use sui::{
    clock::{Self, Clock},
    sui::SUI,
    coin::{Self, Coin},
};

use usdc::usdc::USDC;

use confluence::{
    funding::{Self, Fund},
    poap,
    events
};

// ====== CAMPAIGN STATUSES ======
const STATUS_ACTIVE: u8 = 1;
const STATUS_PAUSED: u8 = 2;
const STATUS_SUCCESSFUL: u8 = 3;
const STATUS_FAILED: u8 = 4;
const STATUS_CANCELLED: u8 = 5;
const STATUS_WITHDRAWN: u8 = 6;

// ====== ERROR CONSTANTS ======
const EUnsupportedCoinType: u64 = 1;
const ENotCreator: u64 = 2;
const ECampaignNotActive: u64 = 3;
const ECampaignExpired: u64 = 4;
const ECampaignNotExpired: u64 = 5;
const ECampaignPaused: u64 = 6;
const ECampaignNotPaused: u64 = 7;
const ECampaignAlreadyFinalized: u64 = 8;
const EGoalAlreadyReached: u64 = 9;
const EInvalidGoal: u64 = 10;
const EEmptyTitle: u64 = 11;
const EEmptyDescription: u64 = 12;
const EInvalidDuration: u64 = 13;
const EInsufficientBalance: u64 = 14;
const EFundsAlreadyWithdrawn: u64 = 15;
const ENoContributions: u64 = 16;
const EArithmeticOverflow: u64 = 17;
const EReentrancyGuard: u64 = 18;
const EInvalidWithdrawalAmount: u64 = 19;
const EWithdrawalExceedsBalance: u64 = 20;
const EInvalidContributor: u64 = 21;
const EInvalidUrl: u64 = 22;

public struct Campaign<phantom T> has key {
    id: UID,
    creator: address,
    title: String,
    coin_type: TypeName,
    description: String,
    profile_url: String,
    background_url: String,
    goal: u64,
    funding: Fund<T>,
    end: u64,
    creation_timestamp_ms: u64,
    status: u8,
    total_withdrawn: u64,
    locked: bool,
    poaps_issued: bool
}

public struct AdminCap has key, store {
    id: UID,
    campaign_id: ID
}

fun assert_admin<T>(admin: &AdminCap, campaign: &Campaign<T>) {
    assert!(admin.campaign_id == object::uid_to_inner(&campaign.id), ENotCreator);
}

public fun grant_admin<T>(campaign: &Campaign<T>, admin: &AdminCap, new_admin: address, ctx: &mut TxContext) {
    assert_admin(admin, campaign);
    let cap = AdminCap { id: object::new(ctx), campaign_id: object::uid_to_inner(&campaign.id) };
    transfer::public_transfer(cap, new_admin);
}

public fun create_campaign<T>(
    title: String,
    description: String,
    goal: u64,
    duration_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext
): (Campaign<T>, AdminCap) {
    // Comprehensive input validation
    assert!(string::length(&title) > 0, EEmptyTitle);
    assert!(string::length(&title) <= 100, EInvalidGoal); // Max title length
    assert!(string::length(&description) > 0, EEmptyDescription);
    assert!(string::length(&description) <= 1000, EInvalidGoal); // Max description length
    
    assert!(goal > 0, EInvalidGoal);
    assert!(goal <= 1000000000000000000u64, EInvalidGoal); // Max goal: 1B tokens (18 decimals)
    
    // Enhanced duration validation
    assert!(duration_ms > 0, EInvalidDuration);
    assert!(duration_ms >= 1000, EInvalidDuration); // Min 1 second
    assert!(duration_ms <= 31536000000, EInvalidDuration); // Max 1 year (365 * 24 * 60 * 60 * 1000)
    
    let creation_time = clock::timestamp_ms(clock);
    
    // Validate end time doesn't overflow
    let max_timestamp = 18446744073709551615u64; // u64::MAX
    assert!(creation_time <= max_timestamp - duration_ms, EArithmeticOverflow);
    
    let coin_type = type_name::with_defining_ids<T>();

    // Assert T is either SUI or USDC
    let sui_type = type_name::with_defining_ids<SUI>();
    let usdc_type = type_name::with_defining_ids<USDC>();

    if (&coin_type != &sui_type && &usdc_type != &coin_type) {
        abort EUnsupportedCoinType
    };

    // Create the fund via funding module
    let funding = funding::create<T>(ctx);

    // Prepare campaign id and creator
    let uid = object::new(ctx);
    let sender = ctx.sender();

    // Create campaign with the fund
    let campaign = Campaign<T> {
        id: uid,
        creator: sender,
        title,
        coin_type: coin_type,
        description,
        profile_url: string::utf8(b""),
        background_url: string::utf8(b""),
        goal,
        funding,
        end: creation_time + duration_ms,
        creation_timestamp_ms: creation_time,
        status: STATUS_ACTIVE,
        total_withdrawn: 0,
        locked: false,
        poaps_issued: false
    };

    // Mint AdminCap for creator (returned to caller)
    let admin_cap = AdminCap { id: object::new(ctx), campaign_id: object::uid_to_inner(&campaign.id) };

    (campaign, admin_cap)
}


// Example: Make campaign a shared object
public fun create_and_share_campaign<T>(
    title: String,
    description: String,
    goal: u64,
    duration_ms: u64,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let (campaign, admin_cap) = create_campaign<T>(
        title,
        description,
        goal,
        duration_ms,
        clock,
        ctx
    );

    // transfer the admin cap to the creator, and share the campaign
    transfer::public_transfer(admin_cap, ctx.sender());
    transfer::share_object(campaign);
}

// Testing helper: allow tests to share a locally created campaign object
public fun share_for_testing<T>(campaign: Campaign<T>) {
    transfer::share_object(campaign);
}

// ====== CAMPAIGN UPDATE FUNCTIONS ======

/// Update campaign title
public fun update_title<T>(
    campaign: &mut Campaign<T>,
    admin:  &AdminCap,
    new_title: String,
    clock: &Clock,
) {
    // Validate caller is admin via capability
    assert_admin(admin, campaign);

    // Validate campaign is active and not expired
    assert!(campaign.status == STATUS_ACTIVE, ECampaignNotActive);
    assert!(clock::timestamp_ms(clock) < campaign.end, ECampaignExpired);

    // Validate title is not empty
    assert!(string::length(&new_title) > 0, EEmptyTitle);

    campaign.title = new_title;

    let cid = object::uid_to_inner(&campaign.id);
    let ts = clock::timestamp_ms(clock);
    events::emit_campaign_updated(
        cid,
        string::utf8(b"title"),
        ts,
    );
}

/// Update campaign description
public fun update_description<T>(
    campaign: &mut Campaign<T>,
    admin: &AdminCap,
    new_description: String,
    clock: &Clock,
) {
    // Validate caller is admin via capability
    assert_admin(admin, campaign);

    // Validate campaign is active and not expired
    assert!(campaign.status == STATUS_ACTIVE, ECampaignNotActive);
    assert!(clock::timestamp_ms(clock) < campaign.end, ECampaignExpired);

    // Validate description is not empty
    assert!(string::length(&new_description) > 0, EEmptyDescription);

    campaign.description = new_description;

    let cid = object::uid_to_inner(&campaign.id);
    let ts = clock::timestamp_ms(clock);
    events::emit_campaign_updated(
        cid,
        string::utf8(b"description"),
        ts,
    );
}

/// Update campaign profile picture URL
public fun set_profile_url<T>(
    campaign: &mut Campaign<T>,
    admin: &AdminCap,
    new_profile_url: String,
    clock: &Clock,
) {
    // Validate caller is admin via capability
    assert_admin(admin, campaign);

    // Validate campaign is active and not expired
    assert!(campaign.status == STATUS_ACTIVE, ECampaignNotActive);
    assert!(clock::timestamp_ms(clock) < campaign.end, ECampaignExpired);

    // Basic URL validations: non-empty and reasonable max length
    let profile_len = string::length(&new_profile_url);
    assert!(profile_len > 0, EInvalidUrl);
    assert!(profile_len <= 2048, EInvalidUrl);

    // Apply update
    campaign.profile_url = new_profile_url;

    let cid = object::uid_to_inner(&campaign.id);
    let ts = clock::timestamp_ms(clock);
    events::emit_campaign_updated(
        cid,
        string::utf8(b"profile_url"),
        ts,
    );
}

/// Update campaign background URL
public fun set_background_url<T>(
    campaign: &mut Campaign<T>,
    admin: &AdminCap,
    new_background_url: String,
    clock: &Clock,
) {
    // Validate caller is admin via capability
    assert_admin(admin, campaign);

    // Validate campaign is active and not expired
    assert!(campaign.status == STATUS_ACTIVE, ECampaignNotActive);
    assert!(clock::timestamp_ms(clock) < campaign.end, ECampaignExpired);

    // Basic URL validations: non-empty and reasonable max length
    let background_len = string::length(&new_background_url);
    assert!(background_len > 0, EInvalidUrl);
    assert!(background_len <= 2048, EInvalidUrl);

    // Apply update
    campaign.background_url = new_background_url;

    let cid = object::uid_to_inner(&campaign.id);
    let ts = clock::timestamp_ms(clock);
    events::emit_campaign_updated(
        cid,
        string::utf8(b"background_url"),
        ts,
    );
}

/// Update campaign goal (only creator, only if campaign is active and not expired)
public fun update_goal<T>(
    campaign: &mut Campaign<T>,
    admin: &AdminCap,
    new_goal: u64,
    clock: &Clock,
) {
    // Reentrancy protection
    assert!(!campaign.locked, EReentrancyGuard);
    campaign.locked = true;
    
    // Validate caller is admin via capability
    assert_admin(admin, campaign);

    // Validate campaign can be updated
    assert!(can_be_updated(campaign, clock), ECampaignExpired);

    // Enhanced input validation with overflow protection
    assert!(new_goal > 0, EInvalidGoal);
    assert!(new_goal <= 1000000000000000000u64, EInvalidGoal); // Max goal: 1B tokens (18 decimals)
    
    // Ensure new goal is reasonable compared to current funding
    let current_raised = funding::get_balance(&campaign.funding);
    
    // Prevent setting goal below current raised amount (would make campaign instantly successful)
    assert!(new_goal >= current_raised, EInvalidGoal);
    
    // Prevent arithmetic overflow in future calculations
    let max_safe_goal = 18446744073709551615u64 / 100; // Ensure percentage calculations won't overflow
    assert!(new_goal <= max_safe_goal, EArithmeticOverflow);

    let old_goal = campaign.goal;
    campaign.goal = new_goal;

    // Check if goal is now reached with new value
    let ts = clock::timestamp_ms(clock);
    let cid = object::uid_to_inner(&campaign.id);
    events::emit_goal_updated(
        cid,
        old_goal,
        new_goal,
        current_raised,
        campaign.creator,
        ts,
    );

    if (current_raised >= new_goal && campaign.status == STATUS_ACTIVE) {
        let old_status = campaign.status;
        campaign.status = STATUS_SUCCESSFUL;
        events::emit_campaign_status_changed(
            cid,
            old_status,
            campaign.status,
            ts,
        );
        let contributor_count = funding::get_contributor_count(&campaign.funding);
        let time_to_goal = ts - campaign.creation_timestamp_ms;
        events::emit_goal_reached(
            cid,
            current_raised,
            new_goal,
            contributor_count,
            time_to_goal,
            ts,
        );
    };

    
    // Release lock
    campaign.locked = false;
}

// ====== CAMPAIGN STATUS MANAGEMENT ======

/// Pause campaign (only creator can pause)
public fun pause_campaign<T>(
    campaign: &mut Campaign<T>,
    admin: &AdminCap,
    reason: String,
    clock: &Clock,
    ctx: &mut TxContext
) {
    // Reentrancy protection
    assert!(!campaign.locked, EReentrancyGuard);
    campaign.locked = true;
    
    // Validate caller is admin via capability
    assert_admin(admin, campaign);

    // Validate campaign is currently active
    assert!(campaign.status == STATUS_ACTIVE, ECampaignNotActive);
    
    // Validate reason is not empty for audit trail
    assert!(string::length(&reason) > 0, EEmptyDescription);

    // Update status to paused
    let old_status = campaign.status;
    campaign.status = STATUS_PAUSED;

    let cid = object::uid_to_inner(&campaign.id);
    let ts = clock::timestamp_ms(clock);
    events::emit_campaign_paused(
        cid,
        campaign.creator,
        reason,
        ts,
    );
    events::emit_campaign_status_changed(
        cid,
        old_status,
        campaign.status,
        ts,
    );
    
    // Release lock before external calls
    campaign.locked = false;
}

/// Unpause campaign (only creator can unpause)
public fun unpause_campaign<T>(
    campaign: &mut Campaign<T>,
    admin: &AdminCap,
    clock: &Clock,
    ctx: &mut TxContext
) {
    // Reentrancy protection
    assert!(!campaign.locked, EReentrancyGuard);
    campaign.locked = true;
    
    // Validate caller is admin via capability
    assert_admin(admin, campaign);

    // Validate campaign is currently paused
    assert!(campaign.status == STATUS_PAUSED, ECampaignNotPaused);

    // Validate campaign hasn't expired
    assert!(clock::timestamp_ms(clock) < campaign.end, ECampaignExpired);

    // Update status to active
    let old_status = campaign.status;
    campaign.status = STATUS_ACTIVE;

    let cid = object::uid_to_inner(&campaign.id);
    let ts = clock::timestamp_ms(clock);
    events::emit_campaign_unpaused(
        cid,
        campaign.creator,
        ts,
    );
    events::emit_campaign_status_changed(
        cid,
        old_status,
        campaign.status,
        ts,
    );
    
    // Release lock before external calls
    campaign.locked = false;
}

/// Cancel campaign and refund all contributors
public fun cancel_campaign<T>(
    campaign: &mut Campaign<T>,
    admin: &AdminCap,
    reason: String,
    clock: &Clock,
    ctx: &mut TxContext
) {
    // Reentrancy protection
    assert!(!campaign.locked, EReentrancyGuard);
    campaign.locked = true;
    
    // Validate caller is admin via capability
    assert_admin(admin, campaign);

    // Validate campaign is not already finalized to a terminal state
    // Allow finalization when goal was reached earlier (STATUS_SUCCESSFUL pre-finalization)
    assert!(
        campaign.status != STATUS_FAILED &&
            campaign.status != STATUS_CANCELLED &&
            campaign.status != STATUS_WITHDRAWN,
        ECampaignAlreadyFinalized
    );
    
    // Validate reason is not empty for audit trail
    assert!(string::length(&reason) > 0, EEmptyDescription);

    let total_raised = funding::get_balance(&campaign.funding);

    // Refund all contributors
    if (total_raised > 0) {
        funding::refund_all_contributors(&mut campaign.funding, ctx);
    };

    // Update status to cancelled
    let old_status = campaign.status;
    campaign.status = STATUS_CANCELLED;

    let cid = object::uid_to_inner(&campaign.id);
    let ts = clock::timestamp_ms(clock);
    let contributor_count = funding::get_contributor_count(&campaign.funding);
    events::emit_campaign_cancelled(
        cid,
        campaign.creator,
        reason,
        total_raised,
        contributor_count,
        ts,
    );
    events::emit_campaign_status_changed(
        cid,
        old_status,
        campaign.status,
        ts,
    );
    
    // Release lock before external calls
    campaign.locked = false;
}

/// Finalize campaign (determine success or failure) - Only creator can finalize
public fun finalize_campaign<T>(
    campaign: &mut Campaign<T>,
    admin: &AdminCap,
    clock: &Clock,
    ctx: &mut TxContext
) {
    // Reentrancy protection
    assert!(!campaign.locked, EReentrancyGuard);
    campaign.locked = true;
    
    // Strict access control - only admin via capability
    assert_admin(admin, campaign);
    
    // Validate campaign has expired
    let current_time = clock::timestamp_ms(clock);
    assert!(current_time >= campaign.end, ECampaignNotExpired);

    // Validate campaign is not already finalized to a terminal state
    // Allow finalization even if status is SUCCESSFUL from prior contributions
    assert!(
            campaign.status != STATUS_FAILED &&
            campaign.status != STATUS_CANCELLED &&
            campaign.status != STATUS_WITHDRAWN,
        ECampaignAlreadyFinalized
    );

    let total_raised = funding::get_balance(&campaign.funding);

    // Determine final status based on goal achievement
    let final_status = if (total_raised >= campaign.goal) {
        STATUS_SUCCESSFUL
    } else {
        // Refund all contributors if campaign failed
        if (total_raised > 0) {
            funding::refund_all_contributors(&mut campaign.funding, ctx);
        };
        STATUS_FAILED
    };

    // Atomic state transition
    let old_status = campaign.status;
    campaign.status = final_status;
    
    // Release lock before external calls
    campaign.locked = false;

    // Emit finalization and status change
    let cid = object::uid_to_inner(&campaign.id);
    let contributor_count = funding::get_contributor_count(&campaign.funding);
    events::emit_campaign_finalized(
        cid,
        final_status,
        total_raised,
        campaign.goal,
        contributor_count,
        current_time,
    );
    events::emit_campaign_status_changed(
        cid,
        old_status,
        campaign.status,
        current_time,
    );

    // If finalized as successful, issue POAPs once and emit goal reached
    if (final_status == STATUS_SUCCESSFUL && !campaign.poaps_issued) {
        let count = funding::get_contributor_count(&campaign.funding);
        let mut i = 0u64;
        let cid = object::uid_to_inner(&campaign.id);
        let time_to_goal = current_time - campaign.creation_timestamp_ms;
        events::emit_goal_reached(
            cid,
            total_raised,
            campaign.goal,
            count,
            time_to_goal,
            current_time,
        );
        while (i < count) {
            let addr = funding::get_contributor_at(&campaign.funding, i);
            let amt = funding::get_contributor_total(&campaign.funding, addr);
            if (amt > 0) {
                poap::issue_for_contribution(
                    cid,
                    addr,
                    string::utf8(b"Campaign POAP"),
                    string::utf8(b"Proof of Contribution"),
                    amt,
                    string::utf8(b"https://confluence.app"),
                    clock,
                    ctx
                );
            };
            i = i + 1;
        };
        campaign.poaps_issued = true;
    };
}

// ====== CONTRIBUTION FUNCTIONS ======

/// Contribute to a campaign
public fun contribute<T>(
    campaign: &mut Campaign<T>,
    payment: Coin<T>,
    remark: String,
    clock: &Clock,
    ctx: &mut TxContext
) {
    // Reentrancy protection
    assert!(!campaign.locked, EReentrancyGuard);
    campaign.locked = true;
    
    // Validate campaign is active and not paused
    assert!(campaign.status == STATUS_ACTIVE, ECampaignNotActive);
    assert!(campaign.status != STATUS_PAUSED, ECampaignPaused);

    // Validate campaign hasn't expired
    let current_time = clock::timestamp_ms(clock);
    assert!(current_time < campaign.end, ECampaignExpired);

    // Enhanced input validation
    let amount = coin::value(&payment);
    assert!(amount > 0, EInsufficientBalance); // Prevent zero contributions
    assert!(amount <= 1000000000000000000u64, EArithmeticOverflow); // Max contribution limit
    
    // Validate remark length
    assert!(string::length(&remark) <= 500, EEmptyDescription); // Max remark length
    
    // Atomic goal checking - get current balance and validate in single operation
    let current_raised = funding::get_balance(&campaign.funding);
    
    // Check if goal is already reached - prevent over-contributions
    assert!(current_raised < campaign.goal, EGoalAlreadyReached);
    
    // Validate contribution doesn't cause overflow
    assert!(current_raised <= campaign.goal - amount, EArithmeticOverflow);

    let contributor = ctx.sender();
    let was_contributor = funding::is_contributor(&campaign.funding, contributor);

    // Add contribution to fund (atomic operation)
    funding::add_contribution(
        &mut campaign.funding,
        contributor,
        payment,
        remark,
        current_time
    );

    // Get updated balance after contribution (atomic read)
    let new_total_raised = funding::get_balance(&campaign.funding);
    let cid = object::uid_to_inner(&campaign.id);
    let ts = current_time;
    events::emit_contribution_made(
        cid,
        contributor,
        amount,
        new_total_raised,
        !was_contributor,
        remark,
        ts,
    );

    // Atomic goal check and status update
    if (current_raised < campaign.goal && new_total_raised >= campaign.goal) {
        // Automatically set campaign status to successful when goal is met
        let old_status = campaign.status;
        campaign.status = STATUS_SUCCESSFUL;
        events::emit_campaign_status_changed(
            cid,
            old_status,
            campaign.status,
            ts,
        );
        let count = funding::get_contributor_count(&campaign.funding);
        let time_to_goal = ts - campaign.creation_timestamp_ms;
        events::emit_goal_reached(
            cid,
            new_total_raised,
            campaign.goal,
            count,
            time_to_goal,
            ts,
        );
    };

    
    // Release lock before external calls
    campaign.locked = false;

    // Issue POAPs once when campaign becomes successful
    if (campaign.status == STATUS_SUCCESSFUL && !campaign.poaps_issued) {
        let count = funding::get_contributor_count(&campaign.funding);
        let mut i = 0u64;
        let cid = object::uid_to_inner(&campaign.id);
        while (i < count) {
            let addr = funding::get_contributor_at(&campaign.funding, i);
            let amt = funding::get_contributor_total(&campaign.funding, addr);
            if (amt > 0) {
                poap::issue_for_contribution(
                    cid,
                    addr,
                    string::utf8(b"Campaign POAP"),
                    string::utf8(b"Proof of Contribution"),
                    amt,
                    string::utf8(b"https://confluence.app"),
                    clock,
                    ctx
                );
            };
            i = i + 1;
        };
        campaign.poaps_issued = true;
    };
}

/// Refund a contributor (only if campaign is cancelled or failed)
public fun refund_contributor<T>(
    campaign: &mut Campaign<T>,
    contributor: address,
    reason: String,
    clock: &Clock,
    ctx: &mut TxContext
) {
    // Only allow refunds if campaign is cancelled or failed
    assert!(
        campaign.status == STATUS_CANCELLED || campaign.status == STATUS_FAILED,
        ECampaignNotActive
    );

    // Validate contributor has contributions
    assert!(funding::is_contributor(&campaign.funding, contributor), ENoContributions);

    // Validate reason is not empty for audit trail
    assert!(string::length(&reason) > 0, EEmptyDescription);

    // Withdraw contribution and assert a positive refund
    let refunded = funding::withdraw_contribution(&mut campaign.funding, contributor, ctx);
    assert!(refunded > 0, EInvalidWithdrawalAmount);

    let cid = object::uid_to_inner(&campaign.id);
    let ts = clock::timestamp_ms(clock);
    events::emit_contribution_refunded(
        cid,
        contributor,
        refunded,
        reason,
        ts,
    );
}

// ====== WITHDRAWAL FUNCTIONS ======

/// Withdraw funds from campaign after time elapsed (only creator)
public fun withdraw_funds<T>(
    campaign: &mut Campaign<T>,
    admin: &AdminCap,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext
) {
    // Reentrancy protection
    assert!(!campaign.locked, EReentrancyGuard);
    campaign.locked = true;
    
    // Validate caller is admin via capability
    assert_admin(admin, campaign);

    // Validate campaign time has elapsed
    let current_time = clock::timestamp_ms(clock);
    assert!(current_time >= campaign.end, ECampaignNotExpired);

    // Validate campaign is not paused
    assert!(campaign.status != STATUS_PAUSED, ECampaignPaused);

    // Validate funds haven't been withdrawn yet
    assert!(campaign.status != STATUS_WITHDRAWN, EFundsAlreadyWithdrawn);

    // Validate campaign is not cancelled (cancelled campaigns should refund contributors)
    assert!(campaign.status != STATUS_CANCELLED, ECampaignAlreadyFinalized);

    let total_raised = funding::get_balance(&campaign.funding);

    // Validate there are funds to withdraw
    assert!(total_raised > 0, ENoContributions);

    // Enhanced input validation with overflow protection
    assert!(amount > 0, EInvalidWithdrawalAmount);
    assert!(amount <= total_raised, EWithdrawalExceedsBalance);
    let fund_balance = funding::get_balance(&campaign.funding);
    assert!(fund_balance >= amount, EInsufficientBalance);
    
    // Check for overflow before addition - use safe math
    let remaining_capacity = 18446744073709551615u64 - campaign.total_withdrawn; // u64::MAX - total_withdrawn
    assert!(amount <= remaining_capacity, EArithmeticOverflow);
    
    // Additional validation: ensure withdrawal doesn't exceed what's actually available
    assert!(campaign.total_withdrawn + amount <= total_raised, EWithdrawalExceedsBalance);

    // Withdraw from fund and update tracking atomically
    let withdrawal_coin = funding::withdraw_for_creator(&mut campaign.funding, amount, ctx);
    campaign.total_withdrawn = campaign.total_withdrawn + amount;

    // Update status if all funds withdrawn
    let cid = object::uid_to_inner(&campaign.id);
    let ts = clock::timestamp_ms(clock);
    events::emit_funds_withdrawn(
        cid,
        campaign.creator,
        amount,
        ts,
    );
    if (campaign.total_withdrawn == total_raised) {
        let old_status = campaign.status;
        campaign.status = STATUS_WITHDRAWN;
        events::emit_campaign_status_changed(
            cid,
            old_status,
            campaign.status,
            ts,
        );
    };
    
    // Release lock before external transfer
    campaign.locked = false;
    
    // Transfer to creator (external interaction last)
    transfer::public_transfer(withdrawal_coin, campaign.creator);
}

/// Emergency refund function for specific contributors (creator only, with restrictions)
public fun emergency_refund<T>(
    campaign: &mut Campaign<T>,
    admin: &AdminCap,
    contributor: address,
    reason: String,
    _clock: &Clock,
    ctx: &mut TxContext
) {
    // Reentrancy protection
    assert!(!campaign.locked, EReentrancyGuard);
    campaign.locked = true;
    
    // Validate caller is admin via capability
    assert_admin(admin, campaign);
    
    // Restrict emergency refunds to specific campaign states only
    assert!(
        campaign.status == STATUS_ACTIVE || 
        campaign.status == STATUS_PAUSED ||
        campaign.status == STATUS_CANCELLED ||
        campaign.status == STATUS_FAILED,
        ECampaignAlreadyFinalized
    );
    
    // Prevent emergency refunds after campaign is successful and funds withdrawn
    assert!(campaign.status != STATUS_WITHDRAWN, EFundsAlreadyWithdrawn);

    // Validate contributor has contributions
    assert!(funding::is_contributor(&campaign.funding, contributor), ENoContributions);
    
    // Validate reason is not empty for audit trail
    assert!(string::length(&reason) > 0, EEmptyDescription);
    
    // Additional validation: prevent self-refund by creator
    assert!(contributor != campaign.creator, EInvalidContributor);

    // Withdraw contribution and assert a positive refund
    let refund_amount = funding::withdraw_contribution(&mut campaign.funding, contributor, ctx);
    assert!(refund_amount > 0, EInvalidWithdrawalAmount);

    let cid = object::uid_to_inner(&campaign.id);
    let ts = clock::timestamp_ms(_clock);
    events::emit_contribution_refunded(
        cid,
        contributor,
        refund_amount,
        reason,
        ts,
    );

    // Release lock before external calls
    campaign.locked = false;
}

// ====== GETTER FUNCTIONS ======

/// Get campaign ID
public fun get_id<T>(campaign: &Campaign<T>): ID {
    object::uid_to_inner(&campaign.id)
}

/// Get campaign creator
public fun get_creator<T>(campaign: &Campaign<T>): address {
    campaign.creator
}

/// Get campaign title
public fun get_title<T>(campaign: &Campaign<T>): String {
    campaign.title
}

/// Get campaign description
public fun get_description<T>(campaign: &Campaign<T>): String {
    campaign.description
}

/// Get campaign profile picture URL
public fun get_profile_url<T>(campaign: &Campaign<T>): String {
    campaign.profile_url
}

/// Get campaign background URL
public fun get_background_url<T>(campaign: &Campaign<T>): String {
    campaign.background_url
}

/// Get campaign goal
public fun get_goal<T>(campaign: &Campaign<T>): u64 {
    campaign.goal
}

/// Get campaign coin type
public fun get_coin_type<T>(campaign: &Campaign<T>): TypeName {
    campaign.coin_type
}

/// Get campaign end timestamp
public fun get_end_timestamp<T>(campaign: &Campaign<T>): u64 {
    campaign.end
}

/// Get campaign creation timestamp
public fun get_creation_timestamp<T>(campaign: &Campaign<T>): u64 {
    campaign.creation_timestamp_ms
}

/// Get campaign status
public fun get_status<T>(campaign: &Campaign<T>): u8 {
    campaign.status
}

/// Get total amount raised
public fun get_total_raised<T>(campaign: &Campaign<T>): u64 {
    funding::get_balance(&campaign.funding)
}

/// Get number of contributors
public fun get_contributor_count<T>(campaign: &Campaign<T>): u64 {
    funding::get_contributor_count(&campaign.funding)
}

/// Get contributor's total contribution
public fun get_contributor_total<T>(campaign: &Campaign<T>, contributor: address): u64 {
    funding::get_contributor_total(&campaign.funding, contributor)
}

/// Check if address is a contributor
public fun is_contributor<T>(campaign: &Campaign<T>, contributor: address): bool {
    funding::is_contributor(&campaign.funding, contributor)
}

/// Get contributor's number of contributions
public fun get_contributor_contribution_count<T>(campaign: &Campaign<T>, contributor: address): u64 {
    funding::get_contribution_count(&campaign.funding, contributor)
}

/// Get campaign progress percentage (0-100)
public fun get_progress_percentage<T>(campaign: &Campaign<T>): u64 {
    let total_raised = funding::get_balance(&campaign.funding);
    if (campaign.goal == 0) {
        return 0
    };
    (total_raised * 100) / campaign.goal
}

/// Get remaining time in milliseconds (0 if expired)
public fun get_remaining_time<T>(campaign: &Campaign<T>, clock: &Clock): u64 {
    let current_time = clock::timestamp_ms(clock);
    if (current_time >= campaign.end) {
        return 0
    };
    campaign.end - current_time
}

/// Get time elapsed since creation in milliseconds
public fun get_elapsed_time<T>(campaign: &Campaign<T>, clock: &Clock): u64 {
    let current_time = clock::timestamp_ms(clock);
    if (current_time <= campaign.creation_timestamp_ms) {
        return 0
    };
    current_time - campaign.creation_timestamp_ms
}

// ====== HELPER FUNCTIONS ======

/// Check if campaign is active and accepting contributions
public fun is_active<T>(campaign: &Campaign<T>, clock: &Clock): bool {
    campaign.status == STATUS_ACTIVE && clock::timestamp_ms(clock) < campaign.end
}

/// Check if campaign has expired
public fun is_expired<T>(campaign: &Campaign<T>, clock: &Clock): bool {
    clock::timestamp_ms(clock) >= campaign.end
}

/// Check if campaign is paused
public fun is_paused<T>(campaign: &Campaign<T>): bool {
    campaign.status == STATUS_PAUSED
}

/// Check if campaign is successful
public fun is_successful<T>(campaign: &Campaign<T>): bool {
    campaign.status == STATUS_SUCCESSFUL
}

/// Check if campaign has failed
public fun is_failed<T>(campaign: &Campaign<T>): bool {
    campaign.status == STATUS_FAILED
}

/// Check if campaign is cancelled
public fun is_cancelled<T>(campaign: &Campaign<T>): bool {
    campaign.status == STATUS_CANCELLED
}

/// Check if funds have been withdrawn
public fun is_withdrawn<T>(campaign: &Campaign<T>): bool {
    campaign.status == STATUS_WITHDRAWN
}

/// Check if campaign goal has been reached
public fun is_goal_reached<T>(campaign: &Campaign<T>): bool {
    funding::get_balance(&campaign.funding) >= campaign.goal
}

/// Check if campaign is finalized (successful, failed, cancelled, or withdrawn)
public fun is_finalized<T>(campaign: &Campaign<T>): bool {
    campaign.status == STATUS_SUCCESSFUL ||
        campaign.status == STATUS_FAILED ||
        campaign.status == STATUS_CANCELLED ||
        campaign.status == STATUS_WITHDRAWN
}

/// Validate campaign can accept contributions
public fun can_accept_contributions<T>(campaign: &Campaign<T>, clock: &Clock): bool {
    campaign.status == STATUS_ACTIVE &&
        campaign.status != STATUS_PAUSED &&
        clock::timestamp_ms(clock) < campaign.end &&
        !is_goal_reached(campaign)
}

/// Validate campaign can be updated
public fun can_be_updated<T>(campaign: &Campaign<T>, clock: &Clock): bool {
    campaign.status == STATUS_ACTIVE &&
        clock::timestamp_ms(clock) < campaign.end
}

/// Validate campaign can be finalized
public fun can_be_finalized<T>(campaign: &Campaign<T>, clock: &Clock): bool {
    !is_finalized(campaign) &&
        (clock::timestamp_ms(clock) >= campaign.end || is_goal_reached(campaign))
}

/// Get status as string for display purposes
public fun get_status_string<T>(campaign: &Campaign<T>): String {
    if (campaign.status == STATUS_ACTIVE) {
        string::utf8(b"Active")
    } else if (campaign.status == STATUS_PAUSED) {
        string::utf8(b"Paused")
    } else if (campaign.status == STATUS_SUCCESSFUL) {
        string::utf8(b"Successful")
    } else if (campaign.status == STATUS_FAILED) {
        string::utf8(b"Failed")
    } else if (campaign.status == STATUS_CANCELLED) {
        string::utf8(b"Cancelled")
    } else if (campaign.status == STATUS_WITHDRAWN) {
        string::utf8(b"Withdrawn")
    } else {
        string::utf8(b"Unknown")
    }
}

/// Validate input parameters for campaign creation
public fun validate_creation_params(
    title: &String,
    description: &String,
    goal: u64,
    duration_ms: u64
) {
    assert!(string::length(title) > 0, EEmptyTitle);
    assert!(string::length(description) > 0, EEmptyDescription);
    assert!(goal > 0, EInvalidGoal);
    assert!(duration_ms > 0, EInvalidDuration);
}