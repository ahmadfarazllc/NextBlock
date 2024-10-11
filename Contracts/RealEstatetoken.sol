// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import OpenZeppelin contracts
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "./CountersUpgradeable.sol"; // Custom CountersUpgradeable


// Multi-Signature Wallet Interface
interface IMultiSigWallet {
    function submitTransaction(address destination, uint256 value, bytes calldata data) external returns (uint256);
    function confirmTransaction(uint256 transactionId) external;
}

/**
 * @title NextBlockToken
 * @dev Custom ERC20 contract for fractional property ownership tokens.
 */
contract NextBlockToken is ERC20 {
    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) ERC20(_name, _symbol) {
        _mint(msg.sender, _initialSupply);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

using CountersUpgradeable for CountersUpgradeable.Counter;

/**
 * @title NextBlockXGovernance
 * @dev A real estate tokenization platform with integrated governance, KYC verification, and revenue collection.
 */
abstract contract NextBlockXGovernance is 
    ERC721, 
    Ownable, 
    ReentrancyGuard, 
    Governor, 
    GovernorSettings, 
    GovernorCountingSimple, 
    GovernorVotes, 
    GovernorVotesQuorumFraction, 
    GovernorTimelockControl
{
    CountersUpgradeable.Counter private _tokenIdCounter;

    struct Property {
        string location;
        uint256 value;
        address owner;
        uint256 tokenSupply;
        uint256 tokenPrice;
        address propertyToken;
        uint256 rentalIncome;
        uint256 lastAppraisalValue;
        bool isVesting;
        uint256 vestingPeriod;
        uint256 vestingAmount;
        uint256 lockPeriod;
        uint256 lockedTokens;
    }

    mapping(uint256 => Property) public properties;
    mapping(address => uint256[]) public userProperties;
    mapping(address => bool) public verifiedUsers;  // Mapping to store KYC-verified users
    mapping(uint256 => address[]) public tokenHolders;

    uint256 public constant MAX_FEE_PERCENTAGE = 10;  // Maximum fee percentage
    uint256 public fees;  // Platform-wide fee percentage (out of 100%)
    address payable public feeCollector;  // Address collecting the fees
    address public multiSigWallet;

    // Events
    event PropertyTokenized(uint256 indexed tokenId, string location, uint256 value, uint256 tokenSupply, uint256 tokenPrice, address propertyToken);
    event TokensPurchased(uint256 indexed tokenId, address indexed buyer, uint256 amount, uint256 totalPrice);
    event RentalIncomeDistributed(uint256 indexed tokenId, uint256 amount, address[] recipients);
    event PropertyAppraised(uint256 indexed tokenId, uint256 newAppraisalValue);
    event TokensVested(uint256 indexed tokenId, address indexed user, uint256 amount);
    event TokensLocked(uint256 indexed tokenId, address indexed user, uint256 amount, uint256 lockPeriod);
    event TokensUnlocked(uint256 indexed tokenId, address indexed user, uint256 amount);
    event FeeCollected(uint256 indexed tokenId, address indexed from, uint256 amount);

    event UserVerified(address indexed user, bool isVerified);  // New Event: User verified or unverified

    modifier onlyVerified() {
        require(verifiedUsers[msg.sender], "User  is not KYC verified.");
        _;
    }

    /**
     * @dev Constructor to initialize governance settings, multi-sig wallet, and fee collection.
     * @param _governanceToken Governance token used for voting.
     * @param _timelock Timelock contract for proposal execution delay.
     * @param _feeCollector Address where the platform fees are collected.
     */
    constructor(IVotes _governanceToken, TimelockController _timelock, address payable _feeCollector)
        ERC721("NextBlockToken", "NBT")
        Governor("NextBlockGovernor")
        GovernorSettings(1 /* voting delay: 1 block */,  45818 /* voting period: 1 week */, 4 /* quorum: 4% */)
        GovernorCountingSimple()
        GovernorVotes(_governanceToken)
        GovernorVotesQuorumFraction(4 /* quorum fraction: 4% */)
        GovernorTimelockControl(_timelock)
    {
        feeCollector = _feeCollector;
        multiSigWallet = address(new MultiSigWallet(address(this), 2));  // Create a new multi-sig wallet with 2 required signatures
    }

    /**
     * @dev Tokenize a new property and mint corresponding tokens.
     * @param _location Property location.
     * @param _value Property value.
     * @param _tokenSupply Total token supply.
     * @param _tokenPrice Token price.
     * @param _rentalIncome Rental income.
     * @param _lastAppraisalValue Last appraisal value.
     * @param _isVesting Whether the property is vesting.
     * @param _vestingPeriod Vesting period.
     * @param _vestingAmount Vesting amount.
     * @param _lockPeriod Lock period.
     */
    function tokenizeProperty(
        string memory _location,
        uint256 _value,
        uint256 _tokenSupply,
        uint256 _tokenPrice,
        uint256 _rentalIncome,
        uint256 _lastAppraisalValue,
        bool _isVesting,
        uint256 _vestingPeriod,
        uint256 _vestingAmount,
        uint256 _lockPeriod
    ) public onlyVerified {
        // Validate input values
        require(_tokenSupply > 0, "Token supply must be greater than 0.");
        require(_tokenPrice > 0, "Token price must be greater than 0.");
        require(_rentalIncome >= 0, "Rental income must be non-negative.");
        require(_lastAppraisalValue >= 0, "Last appraisal value must be non-negative.");
        require(_vestingPeriod >= 0, "Vesting period must be non-negative.");
        require(_vestingAmount >= 0, "Vesting amount must be non-negative.");
        require(_lockPeriod >= 0, "Lock period must be non-negative.");

        // Create a new property token
        NextBlockToken propertyToken = new NextBlockToken("Property Token", "PT", _tokenSupply);

        // Create a new property struct
        Property memory newProperty = Property(
            _location,
            _value,
            msg.sender,
            _tokenSupply,
            _tokenPrice,
            address(propertyToken),
            _rentalIncome,
            _lastAppraisalValue,
            _isVesting,
            _vestingPeriod,
            _vestingAmount,
            _lockPeriod,
            0
        );

        // Add the property to the mapping
        uint256 newTokenId = _tokenIdCounter.current();
        properties[newTokenId] = newProperty;
        userProperties[msg.sender].push(newTokenId);
        tokenHolders[newTokenId].push(msg.sender);

        // Emit event
        emit PropertyTokenized(newTokenId, _location, _value, _tokenSupply, _tokenPrice, address(propertyToken));

        // Increment token ID counter
        _tokenIdCounter.increment();
    }

    /**
     * @dev Purchase tokens for a property.
     * @param _tokenId Property token ID.
     * @param _amount Number of tokens to purchase.
     */
    function purchaseTokens(uint256 _tokenId, uint256 _amount) public onlyVerified {
        // Validate input values
        require(_amount > 0, "Amount must be greater than 0.");

        // Get the property details
        Property storage property = properties[_tokenId];

        // Calculate the total cost
        uint256 totalCost = _amount * property.tokenPrice;

        // Check if the user has sufficient balance
        require(msg.sender.balance >= totalCost, "Insufficient balance.");

        // Transfer tokens from the property token contract to the buyer
        NextBlockToken(property.propertyToken).transfer(msg.sender, _amount);

        // Update the token holders mapping
        tokenHolders[_tokenId].push(msg.sender);

        // Emit event
        emit TokensPurchased(_tokenId, msg.sender, _amount, totalCost);
    }

    /**
     * @dev Distribute rental income to token holders.
     * @param _tokenId Property token ID.
     * @param _amount Rental income amount.
     */
    function distributeRentalIncome(uint256 _tokenId, uint256 _amount) public {
        // Validate input values
        require(_amount > 0, "Amount must be greater than 0.");

        // Get the property details
        Property storage property = properties[_tokenId];

        // Calculate the distribution amount for each token holder
        uint256 distributionAmount = _amount / property.tokenSupply;

        // Distribute the rental income to token holders
        for (uint256 i = 0; i < tokenHolders[_tokenId].length; i++) {
            address tokenHolder = tokenHolders[_tokenId][i];
            tokenHolder.transfer(distributionAmount);
        }

        // Emit event
        emit RentalIncomeDistributed(_tokenId, _amount, tokenHolders[_tokenId]);
    }

    /**
     * @dev Appraise a property and update its value.
     * @param _tokenId Property token ID.
     * @param _newAppraisalValue New appraisal value.
     */
    function appraiseProperty(uint256 _tokenId, uint256 _newAppraisalValue) public {
        // Validate input values
        require(_newAppraisalValue >= 0, "New appraisal value must be non-negative.");

        // Get the property details
        Property storage property = properties[_tokenId];

        // Update the property's appraisal value
        property.lastAppraisalValue = _newAppraisalValue;

        // Emit event
        emit PropertyAppraised(_tokenId, _newAppraisalValue);
    }

    /**
     * @dev Vest tokens for a user.
     * @param _tokenId Property token ID.
     * @param _user User address.
     * @param _amount Number of tokens to vest.
     */
    function vestTokens(uint256 _tokenId, address _user, uint256 _amount) public {
        // Validate input values
        require(_amount > 0, "Amount must be greater than 0.");

        // Get the property details
        Property storage property = properties[_tokenId];

        // Check if the property is vesting
        require(property.isVesting, "Property is not vesting.");

        // Calculate the vesting amount
        uint256 vestingAmount = _amount * property.vestingAmount / 100;

        // Vest tokens for the user
        NextBlockToken(property.propertyToken).transfer(_user, vestingAmount);

        // Emit event
        emit TokensVested(_tokenId, _user, vestingAmount);
    }

    /**
     * @dev Lock tokens for a user.
     * @param _tokenId Property token ID.
     * @param _user User address.
     * @param _amount Number of tokens to lock.
     * @param _lockPeriod Lock period.
     */
    function lockTokens(uint256 _tokenId, address _user, uint256 _amount, uint256 _lockPeriod) public {
        // Validate input values
        require(_amount > 0, "Amount must be greater than 0.");
        require(_lockPeriod > 0, "Lock period must be greater than 0.");

        // Get the property details
        Property storage property = properties[_tokenId];

        // Lock tokens for the user
        property.lockedTokens += _amount;

        // Emit event
        emit TokensLocked(_tokenId, _user, _amount, _lockPeriod);
    }

    /**
     * @dev Unlock tokens for a user.
     * @param _tokenId Property token ID.
     * @param _user User address.
     * @param _amount Number of tokens to unlock.
     */
    function unlockTokens(uint256 _tokenId, address _user, uint256 _amount) public {
        // Validate input values
        require(_amount > 0, "Amount must be greater than 0.");

        // Get the property details
        Property storage property = properties[_tokenId];

        // Check if the user has sufficient locked tokens
        require(property.lockedTokens >= _amount, "Insufficient locked tokens.");

        // Unlock tokens for the user
        property.lockedTokens -= _amount;

        // Emit event
        emit TokensUnlocked(_tokenId, _user, _amount);
    }

    /**
     * @dev Collect fees from a user.
     * @param _tokenId Property token ID.
     * @param _user User address.
     * @param _amount Fee amount.
     */
    function collectFees(uint256 _tokenId, address _user, uint256 _amount) public {
        // Validate input values
        require(_amount > 0, "Amount must be greater than 0.");

        // Get the property details
        Property storage property = properties[_tokenId];

        // Check if the user has sufficient balance
        require(_user.balance >= _amount, "Insufficient balance.");

        // Transfer fees to the fee collector
        feeCollector.transfer(_amount);

        // Emit event
        emit FeeCollected(_tokenId, _user, _amount);
    }

    /**
     * @dev Verify a user's KYC status.
     * @param _user User address.
     * @param _isVerified Whether the user is KYC verified.
     */
    function verifyUser(address _user, bool _isVerified) public {
        // Update the user's KYC status
        verifiedUsers[_user] = _isVerified;

        // Emit event
        emit UserVerified(_user, _isVerified);
    }
}