// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IAgentID
/// @notice Minimal interface for SPACE ID / Binance Agent ID (non-transferable ERC-721 `name.ai`).
/// @dev BNB Smart Chain Mainnet address: 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F
interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title AgentPassRegistry
/// @notice Zero-custody, ownerless on-chain pass, AI endpoint directory, and Sybil-resistant
///         reputation layer gated exclusively by Binance Agent ID (`name.ai`) on BNB Smart Chain.
/// @dev Security posture (explicitly disclosed for hackathon review):
///      - No owner or admin role (fully immutable and permissionless).
///      - No pause, no mint, no blacklist, no fees, and no BNB/token custody.
///      - Every write action requires `AGENT_ID.balanceOf(msg.sender) > 0` (1 KYC-verified Agent ID per user).
///      - Active passes (`hasActivePass(address)`) are verified trustlessly via BSC RPC by the
///        Zero-Proxy AI Intelligence Gateway to grant Agent ID holders free access to 7 live web
///        intelligence APIs (SEC EDGAR, Polymarket, Markdown, Website Enrich, YC, Shopify, News).
contract AgentPassRegistry {
    /// @notice Official SPACE ID / Binance Agent ID ERC-721 contract on BNB Smart Chain.
    IAgentID public immutable AGENT_ID;

    /// @notice Duration of each activated Intelligence Pass (24 hours).
    uint64 public constant PASS_DURATION = 1 days;

    /// @notice Maximum allowed length for optional `.ai` handle label (excluding suffix).
    uint256 public constant MAX_LABEL_LEN = 32;

    /// @notice Maximum allowed length for MCP / x402 endpoint URL.
    uint256 public constant MAX_URL_LEN = 200;

    /// @notice Maximum allowed length for capabilities description.
    uint256 public constant MAX_CAPABILITIES_LEN = 240;

    /// @notice Maximum allowed length for an endorsement note.
    uint256 public constant MAX_NOTE_LEN = 160;

    struct AgentProfile {
        bool activated;
        bool hasEndpoint;
        bool labelVerified;
        uint64 passExpiry;
        uint32 lastClaimDay;
        uint32 streak;
        uint32 passCount;
        uint32 endorsements;
        string label;
        string endpointUrl;
        string capabilities;
    }

    struct DirectoryEntry {
        address agent;
        bool activePass;
        bool labelVerified;
        uint64 passExpiry;
        uint32 streak;
        uint32 endorsements;
        string label;
        string endpointUrl;
        string capabilities;
    }

    /// @notice Total unique Agent ID wallets that have interacted with this contract.
    uint256 public uniqueAgents;

    /// @notice Total Intelligence Passes claimed across all agents.
    uint256 public totalPasses;

    /// @notice Total unique Agent ID holders with a published MCP / x402 endpoint.
    uint256 public totalEndpoints;

    /// @notice Total Sybil-resistant peer endorsements recorded on-chain.
    uint256 public totalEndorsements;

    mapping(address => AgentProfile) private _profiles;
    mapping(address => mapping(address => bool)) public endorsed;
    address[] private _directoryAgents;

    event PassClaimed(
        address indexed agent,
        uint64 expiry,
        uint32 streak,
        uint32 passCount,
        string label,
        bool labelVerified
    );

    event AgentEndpointRegistered(
        address indexed agent,
        string endpointUrl,
        string capabilities,
        uint64 passExpiry
    );

    event AgentEndorsed(
        address indexed from,
        address indexed target,
        string note,
        uint32 newEndorsements
    );

    error ZeroAddress();
    error NoAgentID();
    error TargetHasNoAgentID();
    error InvalidLabel();
    error InvalidEndpointUrl();
    error InvalidCapabilities();
    error NoteTooLong();
    error SelfEndorse();
    error AlreadyEndorsed();

    modifier onlyAgent() {
        if (AGENT_ID.balanceOf(msg.sender) == 0) revert NoAgentID();
        _;
    }

    constructor(address _agentId) {
        if (_agentId == address(0)) revert ZeroAddress();
        AGENT_ID = IAgentID(_agentId);
    }

    /// @notice Returns true if `user` holds a non-transferable Binance Agent ID NFT.
    function hasAgentID(address user) public view returns (bool) {
        if (user == address(0)) return false;
        return AGENT_ID.balanceOf(user) > 0;
    }

    /// @notice Returns true if `user` holds an Agent ID AND has a currently valid 24h Intelligence Pass.
    function hasActivePass(address user) external view returns (bool) {
        if (user == address(0)) return false;
        return AGENT_ID.balanceOf(user) > 0 && _profiles[user].passExpiry > block.timestamp;
    }

    /// @notice Claim or extend a 24-hour Intelligence Pass on BNB Smart Chain.
    /// @param rawLabel Optional `name.ai` handle (or empty string ""). Stored normalized without `.ai`.
    function claimPass(string calldata rawLabel) external onlyAgent {
        AgentProfile storage p = _profiles[msg.sender];
        _markActivated(p);

        if (bytes(rawLabel).length > 0) {
            string memory norm = _normalizeLabel(rawLabel);
            p.label = norm;
            p.labelVerified = _tryVerifyLabelOwner(norm, msg.sender);
        }

        uint32 today = uint32(block.timestamp / 1 days);
        if (p.lastClaimDay == 0) {
            p.streak = 1;
            p.lastClaimDay = today;
        } else if (today > p.lastClaimDay) {
            p.streak = (today == p.lastClaimDay + 1) ? p.streak + 1 : 1;
            p.lastClaimDay = today;
        }

        uint64 newExpiry = uint64(block.timestamp) + PASS_DURATION;
        p.passExpiry = newExpiry;
        p.passCount += 1;
        totalPasses += 1;

        emit PassClaimed(msg.sender, newExpiry, p.streak, p.passCount, p.label, p.labelVerified);
    }

    /// @notice Bind an autonomous AI Agent's MCP / x402 / A2A endpoint to its on-chain Agent ID.
    /// @dev Also activates/refreshes the caller's 24h Intelligence Pass in the same transaction.
    function registerAgentEndpoint(
        string calldata endpointUrl,
        string calldata capabilities
    ) external onlyAgent {
        uint256 urlLen = bytes(endpointUrl).length;
        uint256 capLen = bytes(capabilities).length;
        if (urlLen < 8 || urlLen > MAX_URL_LEN) revert InvalidEndpointUrl();
        if (capLen == 0 || capLen > MAX_CAPABILITIES_LEN) revert InvalidCapabilities();

        AgentProfile storage p = _profiles[msg.sender];
        _markActivated(p);

        if (!p.hasEndpoint) {
            p.hasEndpoint = true;
            totalEndpoints += 1;
            _directoryAgents.push(msg.sender);
        }

        p.endpointUrl = endpointUrl;
        p.capabilities = capabilities;

        uint64 newExpiry = uint64(block.timestamp) + PASS_DURATION;
        if (newExpiry > p.passExpiry) {
            p.passExpiry = newExpiry;
        }

        emit AgentEndpointRegistered(msg.sender, endpointUrl, capabilities, p.passExpiry);
    }

    /// @notice Sybil-resistant 1-Agent-ID-to-1-Agent-ID endorsement for verified BNB Chain AI agents.
    function endorseAgent(address target, string calldata note) external onlyAgent {
        if (target == address(0)) revert ZeroAddress();
        if (target == msg.sender) revert SelfEndorse();
        if (AGENT_ID.balanceOf(target) == 0) revert TargetHasNoAgentID();
        if (endorsed[msg.sender][target]) revert AlreadyEndorsed();
        if (bytes(note).length > MAX_NOTE_LEN) revert NoteTooLong();

        _markActivated(_profiles[msg.sender]);
        endorsed[msg.sender][target] = true;

        AgentProfile storage tp = _profiles[target];
        tp.endorsements += 1;
        totalEndorsements += 1;

        emit AgentEndorsed(msg.sender, target, note, tp.endorsements);
    }

    /// @notice Read complete profile and live pass status for an address in a single RPC call.
    function getAgentProfile(address user)
        external
        view
        returns (
            bool hasId,
            bool activePass,
            bool labelVerified,
            uint64 expiry,
            uint32 streak,
            uint32 passes,
            uint32 endorsements,
            string memory label,
            string memory endpointUrl,
            string memory capabilities
        )
    {
        hasId = hasAgentID(user);
        AgentProfile storage p = _profiles[user];
        activePass = hasId && p.passExpiry > block.timestamp;
        return (
            hasId,
            activePass,
            p.labelVerified,
            p.passExpiry,
            p.streak,
            p.passCount,
            p.endorsements,
            p.label,
            p.endpointUrl,
            p.capabilities
        );
    }

    /// @notice Aggregate on-chain protocol statistics for dashboards and hackathon review.
    function getStats()
        external
        view
        returns (
            uint256 uniqueAgentsCount,
            uint256 totalPassesCount,
            uint256 totalEndpointsCount,
            uint256 totalEndorsementsCount
        )
    {
        return (uniqueAgents, totalPasses, totalEndpoints, totalEndorsements);
    }

    /// @notice Paginated read of the Sybil-resistant on-chain AI Agent Endpoint Directory.
    function getDirectory(uint256 offset, uint256 limit)
        external
        view
        returns (DirectoryEntry[] memory entries, uint256 total)
    {
        total = _directoryAgents.length;
        if (offset >= total || limit == 0) {
            return (new DirectoryEntry[](0), total);
        }
        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 count = end - offset;
        entries = new DirectoryEntry[](count);

        for (uint256 i = 0; i < count; i++) {
            address agent = _directoryAgents[offset + i];
            AgentProfile storage p = _profiles[agent];
            bool active = AGENT_ID.balanceOf(agent) > 0 && p.passExpiry > block.timestamp;
            entries[i] = DirectoryEntry({
                agent: agent,
                activePass: active,
                labelVerified: p.labelVerified,
                passExpiry: p.passExpiry,
                streak: p.streak,
                endorsements: p.endorsements,
                label: p.label,
                endpointUrl: p.endpointUrl,
                capabilities: p.capabilities
            });
        }
    }

    function _markActivated(AgentProfile storage p) internal {
        if (!p.activated) {
            p.activated = true;
            uniqueAgents += 1;
        }
    }

    function _normalizeLabel(string calldata rawLabel) internal pure returns (string memory) {
        bytes memory src = bytes(rawLabel);
        uint256 len = src.length;
        if (len == 0 || len > MAX_LABEL_LEN + 3) revert InvalidLabel();

        // Strip trailing ".ai" (case-insensitive) if provided
        if (
            len > 3 &&
            src[len - 3] == "." &&
            (src[len - 2] == "a" || src[len - 2] == "A") &&
            (src[len - 1] == "i" || src[len - 1] == "I")
        ) {
            len -= 3;
        }
        if (len == 0 || len > MAX_LABEL_LEN) revert InvalidLabel();

        bytes memory out = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            bytes1 c = src[i];
            if (c >= "A" && c <= "Z") {
                c = bytes1(uint8(c) + 32);
            }
            bool ok = (c >= "a" && c <= "z") || (c >= "0" && c <= "9") || (c == "-");
            if (!ok) revert InvalidLabel();
            if ((i == 0 || i == len - 1) && c == "-") revert InvalidLabel();
            out[i] = c;
        }
        return string(out);
    }

    function _tryVerifyLabelOwner(string memory normLabel, address expected) internal view returns (bool) {
        uint256 tokenId = uint256(keccak256(bytes(normLabel)));
        try AGENT_ID.ownerOf(tokenId) returns (address ownerAddr) {
            return ownerAddr == expected;
        } catch {
            return false;
        }
    }
}
