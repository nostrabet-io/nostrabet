// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract Nostrabet is ERC20, ERC20Burnable {
    using Address for address;
    using SafeMath for uint256;
    mapping(address => bool) public feelessAccounts;
    mapping(address => bool) public betManager;
    address private genesis;
    address private _addressTracker;

    constructor(
        address privateSale,
        address syrupPool,
        address developerWallet,
        address marketingCampaign,
        address liquidityPool,
        address initialTokenOffering
    ) ERC20("Nostrabet", "NBET") {
        // Private sale address - 2%
        _mint(privateSale, 300000 * 10**decimals());
        feelessAccounts[privateSale] = true;
        // Syrup pool address - 3%
        _mint(syrupPool, 450000 * 10**decimals());
        feelessAccounts[syrupPool] = true;
        // Developers' address - 5%
        _mint(developerWallet, 750000 * 10**decimals());
        feelessAccounts[developerWallet] = true;
        // Marketing campaigns address - 5%
        _mint(marketingCampaign, 750000 * 10**decimals());
        feelessAccounts[marketingCampaign] = true;
        // Liquidity Pool address - 10%
        _mint(liquidityPool, 1500000 * 10**decimals());
        feelessAccounts[liquidityPool] = true;
        // Initial _ offering - 15%
        _mint(initialTokenOffering, 2250000 * 10**decimals());
        feelessAccounts[initialTokenOffering] = true;
        // Reward pool - 60%
        _mint(address(this), 9000000 * 10**decimals());
        _addressTracker = address(this);
        feelessAccounts[address(this)] = true;

        genesis = developerWallet;
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        // 2% burn rate on chain transactions
        uint256 fee = amount.mul(2).div(100);
        uint256 postTax = amount.sub(fee);
        _burn(_msgSender(), fee);
        _transfer(_msgSender(), recipient, postTax);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        // 2% burn rate on chain transactions
        uint256 fee = amount.mul(2).div(100);
        uint256 postTax = amount.sub(fee);
        _burn(sender, fee);
        _transfer(sender, recipient, postTax);
        return true;
    }

    function feelessTransfer(address recipient, uint256 amount)
        public
        returns (bool)
    {
        // only available to the addresses used for specific mechanisms (see constructor function)
        require(
            feelessAccounts[_msgSender()],
            "Feeless Transfer not available for this account."
        );
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function feelessTransferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public returns (bool) {
        // only available to the addresses used for specific mechanisms (see constructor function)
        require(
            feelessAccounts[_msgSender()],
            "Feeless Transfer not available for this account."
        );
        _transfer(sender, recipient, amount);
        return true;
    }

    function toggleBetManager(address toggleAddress) external onlyGenesis {
        betManager[toggleAddress] = !betManager[toggleAddress];
    }

    function transferGenesisAddress(address newGenesis) external onlyGenesis {
        genesis = newGenesis;
    }

    // Bet Factory Area
    Bet[] public openBets;
    mapping(Bet => bool) public previousBet;

    function createBet(
        string memory description,
        string memory expectedDate,
        string memory optionOne,
        string memory optionTwo,
        string memory title
    ) external onlyBetManager {
        Bet newBet = new Bet(
            Nostrabet(address(this)),
            _msgSender(),
            description,
            expectedDate,
            optionOne,
            optionTwo,
            title
        );
        openBets.push(newBet);
        feelessAccounts[address(newBet)] = true;
    }

    function removeBetFromOpenBets(address toBeRemoved)
        external
        onlyBetManager
    {
        for (uint256 index = 0; index < openBets.length; index++) {
            if (address(openBets[index]) == toBeRemoved) {
                previousBet[openBets[index]] = true;
                openBets[index] = openBets[openBets.length - 1];
                openBets.pop();
            }
        }
    }

    function getOpenBets() external view returns (Bet[] memory) {
        return openBets;
    }

    // Safe Bet Factory
    SafeBet[] public openSafeBets;
    mapping(SafeBet => bool) public previousSafeBet;

    function createSafeBet(
        string memory description,
        string memory expectedDate,
        string memory optionOne,
        string memory optionTwo,
        string memory title
    ) external onlyBetManager {
        uint256 rewards = balanceOf(_addressTracker).div(200);
        SafeBet newBet = new SafeBet(
            Nostrabet(address(this)),
            _msgSender(),
            description,
            expectedDate,
            optionOne,
            optionTwo,
            title,
            rewards
        );
        openSafeBets.push(newBet);
        feelessAccounts[address(newBet)] = true;
        // Gives 0.5% of current reward pool to new safe bet
        feelessTransferFrom(_addressTracker, address(newBet), rewards);
    }

    function removeBetFromOpenSafeBets(address toBeRemoved)
        external
        onlyBetManager
    {
        for (uint256 index = 0; index < openSafeBets.length; index++) {
            if (address(openSafeBets[index]) == toBeRemoved) {
                previousSafeBet[openSafeBets[index]] = true;
                openSafeBets[index] = openSafeBets[openSafeBets.length - 1];
                openSafeBets.pop();
            }
        }
    }

    function getOpenSafeBets() external view returns (SafeBet[] memory) {
        return openSafeBets;
    }

    // Modifiers
    modifier onlyBetManager {
        require(betManager[_msgSender()], "Account is not a bet manager.");
        _;
    }

    modifier onlyGenesis {
        require(_msgSender() == genesis, "Only available for genesis address.");
        _;
    }
}

