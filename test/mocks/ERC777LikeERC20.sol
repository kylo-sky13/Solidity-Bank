// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

interface IERC777Hook {
    function tokensReceived() external;
}

contract ERC777LikeERC20 is ERC20 {
    address public hook;

    constructor() ERC20("777Like", "777") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setHook(address _hook) external {
        hook = _hook;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool ok = super.transfer(to, amount);
        if (hook != address(0)) {
            IERC777Hook(hook).tokensReceived();
        }
        return ok;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool ok = super.transferFrom(from, to, amount);
        if (hook != address(0)) {
            IERC777Hook(hook).tokensReceived();
        }
        return ok;
    }
}
