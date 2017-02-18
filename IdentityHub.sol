pragma solidity ^0.4.4;

contract Proxy {

    address masterContract = msg.sender;

    modifier onlyMaster () {
        if (msg.sender == masterContract) {_;}
    }

    function () payable {
    }

    //changed name from transfer - as to not confuse with ERC token standard
    function transferOwnership (address _newMaster) onlyMaster {
        masterContract = _newMaster;
    }

    function forward(address destination, uint value, bytes data) onlyMaster payable {
    	// If a contract tries to CALL or CREATE a contract with either
    	// (i) insufficient balance, or (ii) stack depth already at maximum (1024),
    	// the sub-execution and transfer do not occur at all, no gas gets consumed, and 0 is added to the stack.
    	// see: https://github.com/ethereum/wiki/wiki/Subtleties#exceptional-conditions
        if (!destination.call.value(value)(data)) {
            throw;
        }
    }
}

library Lib1{
    function findAddress(address a, address[] storage arry) returns (int){
        for (uint i = 0 ; i < arry.length ; i++){
            if(arry[i] == a){return int(i);}
        }
        return -1;
    }
    function removeAddress(uint i, address[] storage arry){
        uint lengthMinusOne = arry.length - 1;
        arry[i] = arry[lengthMinusOne];
        delete arry[lengthMinusOne];
        arry.length = lengthMinusOne;
    }
}


