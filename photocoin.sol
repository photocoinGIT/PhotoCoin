// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PhotoCoin is Ownable {
    uint256 public B;
    uint256 public E;
    uint256 public a;
    uint256 public C;
    uint256 public Cbase;

    uint256 public photoCount;
    uint256 public immutable initialBalance;

    uint256 private constant DECIMALS = 1e18;
    uint256 private constant FEE_PERCENT = 2;
    uint256 private constant FEE_DIVISOR = 100;

    uint256 public A;
    uint256 public f_max;

    mapping(address => uint256) public balances;
    mapping(address => bool) public registered;
    mapping(address => uint256) public registrationTime;
    mapping(address => uint256) public likesGiven;
    mapping(address => uint256) public photosPosted;

    mapping(address => bool) public isHolder;

    uint256 public limitDays;
    uint256 public limitLikes;
    uint256 public limitPhotos;

    struct Photo {
        address author;
        uint256 likes;
        address[] likedBy;
        bool isSponsor;
    }

    mapping(uint256 => Photo) public photos;
    mapping(uint256 => mapping(address => bool)) public photoLiked;

    event UserRegistered(address indexed user, uint256 initialBalance);
    event PhotoAdded(uint256 indexed photoId, address indexed author);
    event PhotoLiked(uint256 indexed photoId, address indexed liker, uint256 price, uint256 newLikeCount);
    event ConversionParametersUpdated(uint256 A, uint256 f_max);
    event PriceMultiplierUpdated(uint256 newMultiplier);
    event TokenPriceUpdated(uint256 newPrice);
    event WithdrawalLimitsUpdated(uint256 limitDays, uint256 limitLikes, uint256 limitPhotos);
    event HolderSet(address indexed user);

    IERC20 public immutable ptcToken;
    address public feeWallet;
    uint256 public priceMultiplier = 1;
    uint256 public manualPrice;

    uint256 public coinAdditionMultiplier;

    address[] private userList;

    constructor(
        uint256 _B,
        uint256 _E,
        uint256 _a,
        uint256 _C,
        uint256 _Cbase,
        uint256 _initialBalance,
        uint256 _limitDays,
        uint256 _limitLikes,
        uint256 _limitPhotos
    ) Ownable(msg.sender) {
        B = _B;
        E = _E;
        a = _a;
        C = _C;
        Cbase = _Cbase;
        initialBalance = _initialBalance;
        ptcToken = IERC20(0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701);
        feeWallet = msg.sender;
        manualPrice = 0;
        A = 5;
        f_max = 100000000000000000;
        coinAdditionMultiplier = 1;

        limitDays = _limitDays;
        limitLikes = _limitLikes;
        limitPhotos = _limitPhotos;
    }

    function setFeeWallet(address _feeWallet) external onlyOwner {
        require(_feeWallet != address(0), "Invalid address");
        feeWallet = _feeWallet;
    }

    function updateConversionParameters(uint256 _A, uint256 _f_max) external onlyOwner {
        A = _A;
        f_max = _f_max;
        emit ConversionParametersUpdated(_A, _f_max);
    }

    function updatePriceMultiplier(uint256 newMultiplier) external onlyOwner {
        priceMultiplier = newMultiplier;
        emit PriceMultiplierUpdated(newMultiplier);
    }

    function updateTokenPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be positive");
        manualPrice = newPrice;
        emit TokenPriceUpdated(newPrice);
    }

    function updateWithdrawalLimits(uint256 _limitDays, uint256 _limitLikes, uint256 _limitPhotos) external onlyOwner {
        limitDays = _limitDays;
        limitLikes = _limitLikes;
        limitPhotos = _limitPhotos;
        emit WithdrawalLimitsUpdated(_limitDays, _limitLikes, _limitPhotos);
    }

    function getTokenPriceInUsd() public view returns (uint256) {
        require(manualPrice > 0, "Manual price not set");
        return manualPrice;
    }

    function getConversionCoefficient() public view returns (uint256) {
        uint256 currentPrice = getTokenPriceInUsd();
        require(currentPrice > 0, "Price not set");
        uint256 rawCoefficient = (A * DECIMALS) / currentPrice;
        if (rawCoefficient > f_max) {
            return f_max;
        }
        return rawCoefficient;
    }

    function calculateDepositAmount(uint256 monAmount) public view returns (uint256) {
        uint256 coefficient = getConversionCoefficient();
        require(coefficient > 0, "Coefficient is zero");
        return (monAmount * DECIMALS) / coefficient;
    }

    function calculateWithdrawAmount(uint256 photocoinAmount) public view returns (uint256) {
        uint256 coefficient = getConversionCoefficient();
        return (photocoinAmount * coefficient) / DECIMALS;
    }

    function registerUser() external {
        require(!registered[msg.sender], "User already registered");
        registered[msg.sender] = true;
        userList.push(msg.sender);
        balances[msg.sender] = initialBalance;
        registrationTime[msg.sender] = block.timestamp;
        likesGiven[msg.sender] = 0;
        photosPosted[msg.sender] = 0;
        emit UserRegistered(msg.sender, initialBalance);
    }

    function getAllUserBalances() external view onlyOwner returns (address[] memory, uint256[] memory) {
        uint256 length = userList.length;
        uint256[] memory userBalances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            userBalances[i] = balances[userList[i]];
        }
        return (userList, userBalances);
    }

    function setHolder(address user) external onlyOwner {
        require(registered[user], "User not registered");
        isHolder[user] = true;
        emit HolderSet(user);
    }

    function addPhoto() external {
        photoCount++;
        uint256 newPhotoId = photoCount;
        require(photos[newPhotoId].author == address(0), "Photo already exists");
        Photo storage newPhoto = photos[newPhotoId];
        newPhoto.author = msg.sender;
        newPhoto.likes = 0;
        newPhoto.isSponsor = false;
        photosPosted[msg.sender] += 1;
        emit PhotoAdded(newPhotoId, msg.sender);
    }

    function addSponsorPhoto() external {
        uint256 currentPrice = getTokenPriceInUsd();
        require(currentPrice > 0, "Price not set");
        uint256 cost = (2 * 10 * 1e18) / currentPrice;
        require(ptcToken.balanceOf(msg.sender) >= cost, "Insufficient token balance");
        require(ptcToken.allowance(msg.sender, address(this)) >= cost, "Insufficient allowance");
        require(ptcToken.transferFrom(msg.sender, feeWallet, cost), "Token transfer failed");
        photoCount++;
        uint256 newPhotoId = photoCount;
        require(photos[newPhotoId].author == address(0), "Photo already exists");
        Photo storage newPhoto = photos[newPhotoId];
        newPhoto.author = msg.sender;
        newPhoto.likes = 0;
        newPhoto.isSponsor = true;
        photosPosted[msg.sender] += 2;
        emit PhotoAdded(newPhotoId, msg.sender);
    }

    function isPhotoSponsor(uint256 photoId) external view returns (bool) {
        require(photos[photoId].author != address(0), "Photo does not exist");
        return photos[photoId].isSponsor;
    }

    function calculatePrice(uint256 countLikes) public view returns (uint256) {
        uint256 currentRate = getTokenPriceInUsd();
        uint256 multiplier = 1;
        if (currentRate > Cbase) {
            multiplier = 1 + ((a * (currentRate - Cbase)) / Cbase);
        }
        uint256 price = B * (1 + E * countLikes) * multiplier;
        if (price < 1) {
            price = 1;
        }
        return price;
    }

    function likePhoto(uint256 photoId) external {
        Photo storage p = photos[photoId];
        require(p.author != address(0), "Photo does not exist");
        require(msg.sender != p.author, "Author cannot like own photo");
        require(!photoLiked[photoId][msg.sender], "Already liked");

        uint256 newLikeCount = p.likes + 1;
        uint256 price = calculatePrice(newLikeCount);
        require(balances[msg.sender] >= price, "Insufficient balance");

        balances[msg.sender] -= price;

        uint256 authorReward = (price * 3) / 8;
        if (authorReward < 1) {
            authorReward = 1;
        }
        balances[p.author] += authorReward;

        uint256 remainingReward = price - authorReward;
        uint256 numPrev = p.likedBy.length;
        if (numPrev > 0) {
            uint256 totalWeight = (numPrev * (numPrev + 1)) / 2;
            for (uint256 i = 0; i < numPrev; i++) {
                uint256 weight = numPrev - i;
                uint256 reward = (remainingReward * weight) / totalWeight;
                if (reward < 1) {
                    reward = 1;
                }
                unchecked {
                    balances[p.likedBy[i]] += reward;
                }
            }
        }

        p.likes = newLikeCount;
        p.likedBy.push(msg.sender);
        photoLiked[photoId][msg.sender] = true;
        likesGiven[msg.sender] += 1;
        emit PhotoLiked(photoId, msg.sender, price, newLikeCount);
    }

    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    function getLikePrice(uint256 photoId) external view returns (uint256) {
        Photo storage p = photos[photoId];
        uint256 nextLikeCount = p.likes + 1;
        return calculatePrice(nextLikeCount);
    }

    function deletePhoto(uint256 photoId) external onlyOwner {
        require(photos[photoId].author != address(0), "Photo does not exist");
        delete photos[photoId];
    }

    function addPhotocoins(address user, uint256 amount) external onlyOwner {
        require(user != address(0), "Invalid address");
        require(amount > 0, "Amount must be greater than zero");
        balances[user] += amount * coinAdditionMultiplier;
    }

    function addPhotoForUser(address _author, bool _isSponsor) external onlyOwner {
        require(_author != address(0), "Invalid author address");
        photoCount++;
        uint256 newPhotoId = photoCount;
        require(photos[newPhotoId].author == address(0), "Photo already exists");
        Photo storage newPhoto = photos[newPhotoId];
        newPhoto.author = _author;
        newPhoto.likes = 0;
        newPhoto.isSponsor = _isSponsor;
        if (_isSponsor) {
            photosPosted[_author] += 2;
        } else {
            photosPosted[_author] += 1;
        }
        emit PhotoAdded(newPhotoId, _author);
    }

    function updateParameters(
        uint256 _B,
        uint256 _E,
        uint256 _a,
        uint256 _C,
        uint256 _Cbase,
        uint256 _coinAdditionMultiplier
    ) external onlyOwner {
        B = _B;
        E = _E;
        a = _a; 
        C = _C;
        Cbase = _Cbase;
        coinAdditionMultiplier = _coinAdditionMultiplier;
    }

    function canWithdraw(address user) public returns (bool) {
        require(registered[user], "User not registered");
        if (isHolder[user]) {
            return true;
        }
        uint256 daysRegistered = (block.timestamp - registrationTime[user]) / 1 days;
        if (
            daysRegistered >= limitDays &&
            likesGiven[user] >= limitLikes &&
            photosPosted[user] >= limitPhotos
        ) {
            registrationTime[user] = block.timestamp;
            likesGiven[user] = 0;
            photosPosted[user] = 0;
            return true;
        }
        return false;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Must deposit some tokens");
        require(ptcToken.transferFrom(msg.sender, address(this), amount), "Token transfer failed");
        uint256 photocoinAmount = calculateDepositAmount(amount);
        balances[msg.sender] += photocoinAmount;
    }

    function withdraw(uint256 photocoinAmount) external {
        require(balances[msg.sender] >= photocoinAmount, "Insufficient balance");
        require(canWithdraw(msg.sender), "Withdrawal conditions not met");

        uint256 tokenAmount = calculateWithdrawAmount(photocoinAmount);
        uint256 fee = (tokenAmount * FEE_PERCENT) / FEE_DIVISOR;
        uint256 userAmount = tokenAmount - fee;
        balances[msg.sender] -= photocoinAmount;
        require(ptcToken.transfer(msg.sender, userAmount), "Token transfer to user failed");
        require(ptcToken.transfer(feeWallet, fee), "Token transfer of fee failed");
    }
}