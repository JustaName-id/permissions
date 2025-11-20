// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import { JustanAccount } from "justanaccount/JustanAccount.sol";

import { EIP712 } from "solady/utils/EIP712.sol";

/**
 * @title JustaPermissionManager
 *
 * @notice Delegation layer for JustanAccount enabling granular permissions with time-bound call execution and spending.
 *
 * @author JustaLab
 */
contract JustaPermissionManager is EIP712 {

    using SafeERC20 for IERC20;

    /**
     * @notice Thrown when the caller is not the expected sender.
     * @param sender The actual sender address.
     * @param expected The expected sender address.
     */
    error JustaPermissionManager_InvalidSender(address sender, address expected);

    /**
     * @notice Thrown when attempting to use a permission that is not approved or has been revoked.
     */
    error JustaPermissionManager_UnauthorizedPermission();

    /**
     * @notice Thrown when attempting to approve a permission with a zero spender address.
     */
    error JustaPermissionManager_ZeroSpender();

    /**
     * @notice Thrown when the permission start time is greater than or equal to the end time.
     * @param start The permission start timestamp.
     * @param end The permission end timestamp.
     */
    error JustaPermissionManager_InvalidStartEnd(uint48 start, uint48 end);

    /**
     * @notice Thrown when attempting to spend zero value.
     */
    error JustaPermissionManager_ZeroValue();

    /**
     * @notice Thrown when attempting to use a permission before its start time.
     * @param currentTimestamp The current block timestamp.
     * @param start The permission start timestamp.
     */
    error JustaPermissionManager_BeforePermissionStart(uint48 currentTimestamp, uint48 start);

    /**
     * @notice Thrown when attempting to use a permission after its end time.
     * @param currentTimestamp The current block timestamp.
     * @param end The permission end timestamp.
     */
    error JustaPermissionManager_AfterPermissionEnd(uint48 currentTimestamp, uint48 end);

    /**
     * @notice Thrown when the spend value exceeds the maximum uint160 value.
     * @param value The overflowing spend value.
     */
    error JustaPermissionManager_SpendValueOverflow(uint256 value);

    /**
     * @notice Thrown when attempting to spend more than the allowed limit for the current period.
     * @param value The total spend amount attempted.
     * @param allowance The maximum allowed spend for the period.
     */
    error JustaPermissionManager_ExceededSpendLimit(uint256 value, uint256 allowance);

    /**
     * @notice Thrown when attempting to execute a call that is not authorized by the permission.
     * @param target The target contract address.
     * @param selector The function selector attempted.
     */
    error JustaPermissionManager_UnauthorizedCall(address target, bytes4 selector);

    /**
     * @notice Thrown when attempting to create a spend limit with a zero token address.
     */
    error JustaPermissionManager_ZeroToken();

    /**
     * @notice Thrown when attempting to create a spend limit with zero allowance.
     */
    error JustaPermissionManager_ZeroAllowance();

    /**
     * @notice Thrown when attempting to create a spend limit with zero period.
     */
    error JustaPermissionManager_ZeroPeriod();

    /**
     * @notice Thrown when attempting to create a spend limit for an ERC721 token (not supported).
     * @param token The ERC721 token address.
     */
    error JustaPermissionManager_ERC721TokenNotSupported(address token);

    /**
     * @notice Thrown when attempting to create a spend limit for an ERC1155 token (not supported).
     * @param token The ERC1155 token address.
     */
    error JustaPermissionManager_ERC1155TokenNotSupported(address token);

    /**
     * @notice Thrown when attempting to approve a permission with no calls and no spend limits.
     */
    error JustaPermissionManager_EmptyPermission();

    /**
     * @notice Thrown when attempting to create a call permission with a zero target address.
     */
    error JustaPermissionManager_ZeroTarget();

    /**
     * @notice Thrown when attempting to create a call permission with a zero selector.
     */
    error JustaPermissionManager_ZeroSelector();

    /**
     * @notice Thrown when the provided calldata is invalid or too short.
     */
    error JustaPermissionManager_InvalidCalldata();

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
        uint48 period;
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
     * @notice ERC-7528 native token address convention.
     */
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @notice EIP-712 typehashes
     */
    bytes32 public constant CALL_PERMISSION_TYPEHASH = keccak256("CallPermission(address target,bytes4 selector)");

    bytes32 public constant SPEND_LIMIT_TYPEHASH =
        keccak256("SpendLimit(address token,uint160 allowance,uint48 period)");

    bytes32 public constant PERMISSION_TYPEHASH = keccak256(
        "Permission(address account,address spender,uint48 start,uint48 end,uint256 salt,CallPermission[] calls,SpendLimit[] spends)CallPermission(address target,bytes4 selector)SpendLimit(address token,uint160 allowance,uint48 period)"
    );

    /**
     * @notice Permission is approved (hash of entire Permission struct).
     * @dev Maps permission hash to approval status.
     */
    mapping(bytes32 permissionHash => bool approved) internal _isApproved;

    /**
     * @notice Permission is revoked.
     * @dev Once revoked, a permission cannot be re-approved with the same hash.
     */
    mapping(bytes32 permissionHash => bool revoked) internal _isRevoked;

    /**
     * @notice Last updated period for each spend limit.
     * @dev Maps permission hash => spend limit hash => period tracking.
     * @dev Period tracking enables recurring spend limits that reset automatically.
     */
    mapping(bytes32 permissionHash => mapping(bytes32 spendLimitHash => PeriodSpend)) internal _lastUpdatedPeriod;

    /**
     * @notice Emitted when a permission is approved.
     * @param permissionHash The EIP-712 hash of the permission.
     * @param permission The complete permission that was approved.
     */
    event PermissionApproved(bytes32 indexed permissionHash, Permission permission);

    /**
     * @notice Emitted when a permission is revoked.
     * @param permissionHash The EIP-712 hash of the permission.
     */
    event PermissionRevoked(bytes32 indexed permissionHash);

    /**
     * @notice Emitted when a call is executed using a permission.
     * @param permissionHash The EIP-712 hash of the permission.
     * @param target The contract that was called.
     * @param selector The function selector that was called.
     */
    event CallExecuted(bytes32 indexed permissionHash, address indexed target, bytes4 indexed selector);

    /**
     * @notice Emitted when tokens are spent using a spend limit.
     * @param permissionHash The EIP-712 hash of the permission.
     * @param token The token that was spent.
     * @param periodSpend The current period with only the incremental spend amount.
     */
    event SpendLimitUsed(bytes32 indexed permissionHash, address indexed token, PeriodSpend periodSpend);

    /**
     * @notice Require that msg.sender matches expected sender.
     * @param sender The expected sender address.
     */
    modifier requireSender(address sender) {
        if (msg.sender != sender) {
            revert JustaPermissionManager_InvalidSender(msg.sender, sender);
        }
        _;
    }

    /**
     * @notice Approve a permission with call and spend limits.
     * @dev Validates all fields and hashes the entire permission - arrays not stored on-chain.
     * @dev The permission hash includes the domain separator for replay protection.
     * @param permission The complete permission with calls and spends arrays.
     * @return True if all checks passes.
     */
    function approve(Permission calldata permission) external requireSender(permission.account) returns (bool) {
        // Check spender is non-zero
        if (permission.spender == address(0)) {
            revert JustaPermissionManager_ZeroSpender();
        }

        // Check start is strictly before end
        if (permission.start >= permission.end) {
            revert JustaPermissionManager_InvalidStartEnd(permission.start, permission.end);
        }

        // Check permission is not empty
        if (permission.calls.length == 0 && permission.spends.length == 0) {
            revert JustaPermissionManager_EmptyPermission();
        }

        // Validate call permissions
        for (uint256 i = 0; i < permission.calls.length; i++) {
            // Check target is non-zero
            if (permission.calls[i].target == address(0)) {
                revert JustaPermissionManager_ZeroTarget();
            }

            // Check function selector is non-zero
            if (permission.calls[i].selector == bytes4(0)) {
                revert JustaPermissionManager_ZeroSelector();
            }
        }

        // Validate spend limits
        for (uint256 i = 0; i < permission.spends.length; i++) {
            // Check token is non-zero
            if (permission.spends[i].token == address(0)) {
                revert JustaPermissionManager_ZeroToken();
            }

            // Check allowance is non-zero
            if (permission.spends[i].allowance == 0) {
                revert JustaPermissionManager_ZeroAllowance();
            }

            // Check perios is non-zero
            if (permission.spends[i].period == 0) {
                revert JustaPermissionManager_ZeroPeriod();
            }

            // Check token is not an ERC-721 or ERC-1155
            if (permission.spends[i].token != NATIVE_TOKEN) {
                if (ERC165Checker.supportsInterface(permission.spends[i].token, type(IERC721).interfaceId)) {
                    revert JustaPermissionManager_ERC721TokenNotSupported(permission.spends[i].token);
                }
                if (ERC165Checker.supportsInterface(permission.spends[i].token, type(IERC1155).interfaceId)) {
                    revert JustaPermissionManager_ERC1155TokenNotSupported(permission.spends[i].token);
                }
            }
        }

        bytes32 hash = getHash(permission);

        // Return false early if spend permission is already revoked
        if (_isRevoked[hash]) {
            return false;
        }

        // Return early if spend permission is already approved
        if (_isApproved[hash]) {
            return true;
        }

        _isApproved[hash] = true;
        emit PermissionApproved(hash, permission);

        return true;
    }

    /**
     * @notice Revoke a permission as the account owner.
     * @dev Once revoked, the permission cannot be used or re-approved.
     * @param permission The permission to revoke (must match approved permission exactly).
     */
    function revoke(Permission calldata permission) external requireSender(permission.account) {
        _revoke(permission);
    }

    /**
     * @notice Revoke a permission as the spender.
     * @dev Allows spenders to voluntarily give up their permissions.
     * @param permission The permission to revoke (must match approved permission exactly).
     */
    function revokeAsSpender(Permission calldata permission) external requireSender(permission.spender) {
        _revoke(permission);
    }

    /**
     * @notice Execute a call using a permission.
     * @param permission The complete permission with all calls and spends.
     * @param call The specific call permission to execute (must be in permission.calls).
     * @param data The calldata to execute.
     */
    function executeCall(
        Permission calldata permission,
        CallPermission calldata call,
        bytes calldata data
    )
        external
        requireSender(permission.spender)
    {
        // Validate calldata has at least a selector
        if (data.length < 4) {
            revert JustaPermissionManager_InvalidCalldata();
        }

        bytes32 hash = getHash(permission);

        // Check permission is approved and not revoked
        _checkApprovedNotRevoked(hash);

        // Check permission time bounds
        _checkPermissionTimeBounds(permission.start, permission.end);

        // Verify the call is in this permission
        if (!_isCallInPermission(permission, call)) {
            revert JustaPermissionManager_UnauthorizedCall(call.target, call.selector);
        }

        // Validate calldata selector matches call permission selector
        bytes4 dataSelector = bytes4(data[:4]);
        if (call.selector != dataSelector) {
            revert JustaPermissionManager_UnauthorizedCall(call.target, dataSelector);
        }

        // Execute call
        _execute(permission.account, call.target, 0, data);

        emit CallExecuted(hash, call.target, call.selector);
    }

    /**
     * @notice Spend tokens using a spend limit.
     * @param permission The complete permission with all calls and spends.
     * @param spendLimit The specific spend limit to use (must be in permission.spends).
     * @param value Amount to spend.
     */
    function spend(
        Permission calldata permission,
        SpendLimit calldata spendLimit,
        uint160 value
    )
        external
        requireSender(permission.spender)
    {
        bytes32 hash = getHash(permission);

        // Check permission is approved and not revoked
        _checkApprovedNotRevoked(hash);

        // Verify the spend limit is in the permission
        if (!_isSpendLimitInPermission(permission, spendLimit)) {
            revert JustaPermissionManager_UnauthorizedPermission();
        }

        // Compute spend limit hash
        bytes32 spendLimitHash = _hashSpendLimit(spendLimit);

        // Use the spend limit
        _useSpendLimit(hash, spendLimitHash, spendLimit, value, permission.start, permission.end);

        // Transfer tokens
        _transferFrom(spendLimit.token, permission.account, permission.spender, value);
    }

    /// @notice Get if a permission is approved.
    ///
    /// @param permission Details of the permission.
    ///
    /// @return approved True if permission is approved.
    function isApproved(Permission calldata permission) external view returns (bool) {
        return _isApproved[getHash(permission)];
    }

    /// @notice Get if a permission is revoked.
    ///
    /// @param permission Details of the permission.
    ///
    /// @return revoked True if permission is revoked.
    function isRevoked(Permission calldata permission) external view returns (bool) {
        return _isRevoked[getHash(permission)];
    }

    /**
     * @notice Get last updated period for a spend limit.
     * @dev Returns the last period that was used for spending.
     * @dev If never used, returns a period with spend = 0.
     * @param permission The permission containing the spend limit.
     * @param spendLimit The specific spend limit to query.
     * @return The last updated period with cumulative spend.
     */
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

    /**
     * @notice Get current active period for a spend limit.
     * @dev Calculates the current period based on permission.start and spendLimit.period.
     * @dev Periods are fixed intervals from permission.start, not rolling windows.
     * @param permission The permission containing the spend limit.
     * @param spendLimit The specific spend limit to query.
     * @return The current period with cumulative spend so far.
     */
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

    /**
     * @notice Hash a complete permission using EIP-712.
     * @dev Follows EIP-712 standard for hashing arrays of structs.
     * @dev Includes domain separator for replay protection across chains and contracts.
     * @param permission The permission to hash.
     * @return The EIP-712 hash of the permission.
     */
    function getHash(Permission calldata permission) public view returns (bytes32) {
        // Hash each CallPermission individually according to EIP-712
        bytes32[] memory callHashes = new bytes32[](permission.calls.length);
        for (uint256 i = 0; i < permission.calls.length; i++) {
            callHashes[i] = _hashCallPermission(permission.calls[i]);
        }

        // Hash each SpendLimit individually according to EIP-712
        bytes32[] memory spendHashes = new bytes32[](permission.spends.length);
        for (uint256 i = 0; i < permission.spends.length; i++) {
            spendHashes[i] = _hashSpendLimit(permission.spends[i]);
        }

        // Hash the permission with EIP-712 domain separator
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

    /**
     * @notice Check if a call permission is in the permission's calls array.
     * @dev Searches through permission.calls[] for an exact match.
     * @param permission The permission to search.
     * @param call The call permission to find.
     * @return True if the call is in the permission's calls array.
     */
    function _isCallInPermission(
        Permission calldata permission,
        CallPermission calldata call
    )
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < permission.calls.length; i++) {
            if (permission.calls[i].target == call.target && permission.calls[i].selector == call.selector) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Check if a spend limit is in the permission's spends array.
     * @param permission The permission to search.
     * @param spendLimit The spend limit to find.
     * @return True if the spend limit is in the permission.
     */
    function _isSpendLimitInPermission(
        Permission calldata permission,
        SpendLimit calldata spendLimit
    )
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < permission.spends.length; i++) {
            if (_spendLimitMatches(permission.spends[i], spendLimit)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Check if two spend limits match exactly.
     * @dev Compares all three fields: token, allowance, and period.
     * @param a First spend limit.
     * @param b Second spend limit.
     * @return True if all fields match.
     */
    function _spendLimitMatches(SpendLimit calldata a, SpendLimit calldata b) internal pure returns (bool) {
        return a.token == b.token && a.allowance == b.allowance && a.period == b.period;
    }

    /**
     * @notice Compute the hash of a call permission.
     * @param call The call permission to hash.
     * @return The hash of the call permission.
     */
    function _hashCallPermission(CallPermission calldata call) internal pure returns (bytes32) {
        return keccak256(abi.encode(CALL_PERMISSION_TYPEHASH, call.target, call.selector));
    }

    /**
     * @notice Compute the hash of a spend limit.
     * @param spendLimit The spend limit to hash.
     * @return The hash of the spend limit.
     */
    function _hashSpendLimit(SpendLimit calldata spendLimit) internal pure returns (bytes32) {
        return keccak256(abi.encode(SPEND_LIMIT_TYPEHASH, spendLimit.token, spendLimit.allowance, spendLimit.period));
    }

    /**
     * @notice Internal function to revoke a permission.
     * @dev Idempotent - safe to call multiple times.
     * @param permission The permission to revoke.
     */
    function _revoke(Permission calldata permission) internal {
        bytes32 hash = getHash(permission);

        // Return early if spend permission is already revoked
        if (_isRevoked[hash]) {
            return;
        }

        _isRevoked[hash] = true;
        emit PermissionRevoked(hash);
    }

    /**
     * @notice Check if permission is approved and not revoked.
     * @dev Only validates approval status, not time bounds.
     * @dev Time bounds are checked separately where needed to avoid duplication.
     * @param hash The pre-computed hash of the permission.
     */
    function _checkApprovedNotRevoked(bytes32 hash) internal view {
        if (!_isApproved[hash] || _isRevoked[hash]) {
            revert JustaPermissionManager_UnauthorizedPermission();
        }
    }

    /**
     * @notice Check if current timestamp is within permission time bounds.
     * @dev Validates current time is in [start, end) range.
     * @param start The permission start timestamp.
     * @param end The permission end timestamp.
     * @return currentTimestamp The current block timestamp (returned to avoid duplicate reads).
     */
    function _checkPermissionTimeBounds(uint48 start, uint48 end) internal view returns (uint48 currentTimestamp) {
        currentTimestamp = uint48(block.timestamp);
        if (currentTimestamp < start) {
            revert JustaPermissionManager_BeforePermissionStart(currentTimestamp, start);
        }
        if (currentTimestamp >= end) {
            revert JustaPermissionManager_AfterPermissionEnd(currentTimestamp, end);
        }
    }

    /**
     * @notice Use a spend limit and update period tracking.
     * @dev Validates spend doesn't exceed allowance and updates the period state.
     * @param hash The permission hash.
     * @param spendLimitHash The hash of the spend limit.
     * @param spendLimit The spend limit being used.
     * @param value The amount to spend.
     * @param permissionStart The permission's start timestamp.
     * @param permissionEnd The permission's end timestamp.
     */
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
        // Check value is non-zero
        if (value == 0) {
            revert JustaPermissionManager_ZeroValue();
        }

        // Get or calculate current period
        PeriodSpend memory currentPeriod =
            _getCurrentPeriod(hash, spendLimitHash, spendLimit, permissionStart, permissionEnd);

        // Calculate total spend in this period
        uint256 totalSpend = value + uint256(currentPeriod.spend);

        // Check total spend value does not overflow max value
        if (totalSpend > type(uint160).max) {
            revert JustaPermissionManager_SpendValueOverflow(totalSpend);
        }

        // Check total spend value does not exceed spend permission
        if (totalSpend > spendLimit.allowance) {
            revert JustaPermissionManager_ExceededSpendLimit(totalSpend, spendLimit.allowance);
        }

        // Update period tracking with new total
        currentPeriod.spend = uint160(totalSpend);
        _lastUpdatedPeriod[hash][spendLimitHash] = currentPeriod;

        // Emit event with incremental spend only (not total)
        emit SpendLimitUsed(hash, spendLimit.token, PeriodSpend(currentPeriod.start, currentPeriod.end, uint160(value)));
    }

    /**
     * @notice Get or calculate the current active period for a spend limit.
     * @dev Periods are fixed intervals from permissionStart, not rolling windows.
     * @dev Period boundaries: [start + n*period, start + (n+1)*period) for n = 0,1,2...
     * @dev If last tracked period is still active, returns it; otherwise calculates new period.
     * @param hash The permission hash.
     * @param spendLimitHash The hash of the spend limit.
     * @param spendLimit The spend limit with period configuration.
     * @param permissionStart The permission's start timestamp.
     * @param permissionEnd The permission's end timestamp.
     * @return The current period with cumulative spend so far.
     */
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
        // Check permission time bounds and get current timestamp
        uint48 currentTimestamp = _checkPermissionTimeBounds(permissionStart, permissionEnd);

        // Check if we have a tracked period
        PeriodSpend memory lastUpdatedPeriod = _lastUpdatedPeriod[hash][spendLimitHash];

        // Period exists if spend is non-zero
        bool lastPeriodExists = lastUpdatedPeriod.spend != 0;

        // Period is still active if current timestamp within [start, end - 1] range
        bool lastPeriodStillActive = currentTimestamp < lastUpdatedPeriod.end;

        // Return existing period if still active
        if (lastPeriodExists && lastPeriodStillActive) {
            return lastUpdatedPeriod;
        }

        // Calculate new period boundaries
        // Progress since permission start, modulo period length
        uint48 periodProgress = (currentTimestamp - permissionStart) % spendLimit.period;
        // Period starts at current time minus progress
        uint48 periodStart = currentTimestamp - periodProgress;

        // Check if adding full period would exceed permission end
        bool endOverflow = uint256(periodStart) + uint256(spendLimit.period) > permissionEnd;
        // Use permission end if overflow, otherwise use calculated period end
        uint48 periodEnd = endOverflow ? permissionEnd : periodStart + spendLimit.period;

        return PeriodSpend({ start: periodStart, end: periodEnd, spend: 0 });
    }

    /**
     * @notice Transfer tokens from account to recipient.
     * @dev Handles both native tokens and ERC-20s using direct transfers.
     * @dev For native: account sends directly to recipient.
     * @dev For ERC-20: approve and use safeTransferFrom.
     * @param token The token address (NATIVE_TOKEN or ERC-20).
     * @param account The account to transfer from.
     * @param recipient The recipient address.
     * @param value The amount to transfer.
     */
    function _transferFrom(address token, address account, address recipient, uint256 value) internal {
        if (token == NATIVE_TOKEN) {
            // Have account send native token directly to recipient
            _execute({ account: account, target: recipient, value: value, data: hex"" });
        } else {
            // set allowance for this contract to spend exact value on behalf of account
            _execute({
                account: account,
                target: token,
                value: 0,
                data: abi.encodeWithSelector(IERC20.approve.selector, address(this), value)
            });

            // use allowance to transfer from account to recipient, which will revert if transfer fails
            IERC20(token).safeTransferFrom(account, recipient, value);
        }
    }

    /**
     * @notice Execute a call on behalf of an account.
     * @dev Virtual to allow overriding for different account implementations.
     * @param account The account to execute from.
     * @param target The contract to call.
     * @param value The amount of native token to send.
     * @param data The calldata to execute.
     */
    function _execute(address account, address target, uint256 value, bytes memory data) internal virtual {
        JustanAccount(payable(account)).execute({ target: target, value: value, data: data });
    }

    /**
     * @notice Get EIP-712 domain name and version.
     * @dev Required by EIP-712 for domain separator construction.
     * @return name The contract name for the domain separator.
     * @return version The version string for the domain separator.
     */
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "JustaPermissionManager";
        version = "1";
    }

}
