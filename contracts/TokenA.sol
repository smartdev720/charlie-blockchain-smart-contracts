// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenA is ERC20 {
    constructor() ERC20("TokenA", "TA") {
        // Mint the initial supply to the contract deployer
        _mint(msg.sender, 10 * 10 * 10**decimals());
    }

    /**
     * @dev Mint new tokens. Only the owner can call this.
     * @param to The address to receive the newly minted tokens.
     * @param amount The amount of tokens to mint.
     */

    /**
     * @dev Burn tokens from the caller's account.
     * @param amount The amount of tokens to burn.
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
