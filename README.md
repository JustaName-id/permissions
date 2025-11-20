# JustaPermissionManager

Delegation layer for JustanAccount enabling granular permissions with time-bound call execution and spending.

## Overview

JustaPermissionManager acts as an owner of [JustanAccount](https://github.com/justaname-id/justanaccount) smart accounts, providing fine-grained access control through delegated permissions. Account owners can grant time-limited permissions to "spenders" (delegated addresses) to execute specific actions on their behalf.

## Key Features

### Call Permissions

Allow spenders to execute specific function calls on target contracts:

- Whitelist specific contract addresses and function selectors
- Execute calls through the account with full validation

### Spend Limits

Enable token spending with recurring period-based allowances:

- Support for native tokens (ETH) and ERC-20 tokens
- Configurable spending limits with automatic period resets
- Per-period allowances that refresh on a fixed schedule

### Time-Bound Permissions

All permissions include start and end timestamps:

- Permissions cannot be used before start time
- Automatically expire after end time
- Provides temporal access control

### Revocation

Permissions can be revoked by either:

- The account owner (permission grantor)
- The spender (permission holder)
