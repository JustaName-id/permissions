// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import { JustanAccount } from "justanaccount/JustanAccount.sol";

import { EIP712 } from "solady/utils/EIP712.sol";
import { ReentrancyGuard } from "solady/utils/ReentrancyGuard.sol";
import { LibBytes } from "solady/utils/LibBytes.sol";
import { LibSort } from "solady/utils/LibSort.sol";
import { DynamicArrayLib } from "solady/utils/DynamicArrayLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { FixedPointMathLib as Math } from "solady/utils/FixedPointMathLib.sol";
import { DateTimeLib } from "solady/utils/DateTimeLib.sol";

/**
 * @title JustaPermissionManager
 *
 * @notice Delegation layer for JustanAccount enabling granular permissions with execution guards and spend limits.
 *
 * @author JustaLab
 */
contract JustaPermissionManager is EIP712, ReentrancyGuard {

    using SafeERC20 for IERC20;
    using LibBytes for *;
    using DynamicArrayLib for *;

    ////////////////////////////////////////////////////////////////////////
    // ERRORS
    ////////////////////////////////////////////////////////////////////////

    error InvalidSender(address sender, address expected);
    error UnauthorizedPermission();
    error ZeroSpender();
    error InvalidStartEnd(uint48 start, uint48 end);
    error BeforePermissionStart(uint48 currentTimestamp, uint48 start);
    error AfterPermissionEnd(uint48 currentTimestamp, uint48 end);
    error SpendValueOverflow(uint256 value);
    error ExceededSpendLimit(uint256 value, uint256 allowance);
    error UnauthorizedCall(address target, bytes4 selector);
    error ZeroToken();
    error ZeroAllowance();
    error ERC721TokenNotSupported(address token);
    error ERC1155TokenNotSupported(address token);
    error EmptyPermission();
    error ZeroTarget();
    error ZeroSelector();
    error DuplicateSpendLimit(address token);
    error NoSpendPermissions();
    error CannotTargetSelf();
    error CannotTargetAccount();
    error PeriodOverflow();
    error ApprovalRevocationFailed(address token, address spender);

    ////////////////////////////////////////////////////////////////////////
    // ENUMS
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Standardized spend periods to prevent period calculation gaming.
     * @dev Using fixed periods eliminates modulo arithmetic edge cases.
     */
    enum SpendPeriod {
        Minute,     // 60 seconds
        Hour,       // 3600 seconds
        Day,        // 86400 seconds
        Week,       // 604800 seconds
        Month,      // 2592000 seconds (30 days)
        Year,       // 31536000 seconds (365 days)
        Forever     // type(uint48).max, one-time allowance for entire permission duration
    }

    ////////////////////////////////////////////////////////////////////////
    // STRUCTS
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice A call permission allowing execution of specific functions.
     */
    struct CallPermission {
        address target;
        bytes4 selector;
    }

    /**
     * @notice A spend limit for a specific token with recurring periods.
     */
    struct SpendLimit {
        address token;
        uint160 allowance;
        SpendPeriod period;
    }

    /**
     * @notice Complete permission with arrays included.
     */
    struct Permission {
        address account;
        address spender;
        uint48 start;
        uint48 end;
        uint256 salt;
        CallPermission[] calls;
        SpendLimit[] spends;
    }

    /**
     * @notice Period parameters and spend usage.
     */
    struct PeriodSpend {
        uint48 start;
        uint48 end;
        uint160 spend;
    }

    /**
     * @notice A single call to execute (matches ERC7821 Call struct pattern)
     */
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    /**
     * @notice Temporary storage for tracking during batch execution
     */
    struct ExecuteTemps {
        DynamicArrayLib.DynamicArray approvedERC20s;
        DynamicArrayLib.DynamicArray approvalSpenders;
        DynamicArrayLib.DynamicArray erc20s;
        DynamicArrayLib.DynamicArray transferAmounts;
        DynamicArrayLib.DynamicArray permit2ERC20s;
        DynamicArrayLib.DynamicArray permit2Spenders;
    }

    ////////////////////////////////////////////////////////////////////////
    // CONSTANTS
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice ERC-7528 native token address convention.
     */
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @notice Canonical Permit2 contract address.
     */
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /**
     * @notice Wildcard constants (inspired by GuardedExecutor pattern)
     */
    address public constant ANY_TARGET = 0x3232323232323232323232323232323232323232;
    bytes4 public constant ANY_FN_SEL = 0x32323232;
    bytes4 public constant EMPTY_CALLDATA_FN_SEL = 0xe0e0e0e0;

    /**
     * @notice EIP-712 typehashes
     */
    bytes32 public constant CALL_PERMISSION_TYPEHASH = keccak256("CallPermission(address target,bytes4 selector)");

    bytes32 public constant SPEND_LIMIT_TYPEHASH =
        keccak256("SpendLimit(address token,uint160 allowance,uint8 period)");

    bytes32 public constant PERMISSION_TYPEHASH = keccak256(
        "Permission(address account,address spender,uint48 start,uint48 end,uint256 salt,CallPermission[] calls,SpendLimit[] spends)CallPermission(address target,bytes4 selector)SpendLimit(address token,uint160 allowance,uint8 period)"
    );

    ////////////////////////////////////////////////////////////////////////
    // STORAGE
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Permission is approved (hash of entire Permission struct).
     */
    mapping(bytes32 permissionHash => bool approved) internal _isApproved;

    /**
     * @notice Permission is revoked.
     */
    mapping(bytes32 permissionHash => bool revoked) internal _isRevoked;

    /**
     * @notice Last updated period for each spend limit.
     */
    mapping(bytes32 permissionHash => mapping(bytes32 spendLimitHash => PeriodSpend)) internal _lastUpdatedPeriod;

    ////////////////////////////////////////////////////////////////////////
    // EVENTS
    ////////////////////////////////////////////////////////////////////////

    event PermissionApproved(bytes32 indexed permissionHash, Permission permission);
    event PermissionRevoked(bytes32 indexed permissionHash);
    event CallExecuted(bytes32 indexed permissionHash, address indexed target, bytes4 indexed selector, uint256 value);
    event SpendLimitUsed(bytes32 indexed permissionHash, address indexed token, PeriodSpend periodSpend);

    ////////////////////////////////////////////////////////////////////////
    // MODIFIERS
    ////////////////////////////////////////////////////////////////////////

    modifier requireSender(address sender) {
        if (msg.sender != sender) {
            revert InvalidSender(msg.sender, sender);
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////
    // ADMIN FUNCTIONS
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Approve a permission with call and spend limits.
     * @dev Both calls and spends MUST be configured together.
     * @param permission The complete permission with calls and spends arrays.
     * @return True if approved successfully.
     */
    function approve(Permission calldata permission) external requireSender(permission.account) returns (bool) {
        // Check spender is non-zero
        if (permission.spender == address(0)) {
            revert ZeroSpender();
        }

        // Check start is strictly before end
        if (permission.start >= permission.end) {
            revert InvalidStartEnd(permission.start, permission.end);
        }

        // Check permission is not empty
        if (permission.calls.length == 0 && permission.spends.length == 0) {
            revert EmptyPermission();
        }

        // Validate call permissions
        uint256 callsLength = permission.calls.length;
        for (uint256 i = 0; i < callsLength; i++) {
            // Prevent targeting self (privilege escalation)
            if (permission.calls[i].target == address(this)) {
                revert CannotTargetSelf();
            }

            // Prevent targeting the account (privilege escalation)
            if (permission.calls[i].target == permission.account) {
                revert CannotTargetAccount();
            }

            // Allow wildcards (ANY_TARGET, ANY_FN_SEL, EMPTY_CALLDATA_FN_SEL)
            // Reject zero values that are NOT wildcards
            if (permission.calls[i].target == address(0) && permission.calls[i].target != ANY_TARGET) {
                revert ZeroTarget();
            }
            if (
                permission.calls[i].selector == bytes4(0)
                    && permission.calls[i].selector != EMPTY_CALLDATA_FN_SEL
            ) {
                revert ZeroSelector();
            }
        }

        // Validate spend limits
        uint256 spendsLength = permission.spends.length;
        for (uint256 i = 0; i < spendsLength; i++) {
            if (permission.spends[i].token == address(0)) {
                revert ZeroToken();
            }
            if (permission.spends[i].allowance == 0) {
                revert ZeroAllowance();
            }

            // Check token is not an ERC-721 or ERC-1155
            if (permission.spends[i].token != NATIVE_TOKEN) {
                if (ERC165Checker.supportsInterface(permission.spends[i].token, type(IERC721).interfaceId)) {
                    revert ERC721TokenNotSupported(permission.spends[i].token);
                }
                if (ERC165Checker.supportsInterface(permission.spends[i].token, type(IERC1155).interfaceId)) {
                    revert ERC1155TokenNotSupported(permission.spends[i].token);
                }
            }
        }

        // Check for duplicate spend limits (same token + allowance + period)
        // This allows same token with different periods (e.g., hourly + daily limits)
        // but prevents exact duplicates which would double-count spending
        if (spendsLength > 1) {
            bytes32[] memory spendHashes = new bytes32[](spendsLength);
            for (uint256 i = 0; i < spendsLength; i++) {
                spendHashes[i] = _hashSpendLimit(permission.spends[i]);
            }
            LibSort.sort(spendHashes);
            for (uint256 i = 1; i < spendsLength; i++) {
                if (spendHashes[i] == spendHashes[i - 1]) {
                    revert DuplicateSpendLimit(permission.spends[i].token);
                }
            }
        }

        bytes32 hash = getHash(permission);

        // Check if already revoked - don't allow reusing revoked permission hashes
        if (_isRevoked[hash]) {
            revert UnauthorizedPermission();
        }

        // Return true if already approved
        if (_isApproved[hash]) {
            return true;
        }

        _isApproved[hash] = true;
        emit PermissionApproved(hash, permission);

        return true;
    }

    /**
     * @notice Revoke a permission as the account owner.
     */
    function revoke(Permission calldata permission) external nonReentrant requireSender(permission.account) {
        _revoke(permission);
    }

    /**
     * @notice Revoke a permission as the spender.
     */
    function revokeAsSpender(Permission calldata permission) external nonReentrant requireSender(permission.spender) {
        _revoke(permission);
    }

    ////////////////////////////////////////////////////////////////////////
    // EXECUTION FUNCTIONS
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Execute multiple calls using a permission (batch execution).
     * @dev
     *      1. Check permission for ALL calls first (fail-fast)
     *      2. Collect ERC20 tokens with spend limits
     *      3. Parse calldata for token operations (transfer, approve, Permit2)
     *      4. Record balances BEFORE execution
     *      5. Execute all calls
     *      6. Increment native spend tracking AFTER execution
     *      7. Revoke approvals (hard failures - transaction reverts if revocation fails)
     *      8. Check ERC20 spend limits using max(calldata_sum, balance_delta)
     *
     * @param permission The complete permission with all calls and spends.
     * @param calls Array of calls to execute.
     */
    function executeBatch(
        Permission calldata permission,
        Call[] calldata calls
    )
        external
        nonReentrant
        requireSender(permission.spender)
    {
        bytes32 hash = getHash(permission);

        // Check permission is approved and not revoked
        _checkApprovedNotRevoked(hash);

        // Check permission time bounds
        _checkPermissionTimeBounds(permission.start, permission.end);

        // ============================================================
        // STEP 1: CHECK EXECUTION PERMISSIONS (FIRST - FAIL FAST)
        // ============================================================
        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength; i++) {
            // Prevent targeting self (privilege escalation)
            if (calls[i].target == address(this)) {
                revert CannotTargetSelf();
            }

            // Prevent targeting the account (privilege escalation)
            if (calls[i].target == permission.account) {
                revert CannotTargetAccount();
            }

            // Extract function selector (use EMPTY_CALLDATA_FN_SEL for empty calldata)
            bytes4 selector = calls[i].data.length >= 4
                ? bytes4(LibBytes.loadCalldata(calls[i].data, 0x00))
                : EMPTY_CALLDATA_FN_SEL;

            // Check if this call is authorized
            if (!_isCallAuthorized(permission, calls[i].target, selector)) {
                revert UnauthorizedCall(calls[i].target, selector);
            }
        }

        // ============================================================
        // STEP 2: SPEND TRACKING SETUP
        // ============================================================
        ExecuteTemps memory t;

        // Collect all ERC20 tokens that need to be guarded,
        // and initialize their transfer amounts as zero.
        // Used for the check on their before and after balances.
        uint256 spendsLength = permission.spends.length;
        for (uint256 i = 0; i < spendsLength; i++) {
            address token = permission.spends[i].token;
            if (token != NATIVE_TOKEN) {
                t.erc20s.p(token);
                t.transferAmounts.p(uint256(0));
            }
        }

        // Parse calldata for token operations.
        // We only filter based on functions that use `msg.sender`.
        // For signature-based approvals (e.g. permit), we can't guard them
        // as anyone can submit the calldata and signature directly.
        uint256 totalNativeSpend;
        for (uint256 i; i < callsLength; ++i) {
            address target = calls[i].target;
            uint256 value = calls[i].value;
            bytes calldata data = calls[i].data;

            if (value != 0) totalNativeSpend += value;
            if (data.length < 4) continue;

            uint32 fnSel = uint32(bytes4(LibBytes.loadCalldata(data, 0x00)));

            // `transfer(address,uint256)` - 0xa9059cbb
            if (fnSel == 0xa9059cbb) {
                t.erc20s.p(target);
                t.transferAmounts.p(LibBytes.loadCalldata(data, 0x24)); // `amount`
            }

            // `transferFrom(address,address,uint256)` - 0x23b872dd
            // The account may have existing ERC20 allowances. If `transferFrom` is used
            // to transfer from the permission account, treat it as outflow.
            if (fnSel == 0x23b872dd) {
                address from = LibBytes.loadCalldata(data, 0x04).lsbToAddress();
                address to = LibBytes.loadCalldata(data, 0x24).lsbToAddress();
                // Skip if this is a self-to-self transfer
                if (from == permission.account && to == permission.account) continue;
                if (LibBytes.loadCalldata(data, 0x44) == 0) continue; // `amount == 0`
                // Only track if account is the sender
                if (from == permission.account) {
                    t.erc20s.p(target);
                    t.transferAmounts.p(LibBytes.loadCalldata(data, 0x44)); // `amount`
                }
            }

            // `approve(address,uint256)` - 0x095ea7b3
            // We have to revoke any new approvals after the batch, else a bad app can
            // leave an approval to let them drain unlimited tokens after the batch.
            if (fnSel == 0x095ea7b3) {
                if (LibBytes.loadCalldata(data, 0x24) == 0) continue; // `amount == 0`
                t.approvedERC20s.p(target);
                t.approvalSpenders.p(LibBytes.loadCalldata(data, 0x04).lsbToAddress()); // `spender`
                t.erc20s.p(target); // `token`
                t.transferAmounts.p(LibBytes.loadCalldata(data, 0x24)); // `amount`
            }

            // Permit2 `approve(address,address,uint160,uint48)` - 0x87517c45
            // For ERC20 tokens giving Permit2 infinite approvals by default,
            // the approve method on Permit2 acts like a approve method on the ERC20.
            if (fnSel == 0x87517c45) {
                if (target != PERMIT2) continue;
                if (LibBytes.loadCalldata(data, 0x44) == 0) continue; // `amount == 0`
                t.permit2ERC20s.p(LibBytes.loadCalldata(data, 0x04).lsbToAddress()); // `token`
                t.permit2Spenders.p(LibBytes.loadCalldata(data, 0x24).lsbToAddress()); // `spender`
                t.erc20s.p(LibBytes.loadCalldata(data, 0x04).lsbToAddress()); // `token`
                t.transferAmounts.p(LibBytes.loadCalldata(data, 0x44)); // `amount`
            }
        }

        // Sum transfer amounts, grouped by the ERC20s. In-place.
        // Only call groupSum if there are tokens to process
        uint256 erc20sLength = t.erc20s.length();
        if (erc20sLength > 0) {
            LibSort.groupSum(t.erc20s.data, t.transferAmounts.data);
        }

        // Collect the ERC20 balances before the batch execution.
        uint256[] memory balancesBefore = DynamicArrayLib.malloc(erc20sLength);
        for (uint256 i; i < erc20sLength; ++i) {
            address token = t.erc20s.getAddress(i);
            balancesBefore.set(i, SafeTransferLib.balanceOf(token, permission.account));
        }

        // ============================================================
        // STEP 3: EXECUTE ALL CALLS
        // ============================================================
        for (uint256 i = 0; i < callsLength; i++) {
            _execute(permission.account, calls[i].target, calls[i].value, calls[i].data);

            emit CallExecuted(
                hash,
                calls[i].target,
                calls[i].data.length >= 4 ? bytes4(LibBytes.loadCalldata(calls[i].data, 0x00)) : bytes4(0),
                calls[i].value
            );
        }

        // ============================================================
        // STEP 4: CHECK SPEND LIMITS (AFTER EXECUTION)
        // ============================================================

        // Perform after the execution, so that in case `calls` contain
        // a spend limit update, it will affect the increment.
        if (totalNativeSpend != 0) {
            _checkAndIncrementSpend(hash, permission, NATIVE_TOKEN, totalNativeSpend);
        }

        // Revoke all non-zero approvals that have been made.
        // As spend permissions are whitelist style, we need to make sure that
        // approvals are revoked. This is to prevent sidestepping the guard.
        uint256 approvedLength = t.approvedERC20s.length();
        for (uint256 i; i < approvedLength; ++i) {
            address token = t.approvedERC20s.getAddress(i);
            address spender = t.approvalSpenders.getAddress(i);
            SafeTransferLib.safeApprove(token, spender, 0);
            // Verify the approval was actually revoked
            if (IERC20(token).allowance(permission.account, spender) != 0) {
                revert ApprovalRevocationFailed(token, spender);
            }
        }

        // Revoke all non-zero Permit2 direct approvals that have been made.
        uint256 permit2Length = t.permit2ERC20s.length();
        for (uint256 i; i < permit2Length; ++i) {
            address token = t.permit2ERC20s.getAddress(i);
            address spender = t.permit2Spenders.getAddress(i);
            SafeTransferLib.permit2Lockdown(token, spender);
        }

        // Increments the spent amounts.
        for (uint256 i; i < erc20sLength; ++i) {
            address token = t.erc20s.getAddress(i);

            // While we can actually just use the difference before and after,
            // we also want to let the sum of the transfer amounts in the calldata to be capped.
            // This prevents tokens from being used as flash loans, and also handles cases
            // where the actual token transfers might not match the calldata amounts.
            // There is no strict definition on what constitutes spending,
            // and we want to be as conservative as possible.
            uint256 spentAmount = Math.max(
                t.transferAmounts.get(i),
                Math.saturatingSub(
                    balancesBefore.get(i),
                    SafeTransferLib.balanceOf(token, permission.account)
                )
            );

            if (spentAmount > 0) {
                _checkAndIncrementSpend(hash, permission, token, spentAmount);
            }
        }
    }

    ////////////////////////////////////////////////////////////////////////
    // VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////////////////

    function isApproved(Permission calldata permission) external view returns (bool) {
        return _isApproved[getHash(permission)];
    }

    function isRevoked(Permission calldata permission) external view returns (bool) {
        return _isRevoked[getHash(permission)];
    }

    function getLastUpdatedPeriod(
        Permission calldata permission,
        SpendLimit calldata spendLimit
    )
        external
        view
        returns (PeriodSpend memory)
    {
        bytes32 hash = getHash(permission);
        bytes32 spendLimitHash = _hashSpendLimit(spendLimit);
        return _lastUpdatedPeriod[hash][spendLimitHash];
    }

    function getCurrentPeriod(
        Permission calldata permission,
        SpendLimit calldata spendLimit
    )
        external
        view
        returns (PeriodSpend memory)
    {
        bytes32 hash = getHash(permission);
        bytes32 spendLimitHash = _hashSpendLimit(spendLimit);
        return _getCurrentPeriod(hash, spendLimitHash, spendLimit, permission.start, permission.end);
    }

    function getHash(Permission calldata permission) public view returns (bytes32) {
        uint256 callsLength = permission.calls.length;
        bytes32[] memory callHashes = new bytes32[](callsLength);
        for (uint256 i = 0; i < callsLength; i++) {
            callHashes[i] = _hashCallPermission(permission.calls[i]);
        }

        uint256 spendsLength = permission.spends.length;
        bytes32[] memory spendHashes = new bytes32[](spendsLength);
        for (uint256 i = 0; i < spendsLength; i++) {
            spendHashes[i] = _hashSpendLimit(permission.spends[i]);
        }

        return _hashTypedData(
            keccak256(
                abi.encode(
                    PERMISSION_TYPEHASH,
                    permission.account,
                    permission.spender,
                    permission.start,
                    permission.end,
                    permission.salt,
                    keccak256(abi.encodePacked(callHashes)),
                    keccak256(abi.encodePacked(spendHashes))
                )
            )
        );
    }

    ////////////////////////////////////////////////////////////////////////
    // INTERNAL HELPERS
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Rounds the unix timestamp down to the period start.
     * @dev Aligns periods to calendar boundaries to prevent gaming.
     *      - Minute/Hour/Day: Rounds down using division
     *      - Week: Aligns to Monday
     *      - Month: Aligns to 1st of month
     *      - Year: Aligns to Jan 1st
     *      - Forever: Returns 1 (non-zero to differentiate from unset)
     */
    function startOfSpendPeriod(uint256 unixTimestamp, SpendPeriod period)
        public
        pure
        returns (uint256)
    {
        if (period == SpendPeriod.Minute) {
            return Math.rawMul(Math.rawDiv(unixTimestamp, 60), 60);
        }
        if (period == SpendPeriod.Hour) {
            return Math.rawMul(Math.rawDiv(unixTimestamp, 3600), 3600);
        }
        if (period == SpendPeriod.Day) {
            return Math.rawMul(Math.rawDiv(unixTimestamp, 86400), 86400);
        }
        if (period == SpendPeriod.Week) {
            return DateTimeLib.mondayTimestamp(unixTimestamp);
        }
        (uint256 year, uint256 month,) = DateTimeLib.timestampToDate(unixTimestamp);
        // Note: DateTimeLib's months and month-days start from 1.
        if (period == SpendPeriod.Month) {
            return DateTimeLib.dateToTimestamp(year, month, 1);
        }
        if (period == SpendPeriod.Year) {
            return DateTimeLib.dateToTimestamp(year, 1, 1);
        }
        if (period == SpendPeriod.Forever) {
            return 1; // Non-zero to differentiate from not set.
        }
        revert(); // We shouldn't hit here.
    }

    /**
     * @notice Get the duration of a spend period in seconds.
     */
    function _periodDuration(SpendPeriod period, uint256 periodStart) internal pure returns (uint48) {
        if (period == SpendPeriod.Minute) return 60;
        if (period == SpendPeriod.Hour) return 3600;
        if (period == SpendPeriod.Day) return 86400;
        if (period == SpendPeriod.Week) return 604800;

        // For Month and Year, calculate actual duration from the period start
        if (period == SpendPeriod.Month) {
            (uint256 year, uint256 month,) = DateTimeLib.timestampToDate(periodStart);
            uint256 nextMonth = month == 12 ? 1 : month + 1;
            uint256 nextYear = month == 12 ? year + 1 : year;
            uint256 nextPeriodStart = DateTimeLib.dateToTimestamp(nextYear, nextMonth, 1);
            return uint48(nextPeriodStart - periodStart);
        }

        if (period == SpendPeriod.Year) {
            (uint256 year,,) = DateTimeLib.timestampToDate(periodStart);
            uint256 nextPeriodStart = DateTimeLib.dateToTimestamp(year + 1, 1, 1);
            return uint48(nextPeriodStart - periodStart);
        }

        return type(uint48).max; // Forever
    }

    /**
     * @notice Check if a call is authorized, supporting wildcards.
     * @dev Wildcard support:
     *      - ANY_TARGET (0x3232...): Allows any target address
     *      - ANY_FN_SEL (0x32323232): Allows any function selector
     *      - EMPTY_CALLDATA_FN_SEL (0xe0e0e0e0): Explicit empty calldata permission
     */
    function _isCallAuthorized(
        Permission calldata permission,
        address target,
        bytes4 selector
    )
        internal
        pure
        returns (bool)
    {
        uint256 callsLength = permission.calls.length;
        for (uint256 i = 0; i < callsLength; i++) {
            // Exact match
            if (permission.calls[i].target == target && permission.calls[i].selector == selector) {
                return true;
            }

            // Wildcard target (ANY_TARGET) with exact selector
            if (permission.calls[i].target == ANY_TARGET && permission.calls[i].selector == selector) {
                return true;
            }

            // Exact target with wildcard selector (ANY_FN_SEL)
            if (permission.calls[i].target == target && permission.calls[i].selector == ANY_FN_SEL) {
                return true;
            }

            // Both wildcards (ANY_TARGET + ANY_FN_SEL)
            if (permission.calls[i].target == ANY_TARGET && permission.calls[i].selector == ANY_FN_SEL) {
                return true;
            }
        }

        return false;
    }


    function _checkAndIncrementSpend(
        bytes32 hash,
        Permission calldata permission,
        address token,
        uint256 amount
    )
        internal
    {
        if (amount == 0) return;

        // Check ALL spend limits for this token (supports multiple periods per token)
        bool found = false;
        uint256 spendsLength = permission.spends.length;
        for (uint256 i = 0; i < spendsLength; i++) {
            if (permission.spends[i].token == token) {
                found = true;
                bytes32 spendLimitHash = _hashSpendLimit(permission.spends[i]);
                _useSpendLimit(
                    hash,
                    spendLimitHash,
                    permission.spends[i],
                    amount,
                    permission.start,
                    permission.end
                );
                // Don't break - continue checking all limits for this token
            }
        }

        // If token has no spend limit configured, revert
        if (!found) {
            revert NoSpendPermissions();
        }
    }

    function _checkApprovedNotRevoked(bytes32 hash) internal view {
        if (!_isApproved[hash] || _isRevoked[hash]) {
            revert UnauthorizedPermission();
        }
    }

    function _checkPermissionTimeBounds(uint48 start, uint48 end) internal view returns (uint48 currentTimestamp) {
        currentTimestamp = uint48(block.timestamp);
        if (currentTimestamp < start) {
            revert BeforePermissionStart(currentTimestamp, start);
        }
        if (currentTimestamp > end) {
            revert AfterPermissionEnd(currentTimestamp, end);
        }
    }

    function _useSpendLimit(
        bytes32 hash,
        bytes32 spendLimitHash,
        SpendLimit calldata spendLimit,
        uint256 value,
        uint48 permissionStart,
        uint48 permissionEnd
    )
        internal
    {
        PeriodSpend memory currentPeriod =
            _getCurrentPeriod(hash, spendLimitHash, spendLimit, permissionStart, permissionEnd);

        uint256 totalSpend = value + uint256(currentPeriod.spend);

        if (totalSpend > type(uint160).max) {
            revert SpendValueOverflow(totalSpend);
        }

        if (totalSpend > spendLimit.allowance) {
            revert ExceededSpendLimit(totalSpend, spendLimit.allowance);
        }

        currentPeriod.spend = uint160(totalSpend);
        _lastUpdatedPeriod[hash][spendLimitHash] = currentPeriod;

        emit SpendLimitUsed(hash, spendLimit.token, PeriodSpend(currentPeriod.start, currentPeriod.end, uint160(value)));
    }

    function _getCurrentPeriod(
        bytes32 hash,
        bytes32 spendLimitHash,
        SpendLimit calldata spendLimit,
        uint48 permissionStart,
        uint48 permissionEnd
    )
        internal
        view
        returns (PeriodSpend memory)
    {
        uint48 currentTimestamp = _checkPermissionTimeBounds(permissionStart, permissionEnd);

        PeriodSpend memory lastUpdatedPeriod = _lastUpdatedPeriod[hash][spendLimitHash];

        bool lastPeriodExists = lastUpdatedPeriod.start != 0;
        bool lastPeriodStillActive = currentTimestamp <= lastUpdatedPeriod.end;

        if (lastPeriodExists && lastPeriodStillActive) {
            return lastUpdatedPeriod;
        }

        // Use startOfSpendPeriod to align to calendar boundaries
        uint48 periodStart = uint48(startOfSpendPeriod(currentTimestamp, spendLimit.period));

        // For Forever period, use entire permission duration
        if (spendLimit.period == SpendPeriod.Forever) {
            return PeriodSpend({ start: permissionStart, end: permissionEnd, spend: 0 });
        }

        // Clamp period start to permission start (can't track spending before permission begins)
        if (periodStart < permissionStart) {
            periodStart = permissionStart;
        }

        // Calculate period end using duration
        uint48 duration = _periodDuration(spendLimit.period, periodStart);
        uint256 calculatedEnd = uint256(periodStart) + uint256(duration);

        // Check for overflow before casting
        if (calculatedEnd > type(uint48).max) {
            revert PeriodOverflow();
        }

        // Cap at permission end
        uint48 periodEnd = calculatedEnd > permissionEnd ? permissionEnd : uint48(calculatedEnd);

        return PeriodSpend({ start: periodStart, end: periodEnd, spend: 0 });
    }

    function _revoke(Permission calldata permission) internal {
        bytes32 hash = getHash(permission);

        if (_isRevoked[hash]) {
            return;
        }

        _isRevoked[hash] = true;
        emit PermissionRevoked(hash);
    }

    function _hashCallPermission(CallPermission calldata call) internal pure returns (bytes32) {
        return keccak256(abi.encode(CALL_PERMISSION_TYPEHASH, call.target, call.selector));
    }

    function _hashSpendLimit(SpendLimit calldata spendLimit) internal pure returns (bytes32) {
        return keccak256(abi.encode(SPEND_LIMIT_TYPEHASH, spendLimit.token, spendLimit.allowance, spendLimit.period));
    }

    function _execute(address account, address target, uint256 value, bytes memory data) internal {
        JustanAccount(payable(account)).execute({ target: target, value: value, data: data });
    }

    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "JustaPermissionManager";
        version = "1";
    }
}
