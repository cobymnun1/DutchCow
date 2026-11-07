// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/// @notice Minimal ERC20 with optional hostile behavior. Not a production token.
contract ZooToken {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    address public owner;

    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) public allowance;

    enum TaxMode { None, Recipient, SenderExtra, VaultOnly, Burn }

    TaxMode public taxMode;
    uint256 public taxBps;
    address public settlement;
    address public vaultRelayer;
    bool public usdtApprove;
    bool public falseReturn;
    bool public noReturnData;
    bool public capUint96;
    bool public paused;
    bool public lieHigh;
    bool public lieLow;
    address public reenter;
    int256 public rebaseBps;

    mapping(address => bool) public blocked;

    constructor(string memory n, uint8 dec) {
        name = n;
        symbol = n;
        decimals = dec;
        owner = msg.sender;
    }

    function configureTax(TaxMode mode, uint256 bps, address settlement_, address relayer_) external {
        taxMode = mode;
        taxBps = bps;
        settlement = settlement_;
        vaultRelayer = relayer_;
    }

    function setFlags(bool usdt_, bool falseRet, bool noReturn, bool uint96_, bool lieH, bool lieL) external {
        usdtApprove = usdt_;
        falseReturn = falseRet;
        noReturnData = noReturn;
        capUint96 = uint96_;
        lieHigh = lieH;
        lieLow = lieL;
    }

    function setPaused(bool v) external { paused = v; }
    function setBlocked(address a, bool v) external { blocked[a] = v; }
    function setReenter(address a) external { reenter = a; }
    function setRebaseBps(int256 bps) external { rebaseBps = bps; }

    function mint(address to, uint256 amount) external { _balances[to] += amount; totalSupply += amount; }

    function balanceOf(address account) public view returns (uint256) {
        if (lieHigh) return type(uint256).max;
        if (lieLow) return 0;
        uint256 raw = _balances[account];
        if (rebaseBps == 0 || raw == 0) return raw;
        if (rebaseBps > 0) return raw + (raw * uint256(rebaseBps) / 10_000);
        uint256 cut = raw * uint256(-rebaseBps) / 10_000;
        return raw > cut ? raw - cut : 0;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (capUint96 && amount > type(uint96).max) revert("Uint96");
        if (usdtApprove && amount != 0 && allowance[msg.sender][spender] != 0) revert("USDTApprove");
        allowance[msg.sender][spender] = amount;
        if (noReturnData) {
            assembly { return(0, 0) }
        }
        return !falseReturn;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        if (noReturnData) assembly { return(0, 0) }
        return !falseReturn;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        _move(from, to, amount);
        if (noReturnData) assembly { return(0, 0) }
        return !falseReturn;
    }

    function _move(address from, address to, uint256 amount) internal {
        require(!paused, "paused");
        require(!blocked[from] && !blocked[to], "blocked");
        if (reenter != address(0)) {
            (bool ok, bytes memory err) = reenter.call(abi.encodeWithSignature("onToken(address,address,uint256)", from, to, amount));
            if (!ok) {
                assembly { revert(add(err, 32), mload(err)) }
            }
        }
        if (falseReturn) return;

        uint256 fee;
        bool taxRecipient = taxMode == TaxMode.Recipient || taxMode == TaxMode.Burn
            || (taxMode == TaxMode.VaultOnly && (to == settlement || to == vaultRelayer));
        if (taxRecipient && taxBps > 0 && from != address(0)) {
            fee = amount * taxBps / 10_000;
        }
        uint256 debit = amount;
        if (taxMode == TaxMode.SenderExtra && taxBps > 0 && from != address(0)) {
            debit = amount + (amount * taxBps / 10_000);
        }
        require(_balances[from] >= debit, "balance");
        _balances[from] -= debit;
        _balances[to] += (amount - fee);
        if (taxMode == TaxMode.Burn && fee > 0) totalSupply -= fee;
    }
}

interface ITokenHook {
    function onToken(address from, address to, uint256 amount) external;
}
