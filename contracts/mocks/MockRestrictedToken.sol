// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockRestrictedToken is ERC20 {
    address public router;

    constructor(address _router) ERC20("Restricted", "RST") {
        router = _router;
    }

    function setRouter(address r) external {
        router = r;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(msg.sender == router, "transfer restricted");
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(msg.sender == router, "transferFrom restricted");
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }
}
