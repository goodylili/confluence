module confluence::events;
use sui::event;

// ====== CAMPAIGN EVENTS ======
public struct CampaignCreated has copy, drop {
    campaign_id: ID,
    creator: address,
    title: vector<u8>,
    description: vector<u8>,
    goal: u64,
    timestamp: u64,
}

public struct CampaignUpdated has copy, drop {
    campaign_id: ID,
    field: vector<u8>,
    timestamp: u64,
}

public struct CampaignStatusChanged has copy, drop {
    campaign_id: ID,
    old_status: u8,
    new_status: u8,
    timestamp: u64,
}

public struct CampaignPaused has copy, drop {
    campaign_id: ID,
    creator: address,
    reason: vector<u8>,
    timestamp: u64,
}

public struct CampaignUnpaused has copy, drop {
    campaign_id: ID,
    creator: address,
    timestamp: u64,
}

public struct CampaignCancelled has copy, drop {
    campaign_id: ID,
    creator: address,
    reason: vector<u8>,
    total_raised: u64,
    contributor_count: u64,
    timestamp: u64,
}

public struct CampaignFinalized has copy, drop {
    campaign_id: ID,
    final_status: u8,
    total_raised: u64,
    goal: u64,
    contributor_count: u64,
    timestamp: u64,
}

// ====== FUNDING EVENTS ======
public struct ContributionMade has copy, drop {
    campaign_id: ID,
    contributor: address,
    amount: u64,
    timestamp: u64,
}

public struct FundsWithdrawn has copy, drop {
    campaign_id: ID,
    recipient: address,
    amount: u64,
    timestamp: u64,
}

public struct RefundIssued has copy, drop {
    campaign_id: ID,
    contributor: address,
    amount: u64,
    timestamp: u64,
}

// ====== GOAL TRACKING EVENTS ======
public struct GoalReached has copy, drop {
    campaign_id: ID,
    final_amount: u64,
    goal: u64,
    contributor_count: u64,
    time_to_goal: u64,
    timestamp: u64,
}

public struct MilestoneReached has copy, drop {
    campaign_id: ID,
    milestone_percentage: u64,
    current_amount: u64,
    goal: u64,
    timestamp: u64,
}

public struct GoalUpdated has copy, drop {
    campaign_id: ID,
    old_goal: u64,
    new_goal: u64,
    current_raised: u64,
    creator: address,
    timestamp: u64,
}

// ====== EVENT EMISSION FUNCTIONS ======
public fun emit_campaign_created(
    campaign_id: ID,
    creator: address,
    title: vector<u8>,
    description: vector<u8>,
    goal: u64,
    timestamp: u64,
) {
    event::emit(CampaignCreated {
        campaign_id,
        creator,
        title,
        description,
        goal,
        timestamp,
    });
}

public fun emit_campaign_updated(
    campaign_id: ID,
    field: vector<u8>,
    timestamp: u64,
) {
    event::emit(CampaignUpdated {
        campaign_id,
        field,
        timestamp,
    });
}

public fun emit_campaign_status_changed(
    campaign_id: ID,
    old_status: u8,
    new_status: u8,
    timestamp: u64,
) {
    event::emit(CampaignStatusChanged {
        campaign_id,
        old_status,
        new_status,
        timestamp,
    });
}

public fun emit_campaign_paused(
    campaign_id: ID,
    creator: address,
    reason: vector<u8>,
    timestamp: u64,
) {
    event::emit(CampaignPaused {
        campaign_id,
        creator,
        reason,
        timestamp,
    });
}

public fun emit_campaign_unpaused(
    campaign_id: ID,
    creator: address,
    timestamp: u64,
) {
    event::emit(CampaignUnpaused {
        campaign_id,
        creator,
        timestamp,
    });
}

public fun emit_campaign_cancelled(
    campaign_id: ID,
    creator: address,
    reason: vector<u8>,
    total_raised: u64,
    contributor_count: u64,
    timestamp: u64,
) {
    event::emit(CampaignCancelled {
        campaign_id,
        creator,
        reason,
        total_raised,
        contributor_count,
        timestamp,
    });
}

public fun emit_campaign_finalized(
    campaign_id: ID,
    final_status: u8,
    total_raised: u64,
    goal: u64,
    contributor_count: u64,
    timestamp: u64,
) {
    event::emit(CampaignFinalized {
        campaign_id,
        final_status,
        total_raised,
        goal,
        contributor_count,
        timestamp,
    });
}

public fun emit_contribution_event(
    campaign_id: ID,
    contributor: address,
    amount: u64,
    timestamp: u64,
) {
    event::emit(ContributionMade {
        campaign_id,
        contributor,
        amount,
        timestamp,
    });
}

public fun emit_contribution_made(
    campaign_id: ID,
    contributor: address,
    amount: u64,
    new_total_raised: u64,
    is_first_contribution: bool,
    remark: vector<u8>,
    timestamp: u64,
) {
    event::emit(ContributionMade {
        campaign_id,
        contributor,
        amount,
        timestamp,
    });
}

public fun emit_withdrawal_event(
    campaign_id: ID,
    recipient: address,
    amount: u64,
    timestamp: u64,
) {
    event::emit(FundsWithdrawn {
        campaign_id,
        recipient,
        amount,
        timestamp,
    });
}

public fun emit_funds_withdrawn(
    campaign_id: ID,
    recipient: address,
    amount: u64,
    timestamp: u64,
) {
    event::emit(FundsWithdrawn {
        campaign_id,
        recipient,
        amount,
        timestamp,
    });
}

public fun emit_refund_event(
    campaign_id: ID,
    contributor: address,
    amount: u64,
    timestamp: u64,
) {
    event::emit(RefundIssued {
        campaign_id,
        contributor,
        amount,
        timestamp,
    });
}

public fun emit_contribution_refunded(
    campaign_id: ID,
    contributor: address,
    amount: u64,
    reason: vector<u8>,
    timestamp: u64,
) {
    event::emit(RefundIssued {
        campaign_id,
        contributor,
        amount,
        timestamp,
    });
}

public fun emit_goal_reached(
    campaign_id: ID,
    final_amount: u64,
    goal: u64,
    contributor_count: u64,
    time_to_goal: u64,
    timestamp: u64,
) {
    event::emit(GoalReached {
        campaign_id,
        final_amount,
        goal,
        contributor_count,
        time_to_goal,
        timestamp,
    });
}

public fun emit_milestone_reached(
    campaign_id: ID,
    milestone_percentage: u64,
    current_amount: u64,
    goal: u64,
    timestamp: u64,
) {
    event::emit(MilestoneReached {
        campaign_id,
        milestone_percentage,
        current_amount,
        goal,
        timestamp,
    });
}

public fun emit_goal_updated(
    campaign_id: ID,
    old_goal: u64,
    new_goal: u64,
    current_raised: u64,
    creator: address,
    timestamp: u64,
) {
    event::emit(GoalUpdated {
        campaign_id,
        old_goal,
        new_goal,
        current_raised,
        creator,
        timestamp,
    });
}
