module confluence::events;

use std::{
    string::String,
    type_name::TypeName
};

use sui::event;

// ============ Campaign Lifecycle Events ============

public struct CampaignCreated has copy, drop {
    campaign_id: ID,
    creator: address,
    title: String,
    goal: u64,
    coin_type: TypeName,
    end_timestamp_ms: u64,
    creation_timestamp_ms: u64
}

public struct CampaignUpdated has copy, drop {
    campaign_id: ID,
    updater: address,
    old_title: String,
    new_title: String,
    old_description: String,
    new_description: String,
    timestamp_ms: u64
}

public struct CampaignCancelled has copy, drop {
    campaign_id: ID,
    creator: address,
    reason: String,
    total_raised: u64,
    contributor_count: u64,
    timestamp_ms: u64
}

public struct CampaignFinalized has copy, drop {
    campaign_id: ID,
    status: u8,
    total_raised: u64,
    goal: u64,
    contributor_count: u64,
    timestamp_ms: u64
}

// ============ Funding Lifecycle Events ============

public struct ContributionMade has copy, drop {
    campaign_id: ID,
    contributor: address,
    amount: u64,
    total_raised: u64,
    is_first_contribution: bool,
    remark: String,
    timestamp_ms: u64
}

public struct ContributionRefunded has copy, drop {
    campaign_id: ID,
    contributor: address,
    amount: u64,
    reason: String,
    timestamp_ms: u64
}

// ============ Pause/Unpause Events ============

public struct CampaignPaused has copy, drop {
    campaign_id: ID,
    pauser: address,
    reason: String,
    timestamp_ms: u64
}

public struct CampaignUnpaused has copy, drop {
    campaign_id: ID,
    unpauser: address,
    timestamp_ms: u64
}

// ============ Goal Events ============

public struct GoalReached has copy, drop {
    campaign_id: ID,
    total_raised: u64,
    goal: u64,
    contributor_count: u64,
    time_to_goal_ms: u64,
    timestamp_ms: u64
}

public struct GoalUpdated has copy, drop {
    campaign_id: ID,
    old_goal: u64,
    new_goal: u64,
    current_raised: u64,
    updater: address,
    timestamp_ms: u64
}

public struct MilestoneReached has copy, drop {
    campaign_id: ID,
    milestone_percentage: u64, // 25, 50, 75, 100
    total_raised: u64,
    goal: u64,
    timestamp_ms: u64
}

// ============ Withdrawal Events ============

public struct FundsWithdrawn has copy, drop {
    campaign_id: ID,
    creator: address,
    amount: u64,
    timestamp_ms: u64
}

// ============ Event Emission Functions ============

// Campaign Lifecycle
public(package) fun emit_campaign_created(
    campaign_id: ID,
    creator: address,
    title: String,
    goal: u64,
    coin_type: TypeName,
    end_timestamp_ms: u64,
    creation_timestamp_ms: u64
) {
    event::emit(CampaignCreated {
        campaign_id,
        creator,
        title,
        goal,
        coin_type,
        end_timestamp_ms,
        creation_timestamp_ms
    });
}

public(package) fun emit_campaign_updated(
    campaign_id: ID,
    updater: address,
    old_title: String,
    new_title: String,
    old_description: String,
    new_description: String,
    timestamp_ms: u64
) {
    event::emit(CampaignUpdated {
        campaign_id,
        updater,
        old_title,
        new_title,
        old_description,
        new_description,
        timestamp_ms
    });
}

public(package) fun emit_campaign_cancelled(
    campaign_id: ID,
    creator: address,
    reason: String,
    total_raised: u64,
    contributor_count: u64,
    timestamp_ms: u64
) {
    event::emit(CampaignCancelled {
        campaign_id,
        creator,
        reason,
        total_raised,
        contributor_count,
        timestamp_ms
    });
}

public(package) fun emit_campaign_finalized(
    campaign_id: ID,
    status: u8,
    total_raised: u64,
    goal: u64,
    contributor_count: u64,
    timestamp_ms: u64
) {
    event::emit(CampaignFinalized {
        campaign_id,
        status,
        total_raised,
        goal,
        contributor_count,
        timestamp_ms
    });
}

// Funding Lifecycle
public(package) fun emit_contribution_made(
    campaign_id: ID,
    contributor: address,
    amount: u64,
    total_raised: u64,
    is_first_contribution: bool,
    remark: String,
    timestamp_ms: u64
) {
    event::emit(ContributionMade {
        campaign_id,
        contributor,
        amount,
        total_raised,
        is_first_contribution,
        remark,
        timestamp_ms
    });
}

public(package) fun emit_contribution_refunded(
    campaign_id: ID,
    contributor: address,
    amount: u64,
    reason: String,
    timestamp_ms: u64
) {
    event::emit(ContributionRefunded {
        campaign_id,
        contributor,
        amount,
        reason,
        timestamp_ms
    });
}

// Pause/Unpause
public(package) fun emit_campaign_paused(
    campaign_id: ID,
    pauser: address,
    reason: String,
    timestamp_ms: u64
) {
    event::emit(CampaignPaused {
        campaign_id,
        pauser,
        reason,
        timestamp_ms
    });
}

public(package) fun emit_campaign_unpaused(
    campaign_id: ID,
    unpauser: address,
    timestamp_ms: u64
) {
    event::emit(CampaignUnpaused {
        campaign_id,
        unpauser,
        timestamp_ms
    });
}

// Goal Events
public(package) fun emit_goal_reached(
    campaign_id: ID,
    total_raised: u64,
    goal: u64,
    contributor_count: u64,
    time_to_goal_ms: u64,
    timestamp_ms: u64
) {
    event::emit(GoalReached {
        campaign_id,
        total_raised,
        goal,
        contributor_count,
        time_to_goal_ms,
        timestamp_ms
    });
}

public(package) fun emit_goal_updated(
    campaign_id: ID,
    old_goal: u64,
    new_goal: u64,
    current_raised: u64,
    updater: address,
    timestamp_ms: u64
) {
    event::emit(GoalUpdated {
        campaign_id,
        old_goal,
        new_goal,
        current_raised,
        updater,
        timestamp_ms
    });
}

public(package) fun emit_milestone_reached(
    campaign_id: ID,
    milestone_percentage: u64,
    total_raised: u64,
    goal: u64,
    timestamp_ms: u64
) {
    event::emit(MilestoneReached {
        campaign_id,
        milestone_percentage,
        total_raised,
        goal,
        timestamp_ms
    });
}

// Withdrawal
public(package) fun emit_funds_withdrawn(
    campaign_id: ID,
    creator: address,
    amount: u64,
    timestamp_ms: u64
) {
    event::emit(FundsWithdrawn {
        campaign_id,
        creator,
        amount,
        timestamp_ms
    });
}