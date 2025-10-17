# Confluence

Confluence is a Sui Move package for goal-based crowdfunding campaigns. Creators can accept contributions in `SUI` or `USDC`, manage campaign lifecycle (pause, unpause, cancel, finalize), withdraw funds after the end, and automatically issue POAP NFTs to contributors when successful.

## Overview
- Multi-coin support via generics: restricted to `SUI` and `USDC`.
- Campaign statuses: `ACTIVE`, `PAUSED`, `SUCCESSFUL`, `FAILED`, `CANCELLED`, `WITHDRAWN`.
- Strong validation, overflow checks, and a reentrancy guard on `Campaign`.
- Rich event emission for indexers and analytics.

## Modules
- `confluence::campaign` — Core campaign object and lifecycle: create, update metadata, contribute, pause/unpause, cancel, finalize, refund, withdraw.
- `confluence::funding` — Contributor registry and balances; add contributions, aggregate totals, withdraw/refund operations.
- `confluence::events` — Typed events for creation, updates, contributions, goals, status changes, refunds, withdrawals, finalization.
- `confluence::poap` — Minimal NFT minted as proof-of-contribution with display fields; issued on success.
- `confluence::version` — Shared `Version` object and runtime check to validate the deployed package version.
- `confluence::confluence` — Package init helper: claims a `Publisher` and transfers it to the sender.

## Quick Start

Build
```
sui move build
```

Test
```
sui move test
```

Publish
```
sui client publish --gas-budget 200000000
```

## CLI Examples (copy-ready)
Replace placeholders:
- `<PACKAGE_ID>`: your published package ID
- `<USDC_PACKAGE_ID>`: the USDC package ID if using USDC
- `<CAMPAIGN_ID>`: your shared `Campaign<T>` object ID
- `<COIN_ID>`: a `0x2::coin::Coin<T>` object ID of the correct type
- `<CLOCK_ID>`: global clock (usually `0x6`)
- `<AMOUNT>`/`<NEW_GOAL>`: numeric amounts in base units

Create SUI campaign
```
sui client call --package <PACKAGE_ID> --module campaign --function create_and_share_campaign --type-args 0x2::sui::SUI --args "My Campaign" "Description" 1000000000 604800000 <CLOCK_ID> --gas-budget 200000000
```

Create USDC campaign
```
sui client call --package <PACKAGE_ID> --module campaign --function create_and_share_campaign --type-args <USDC_PACKAGE_ID>::usdc::USDC --args "My Campaign" "Description" 1000000 604800000 <CLOCK_ID> --gas-budget 200000000
```

Contribute (SUI)
```
sui client call --package <PACKAGE_ID> --module campaign --function contribute --type-args 0x2::sui::SUI --args <CAMPAIGN_ID> <COIN_ID> "Great project!" <CLOCK_ID> --gas-budget 200000000
```

Pause campaign
```
sui client call --package <PACKAGE_ID> --module campaign --function pause_campaign --type-args 0x2::sui::SUI --args <CAMPAIGN_ID> "maintenance" <CLOCK_ID> --gas-budget 200000000
```

Unpause campaign
```
sui client call --package <PACKAGE_ID> --module campaign --function unpause_campaign --type-args 0x2::sui::SUI --args <CAMPAIGN_ID> <CLOCK_ID> --gas-budget 200000000
```

Finalize (after end)
```
sui client call --package <PACKAGE_ID> --module campaign --function finalize_campaign --type-args 0x2::sui::SUI --args <CAMPAIGN_ID> <CLOCK_ID> --gas-budget 200000000
```

Withdraw funds (creator)
```
sui client call --package <PACKAGE_ID> --module campaign --function withdraw_funds --type-args 0x2::sui::SUI --args <CAMPAIGN_ID> <AMOUNT> <CLOCK_ID> --gas-budget 200000000
```

Cancel + refund all
```
sui client call --package <PACKAGE_ID> --module campaign --function cancel_campaign --type-args 0x2::sui::SUI --args <CAMPAIGN_ID> "reason" <CLOCK_ID> --gas-budget 200000000
```

Refund contributor (failed/cancelled)
```
sui client call --package <PACKAGE_ID> --module campaign --function refund_contributor --type-args 0x2::sui::SUI --args <CAMPAIGN_ID> <CONTRIBUTOR_ADDRESS> "reason" <CLOCK_ID> --gas-budget 200000000
```

Update title
```
sui client call --package <PACKAGE_ID> --module campaign --function update_title --type-args 0x2::sui::SUI --args <CAMPAIGN_ID> "New Title" <CLOCK_ID> --gas-budget 200000000
```

Update description
```
sui client call --package <PACKAGE_ID> --module campaign --function update_description --type-args 0x2::sui::SUI --args <CAMPAIGN_ID> "New Description" <CLOCK_ID> --gas-budget 200000000
```

Set profile URL
```
sui client call --package <PACKAGE_ID> --module campaign --function set_profile_url --type-args 0x2::sui::SUI --args <CAMPAIGN_ID> "https://example.com/profile.png" <CLOCK_ID> --gas-budget 200000000
```

Set background URL
```
sui client call --package <PACKAGE_ID> --module campaign --function set_background_url --type-args 0x2::sui::SUI --args <CAMPAIGN_ID> "https://example.com/background.png" <CLOCK_ID> --gas-budget 200000000
```

Update goal
```
sui client call --package <PACKAGE_ID> --module campaign --function update_goal --type-args 0x2::sui::SUI --args <CAMPAIGN_ID> <NEW_GOAL> <CLOCK_ID> --gas-budget 200000000
```

## Events
Key event types: `CampaignCreated`, `CampaignUpdated`, `CampaignStatusChanged`, `CampaignPaused`, `CampaignUnpaused`, `CampaignCancelled`, `CampaignFinalized`, `ContributionMade`, `FundsWithdrawn`, `RefundIssued`, `RefundBatchProcessed`, `AllContributorsRefunded`, `GoalReached`, `MilestoneReached`, `GoalUpdated`.

## Notes
- Named address `confluence` is `0x0` in `Move.toml` and replaced on publish.
- POAP NFTs include display fields and transfer to contributors when goals are achieved.
- Target edition: Sui Move `2024.beta` (adjust if using legacy Move).