contract IdentityHub {
    uint    public version;
    uint    public existingIdentityNum = 1;

    struct identity {
        address userKey;
        address proposedUserKey;
        uint    proposedUserKeyPendingUntil;

        address proposedController;
        uint    proposedControllerPendingUntil;

        uint    shortTimeLock;// use 900 for 15 minutes
        uint    longTimeLock; // use 259200 for 3 days

        uint idenNum;
        Proxy   proxy;
        address[]  delegateAddresses;
    }
    identity[] Iden; //Stored in array instead of mapping so no copying data necessary

    struct Delegate{
        uint    deletedAfter; // delegate exists if not 0
        uint    pendingUntil;
        address proposedUserKey;
        address proposedController;
    }
    mapping (address => Delegate) public delegates;

    struct UserTypeAndNum {
        uint idenNum;
        bool isUserKey;
    }
    mapping (address => UserTypeAndNum) public userTypesAndNums; //used to refer to one struct in Iden array from multiple addresses

    function IdentityHub() {
        version = 1;
        existingIdentityNum = 1;
    }
    event IdentityEvent(
      address indexed identity,
      string action,
      address initiatedBy
    );

    event RecoveryEvent(
      string action,
      address initiatedBy
    );

    //indexing proxy in these two to move this out of proxy contract
    event Forwarded (
        address indexed idenitity,
        address indexed destination,
        uint value,
        bytes data
    );

    event Received (
        address indexed identity,
        address indexed sender,
        uint value
    );

    //MODIFIERS TO LIMIT ACCESS

    //makes sure no existing data is being overwritten
    modifier checkAddressesExistance(address _userKey, address[] _delegates) {
        if (userTypesAndNums[_userKey].idenNum != 0) throw;
        for (uint i = 0; i < _delegates.length; i++) {
            if (userTypesAndNums[_delegates[i]].idenNum != 0) throw;
        }
        _;
    }

    //only a userKey (not a delegate) can get through
    modifier onlyUserKeys(address key) {
        if (userTypesAndNums[key].idenNum == 0 || !userTypesAndNums[key].isUserKey) throw;
        _;
    }

    //only a delegate (not a userKey) can get through
    modifier onlyDelegateKeys(address key) {
        if (userTypesAndNums[key].idenNum == 0 || userTypesAndNums[key].isUserKey) throw;
        _;
    }

    //creates a basic identity
    function createIdentity(address _userKey, address[] _delegates, uint _longTimeLock, uint _shortTimeLock)
                checkAddressesExistance(_userKey, _delegates){
        //create new proxy
        Proxy proxy = new Proxy();
        //add new identity structure to Iden array
        Iden.push(identity({userKey: _userKey, proposedUserKey: 0x0, proposedUserKeyPendingUntil: 0, proposedController: 0x0, proposedControllerPendingUntil: 0, shortTimeLock: _shortTimeLock, longTimeLock: _longTimeLock, idenNum: existingIdentityNum, proxy: proxy, delegateAddresses: _delegates}));

        updateMapping(_userKey, existingIdentityNum, true);

        //create all delegates
        for (uint i = 0; i < _delegates.length; i++) {
            updateMapping(_delegates[i], existingIdentityNum, false);
            delegates[_delegates[i]] = Delegate({deletedAfter: 31536000000000, pendingUntil: 0, proposedUserKey: 0x0, proposedController: 0x0});
        }
        IdentityEvent(proxy, "createIdentity", msg.sender);
        existingIdentityNum++;

    }

    function forward(address destination, uint value, bytes data) onlyUserKeys(msg.sender) {
        uint idenNum = userTypesAndNums[msg.sender].idenNum;

        Iden[idenNum].proxy.forward(destination, value, data);
        Forwarded (Iden[idenNum].proxy, destination, value, data);
    }

    function fundProxy() onlyUserKeys(msg.sender) payable {
        uint idenNum = userTypesAndNums[msg.sender].idenNum;
        //do not need to check return - all proxys are trusted
        Iden[idenNum].proxy.send(msg.value);
        Received(Iden[idenNum].proxy, msg.sender, msg.value);
    }

    //FUNCTION FOR USERKEYS (NOT DELEGATES)

    function userSignControllerChange(address _proposedController) onlyUserKeys(msg.sender) {
        var user = Iden[userTypesAndNums[msg.sender].idenNum];

        user.proposedControllerPendingUntil = now + user.longTimeLock;
        user.proposedController = _proposedController;
        RecoveryEvent("signControllerChange", msg.sender);
    }

    //this function could be made to be compatable - mostly - with current identity factory.
    function userChangeController() onlyUserKeys(msg.sender) onlyUserKeys(msg.sender) {
        uint idenNum = userTypesAndNums[msg.sender].idenNum;
        var user = Iden[idenNum];

        if(user.proposedControllerPendingUntil < now && user.proposedController != 0x0){
            changeController(idenNum, user.proposedController, true);
        }
        RecoveryEvent("changeController", msg.sender);
    }

    function userSignUserKeyChange(address _proposedUserKey) onlyUserKeys(msg.sender){
        var user = Iden[userTypesAndNums[msg.sender].idenNum];

        user.proposedUserKeyPendingUntil = now + user.shortTimeLock;
        user.proposedUserKey = _proposedUserKey;
        RecoveryEvent("signUserKeyChange", msg.sender);
    }

    //this maybe should be able to be called by anyone?
    function userChangeUserKey() onlyUserKeys(msg.sender){
        uint idenNum = userTypesAndNums[msg.sender].idenNum;
        var user = Iden[idenNum];

        //don't let overwrite anyone elses data
        if (userTypesAndNums[user.proposedUserKey].idenNum != 0) {throw;}

        if(user.proposedUserKeyPendingUntil < now && user.proposedUserKey != 0x0){
            changeUserKey(idenNum, user.proposedUserKey, true);
        }
    }

    function userReplaceDelegates(address[] delegatesToRemove, address[] delegatesToAdd) onlyUserKeys(msg.sender){
        uint idenNum = userTypesAndNums[msg.sender].idenNum;
        var user = Iden[idenNum];

        removeDelegates(idenNum, delegatesToRemove);
        garbageCollect(idenNum);
        addDelegates(idenNum, delegatesToAdd);

        RecoveryEvent("replaceDelegates", msg.sender);
    }

    function delegateSignUserChange(address proposedUserKey) onlyDelegateKeys(msg.sender){
        uint idenNum = userTypesAndNums[msg.sender].idenNum;

        if(delegateRecordExists(delegates[msg.sender])) {
            delegates[msg.sender].proposedUserKey = proposedUserKey;
            changeUserKey(idenNum, proposedUserKey, false);
            RecoveryEvent("signUserChange", msg.sender);
        }
    }

    function delegateSignControllerChange(address _proposedController) onlyDelegateKeys(msg.sender){
        uint idenNum = userTypesAndNums[msg.sender].idenNum;

        if(delegateRecordExists(delegates[msg.sender])) {
            delegates[msg.sender].proposedController = _proposedController;
            changeController(idenNum, _proposedController, false);
            RecoveryEvent("signControllerChange", msg.sender);
        }
    }

    //HELPER FUNCTIONS - ALL ARE PRIVATE

    //if user has to many delegates, this function will run out of gas. In this case,
    //should delete delegates in bunches before calling this.
    //this also leaves blank spaces in Iden array, as to not overcomplicate logic
    function deleteIdentity(address _userKey) private onlyUserKeys(_userKey) {
        uint idenNum = userTypesAndNums[_userKey].idenNum;
        var user = Iden[idenNum];

        for(uint i = 0; i < user.delegateAddresses.length; i++) {
            delete delegates[user.delegateAddresses[i]];
            delete userTypesAndNums[user.delegateAddresses[i]];
        }

        delete userTypesAndNums[_userKey];
        delete Iden[idenNum];
    }

    function changeUserKey(uint _idenNum, address newUserKey, bool alreadyApproved) private{
        var user = Iden[_idenNum];

        if(collectedSignatures(_idenNum, newUserKey, false) >= neededSignatures(_idenNum) || alreadyApproved){
            delete userTypesAndNums[user.userKey];
            user.userKey = newUserKey;
            updateMapping(newUserKey, _idenNum, true);
            delete user.proposedUserKey;

            for(uint i = 0 ; i < user.delegateAddresses.length ; i++){
                //remove any pending delegates after a recovery
                if(delegates[user.delegateAddresses[i]].pendingUntil > now){
                    delegates[user.delegateAddresses[i]].deletedAfter = now;
                }
                delete delegates[user.delegateAddresses[i]].proposedUserKey;
            }

        RecoveryEvent("changeUserKey", msg.sender);
        }
    }


    function changeController(uint _idenNum, address _proposedController, bool alreadyApproved) private {
        var user = Iden[_idenNum];

        if(collectedSignatures(_idenNum, _proposedController, true) >= neededSignatures(_idenNum) || alreadyApproved){
            user.proxy.transferOwnership(user.proposedController);
            deleteIdentity(user.userKey);
        }
        RecoveryEvent("changeController", msg.sender);
    }

    function neededSignatures(uint _idenNum) returns (uint){
        var user = Iden[_idenNum];
        uint currentDelegateCount; //always 0 at this point
        for(uint i = 0 ; i < user.delegateAddresses.length ; i++){
            if(delegateIsCurrent(delegates[user.delegateAddresses[i]])){ currentDelegateCount++; }
        }
        return currentDelegateCount/2 + 1;
    }

    function collectedSignatures(uint _idenNum, address _proposedKey, bool isForController) returns (uint signatures){
        var user = Iden[userTypesAndNums[msg.sender].idenNum];

        for(uint i = 0 ; i < user.delegateAddresses.length ; i++){
            if (isForController) {
                if (delegateHasValidSignature(delegates[user.delegateAddresses[i]]) && delegates[user.delegateAddresses[i]].proposedController == _proposedKey){
                    signatures++;
                }
            } else {
                if (delegateHasValidSignature(delegates[user.delegateAddresses[i]]) && delegates[user.delegateAddresses[i]].proposedUserKey == _proposedKey){
                    signatures++;
                }
            }
        }
    }

    function addDelegates(uint _idenNum, address[] delegatesToAdd) private {
        var user = Iden[_idenNum];

        for (uint i = 0; i < delegatesToAdd.length; i++) {
            address delegate = delegatesToAdd[i];
            //checks to make sure delegate does not exist already
            if (userTypesAndNums[delegate].idenNum != 0) {throw;}

            if(!delegateRecordExists(delegates[delegate]) && user.delegateAddresses.length < 15) {
                delegates[delegate] = Delegate({proposedUserKey: 0x0, pendingUntil: now + user.longTimeLock, deletedAfter: 31536000000000, proposedController: 0x0});
                user.delegateAddresses.push(delegate);
                updateMapping(delegate, _idenNum, false);
            }
        }
    }

    function removeDelegates(uint _idenNum, address[] delegatesToRemove) private {
        var user = Iden[_idenNum];

        for (uint i = 0; i < delegatesToRemove.length; i++) {
            address delegate = delegatesToRemove[i];
            //checks to make sure delegate is owner by person removing them
            if (userTypesAndNums[delegate].idenNum != _idenNum) {throw;}

            if(delegates[delegate].deletedAfter > user.longTimeLock + now){
            //remove right away if they are still pending
                if(delegates[delegate].pendingUntil > now){
                    delegates[delegate].deletedAfter = now;
                    delete userTypesAndNums[delegate];
                } else{
                    delegates[delegate].deletedAfter = user.longTimeLock + now;
                }
            }
        }
    }

    function garbageCollect(uint _idenNum) private{
        var user = Iden[_idenNum];
        uint i = 0;
        while(i < user.delegateAddresses.length){
            if(delegateIsDeleted(delegates[user.delegateAddresses[i]])){
                delegates[user.delegateAddresses[i]].deletedAfter = 0;
                delegates[user.delegateAddresses[i]].pendingUntil = 0;
                delegates[user.delegateAddresses[i]].proposedUserKey = 0;
                Lib1.removeAddress(i, user.delegateAddresses);
            }else{i++;}
        }
    }

    function delegateRecordExists(Delegate d) private returns (bool){
        return d.deletedAfter != 0;
    }
    function delegateIsDeleted(Delegate d) private returns (bool){
        return d.deletedAfter <= now; //doesnt check record existence
    }
    function delegateIsCurrent(Delegate d) private returns (bool){
        return delegateRecordExists(d) && !delegateIsDeleted(d) && now > d.pendingUntil;
    }
    function delegateHasValidSignature(Delegate d) private returns (bool){
        return delegateIsCurrent(d) && d.proposedUserKey != 0x0;
    }

    function updateMapping(address keyToUpdate, uint newIdentityNum, bool _isUserKey) private {
        userTypesAndNums[keyToUpdate].idenNum = newIdentityNum;
        userTypesAndNums[keyToUpdate].isUserKey = _isUserKey;
    }
}