contract Bet {
    Nostrabet private _token;
    address private _manager;
    mapping(address => uint256) public betStatus;
    mapping(address => uint256) public amountBet;
    uint256 public amountOptionOne;
    uint256 public amountOptionTwo;
    uint256 public amountTotal;
    uint256 public _winner;
    // 0 = open, 1 = complete, 2 = canceled
    uint256 public _status;

    string public _description;
    string public _expectedDate;
    string public _optionOne;
    string public _optionTwo;
    string public _title;

    using SafeMath for uint256;

    constructor(
        Nostrabet token,
        address manager,
        string memory description,
        string memory expectedDate,
        string memory optionOne,
        string memory optionTwo,
        string memory title
    ) {
        _token = token;
        _manager = manager;
        _description = description;
        _expectedDate = expectedDate;
        _optionOne = optionOne;
        _optionTwo = optionTwo;
        _title = title;
    }

    function castBet(uint256 option, uint256 amount) external {
        require(_status == 0, "Bet is not open");
        require(option == 1 || option == 2, "Invalid bet option.");
        address from = msg.sender;

        _token.feelessTransferFrom(from, address(this), amount);
        // this second set of requires below allow for the player to
        // increase his bet only if he's betting on the same result
        if (option == 1) {
            require(
                betStatus[from] == 0 || betStatus[from] == 1,
                "Can only bet on an option you already bet on."
            );
            amountOptionOne += amount;
            betStatus[from] = option;
            amountTotal += amount;
            amountBet[from] += amount;
        } else {
            require(
                betStatus[from] == 0 || betStatus[from] == 2,
                "Can only bet on an option you already bet on."
            );
            amountOptionTwo += amount;
            betStatus[from] = option;
            amountTotal += amount;
            amountBet[from] += amount;
        }
    }

    function setWinner(uint256 winner) public onlyManager {
        require(winner == 1 || winner == 2, "Invalid winner option.");
        _winner = winner;
    }

    function cancelBet() public onlyManager {
        // Can only cancel an open bet
        require(_status == 0, "Bet is not open.");
        _status = 2;
    }

    function closeBet() public onlyManager {
        // Can only close an open bet
        require(_status == 0, "Bet is not open.");
        uint256 fee;
        fee = amountTotal.div(200);
        amountTotal -= fee.mul(2);
        // Returns half a percent to the reward pool
        _token.feelessTransfer(address(_token), fee);
        // Gives half a percent to the bet manager
        _token.feelessTransfer(_manager, fee);
        _status = 1;
    }

    function collectWinnings() public {
        uint256 earnings;

        // Bet isn't open
        require(_status != 0, "Bet is still open.");

        // Bet closed successfully
        if (_status == 1) {
            // Has stake in the winners pool
            require(
                betStatus[msg.sender] == _winner,
                "Address not in winners list."
            );
            if (_winner == 1) {
                earnings = amountBet[msg.sender].mul(amountTotal).div(
                    amountOptionOne
                );
            } else {
                earnings = amountBet[msg.sender].mul(amountTotal).div(
                    amountOptionTwo
                );
            }
            betStatus[msg.sender] = 0;
            _token.feelessTransfer(msg.sender, earnings);
        }
        // Bet cancelled
        else {
            require(
                betStatus[msg.sender] != 0,
                "Not a participant of this bet."
            );
            betStatus[msg.sender] = 0;
            earnings = amountBet[msg.sender];
            _token.feelessTransfer(msg.sender, earnings);
        }
    }

    modifier onlyManager() {
        require(msg.sender == _manager, "Not a manager.");
        _;
    }
}

