// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title MockAgentID
/// @notice Local unit-test stand-in for SPACE ID / Binance Agent ID (ERC-721 non-transferable).
contract MockAgentID {
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _owners;

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "ERC721NonexistentToken");
        return o;
    }

    function mintWithLabel(address to, string calldata label) external {
        require(_balances[to] == 0, "Already holds Agent ID");
        uint256 tokenId = uint256(keccak256(bytes(label)));
        _balances[to] = 1;
        _owners[tokenId] = to;
    }

    function mintArbitraryId(address to, uint256 tokenId) external {
        require(_balances[to] == 0, "Already holds Agent ID");
        _balances[to] = 1;
        _owners[tokenId] = to;
    }
}
