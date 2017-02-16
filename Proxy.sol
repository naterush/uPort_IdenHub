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
