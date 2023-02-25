// SPDX-License-Identifier: MIT
pragma solidity 0.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "../EIPs/IERC4907.sol";
import "../utils/OwnableLink.sol";
import "./IRentMarket.sol";

contract RentMarket is IRentMarket, OwnableLink {

    using Counters for Counters.Counter;
    
    constructor (address _owanble) {
        ownable = IOwnable(_owanble);
    }

    IERC20 _tokenPayment;

    Counters.Counter private _lends;
    Counters.Counter private _rents;
    mapping (address=>mapping (uint=>uint)) private _nftToLend;
    mapping (uint=>Lend) private _lendMap;
    mapping (uint=>Rent) private _rentMap;

    function isApprovedOrOwner(
        address spender, 
        uint256 tokenId, 
        address collectionAddress
    )
        public view returns(bool)
    {
        IERC4907 collection = IERC4907(collectionAddress);
        address owner = collection.ownerOf(tokenId);
        return 
            spender == owner ||
            collection.isApprovedForAll(owner, spender) ||
            collection.getApproved(tokenId) == spender;
    }

    function getTokenPayment() 
        public view override returns(address token) {
        token = address(_tokenPayment);
    }

    function getAvailableStatus(uint lendId) 
        public view override returns(bool available) {
        Lend memory lend = _lendMap[lendId];
        if (isApprovedOrOwner(
            address(this), 
            lend.tokenId, 
            lend.collectionAddress))
        return lend.rents.length == 0
            ? true 
            : _rentMap[
                lend.rents[lend.rents.length-1]
                ].endTimestamp > block.timestamp;
    }

    function getLends()
        public view override returns(Lend[] memory lends) {
        uint lendsCount = _lends.current();
        lends = new Lend[](lendsCount);
        for (uint256 i; i < lendsCount; i++) {
            lends[i] = _lendMap[i+1];
        }
    }

    function getLendsCount()
        public view override returns(uint lendCount) {
        lendCount = _lends.current();
    }

    function getLendById(uint lendId)
        public view returns(Lend memory lend) {
        lend = _lendMap[lendId];
    }
    
    function getRents() 
        public view override returns(Rent[] memory rents) {
        uint rentsCount = _rents.current();
        rents = new Rent[](rentsCount);

        for (uint i; i < rentsCount; i++) {
            rents[i] = _rentMap[i+1];
        }
    }

    function getRentsCount()
        public view returns(uint rentCount) {
        rentCount = _rents.current();
    }

    function getRentById(uint rentId)
        public view returns(Rent memory rent) {
        rent = _rentMap[rentId];
    }


    function getOwnerLends(address owner) 
        public view override returns(Lend[] memory lends) {
        uint lendsCount = _lends.current();
        uint ownerLendCount;
        uint current;

        for (uint i; i < lendsCount; i++) {
            if (_lendMap[i+1].owner == owner) {
                if (_lendMap[i+1].endTimestamp > block.timestamp) {
                    ownerLendCount++;
                }
            }
        }

        lends = new Lend[](ownerLendCount);

        for (uint i; i < lendsCount; i++) {
            if (_lendMap[i+1].owner == owner) {
                if (_lendMap[i+1].endTimestamp > block.timestamp) {
                    lends[current] = _lendMap[i+1];
                    IERC4907 collection = IERC4907(
                        lends[current].collectionAddress
                    );
                    lends[current].tokenUri = collection.tokenURI(
                        lends[current].tokenId
                    );
                    current++;
                }
            }
        }
    }

    function getAvailableLends() 
        public view override returns(Lend[] memory lends) {
        uint lendsCount = _lends.current();
        uint availableRentCount;
        uint current;

        for (uint i; i < lendsCount; i++) {
            if (getAvailableStatus(i+1)) {
                if (_lendMap[i+1].endTimestamp > block.timestamp) {
                    availableRentCount++;
                }
            }
        }

        lends = new Lend[](availableRentCount);

        for (uint i; i < lendsCount; i++) {
            if (getAvailableStatus(i+1)) {
                if (_lendMap[i+1].endTimestamp > block.timestamp) {
                    lends[current] = _lendMap[i+1];
                    IERC4907 collection = IERC4907(
                        lends[current].collectionAddress
                    );
                    lends[current].tokenUri = collection.tokenURI(
                        lends[current].tokenId
                    );
                    current++;
                }
            }
        }
    }

    function getCustomerRents(address customer) 
        public view override returns(Rent[] memory rents) {
        uint rentsCount = _rents.current();
        uint customerRentCount;
        uint current;

        for (uint i; i < rentsCount; i++) {
            if (_rentMap[i+1].customer == customer) {
                if (_rentMap[i+1].endTimestamp > block.timestamp) {
                    customerRentCount++;
                }
            }
        }

        rents = new Rent[](customerRentCount);

        for (uint i; i < rentsCount; i++) {
            if (_rentMap[i+1].customer == customer) {
                if (_rentMap[i+1].endTimestamp > block.timestamp) {
                    rents[current] = _rentMap[i+1];
                    IERC4907 collection = IERC4907(
                        rents[current].collectionAddress
                    );
                    rents[current].tokenUri = collection.tokenURI(
                        rents[current].tokenId
                    );
                    current++;
                }
            }
        }
    }

    function setTokenPayment(address token)
        public override CheckPerms {
        _tokenPayment = IERC20(token);
    }

    function initLend(
        uint tokenId,
        address collectionAddress,
        uint timeUnitSeconds,
        uint timeUnitPrice,
        uint timeUnitCount
    ) 
        public override returns(uint256 lendId) 
    {
        require(_nftToLend[collectionAddress][tokenId] == 0 || 
            !getAvailableStatus(_nftToLend[collectionAddress][tokenId]), 
            "this token already used" );
        IERC4907 collection = IERC4907( collectionAddress);
        address owner = collection.ownerOf(tokenId);
        require(owner == msg.sender, "haven't this token id");
        
        _lends.increment();
        lendId = _lends.current();
        uint startTimestamp = block.timestamp;
        uint endTimestamp = startTimestamp + timeUnitCount * timeUnitSeconds;
        
        _nftToLend[collectionAddress][tokenId] = lendId;
        _lendMap[lendId] = Lend(
            lendId,
            tokenId,
             collectionAddress,
            "",
            owner,
            timeUnitSeconds,
            timeUnitPrice,
            timeUnitCount,
            startTimestamp,
            endTimestamp,
            new uint[](0)
        );
    }

    function closeLend(uint lendId) 
        public override {
        Lend memory lend = _lendMap[lendId];
        require(lend.endTimestamp < block.timestamp, "its landing now");
        uint tokenAmount;
        
        for (uint i; i <= lend.rents.length; i++) {
            tokenAmount += 
                lend.timeUnitPrice * 
                _rentMap[lend.rents[i]].timeUnitCount;
        }

        _tokenPayment.transferFrom(address(this), lend.owner, tokenAmount);
    }

    function intiRent(
        uint lendId, 
        uint timeUnitCount
    ) 
        public override returns(uint rentId) 
    {
        Lend memory lend = _lendMap[lendId];
        uint tokenAmount = lend.timeUnitPrice * timeUnitCount;
        require(lend.owner == msg.sender, "you can't rent your token");
        require(getAvailableStatus(lendId), "lend is busy");
        require(_tokenPayment.allowance(
            msg.sender, 
            address(this)
            ) >= tokenAmount, "allowance is so low");
        
        _rents.increment();
        rentId = _rents.current();
        address customer = msg.sender;
        uint startTimestamp = block.timestamp;
        uint endTimestamp = startTimestamp + timeUnitCount * lend.timeUnitSeconds;
        IERC4907 collection = IERC4907(lend. collectionAddress);
        
        collection.setUser(lend.tokenId, customer, uint64(endTimestamp));
        _tokenPayment.transferFrom(msg.sender, address(this), tokenAmount);

        _rentMap[rentId] = Rent(
            rentId,
            lend.tokenId,
            lend.collectionAddress,
            "",
            customer,
            lendId,
            lend.timeUnitSeconds,
            timeUnitCount,
            startTimestamp,
            endTimestamp
        );
        _lendMap[lendId].rents.push(rentId);
    }
}