contract SafeBet {
    Nostrabet private _token;
    address private _manager;
    mapping(address => uint256) public betStatus;
    mapping(address => uint256) public amountBet;
    uint256 public amountOptionOne;
    uint256 public amountOptionTwo;
    uint256 public rewards;
    uint256 public _winner;
    // 0 = open, 1 = complete, 2 = canceled
    uint256 public _status;

    string public _description;
    string public _expectedDate;
    string public _optionOne;
    string public _optionTwo;
    string public _title;

    using SafeMath for uint256;

    constructor(
        Nostrabet token,
        address manager,
        string memory description,
        string memory expectedDate,
        string memory optionOne,
        string memory optionTwo,
        string memory title,
        uint256 rewardAllocated
    ) {
        _token = token;
        _manager = manager;
        _description = description;
        _expectedDate = expectedDate;
        _optionOne = optionOne;
        _optionTwo = optionTwo;
        _title = title;
        rewards = rewardAllocated;
    }

    function castBet(uint256 option, uint256 amount) external {
        require(_status == 0, "Bet is not open.");
        require(option == 1 || option == 2, "Invalid betting option.");
        address from = msg.sender;

        _token.feelessTransferFrom(from, address(this), amount);
        // this second set of requires below allow for the player to
        // increase his bet only if he's betting on the same result
        if (option == 1) {
            require(
                betStatus[from] == 0 || betStatus[from] == 1,
                "Can only bet on an option you already bet on."
            );
            amountOptionOne += amount;
            betStatus[from] = option;
            amountBet[from] += amount;
        } else {
            require(
                betStatus[from] == 0 || betStatus[from] == 2,
                "Can only bet on an option you already bet on."
            );
            amountOptionTwo += amount;
            betStatus[from] = option;
            amountBet[from] += amount;
        }
    }

    function setWinner(uint256 winner) public onlyManager {
        require(winner == 1 || winner == 2, "Invalid winner option.");
        _winner = winner;
    }

    function cancelBet() public onlyManager {
        // Can only cancel an open bet
        require(_status == 0, "Bet is not open.");
        _status = 2;
    }

    function closeBet() public onlyManager {
        // Can only close an open bet
        require(_status == 0, "Bet is not open.");
        _status = 1;
    }

    function collectWinnings() public {
        uint256 earnings;

        // Bet isn't open
        require(_status != 0, "Bet is still open.");
        require(betStatus[msg.sender] != 0, "Not a participant.");
        // Bet closed successfully
        if (_status == 1) {
            // Has stake in the winners pool
            if (betStatus[msg.sender] == _winner) {
                if (_winner == 1) {
                    earnings = amountBet[msg.sender]
                    .mul(rewards)
                    .div(amountOptionOne)
                    .add(amountBet[msg.sender]);
                } else {
                    earnings = amountBet[msg.sender]
                    .mul(rewards)
                    .div(amountOptionTwo)
                    .add(amountBet[msg.sender]);
                }
            }
            // Did not win (still able to withdraw same amount that was deposited)
            else {
                earnings = amountBet[msg.sender];
            }
            betStatus[msg.sender] = 0;
            _token.feelessTransfer(msg.sender, earnings);
        }
        // Bet cancelled
        else {
            require(
                betStatus[msg.sender] != 0,
                "Not a participant of this bet."
            );
            earnings = amountBet[msg.sender];
            betStatus[msg.sender] = 0;
            _token.feelessTransfer(msg.sender, earnings);
        }
    }

    modifier onlyManager() {
        require(msg.sender == _manager, "Not a manager.");
        _;
    }
}
