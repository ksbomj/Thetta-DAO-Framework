pragma solidity ^0.4.15;

import "zeppelin-solidity/contracts/token/ERC20/ERC20.sol";

import '../moneyflow/WeiExpense.sol';
import '../IMicrocompany.sol';

// 4 types of tasks:
// PrePaid 
// PostPaid with known neededWei amount 
// PostPaid with unknown neededWei amount. Task is evaluated AFTER work is complete
// PostPaid donation - client pays any amount he wants AFTER work is complete
// 
////////////////////////////////////////////////////////
// WeiAbsoluteExpense:
//		has 'owner'	(i.e. "admin")
//		has 'moneySource' (i.e. "client")
//		has 'neededWei'
//		has 'processFunds(uint _currentFlow)' payable function 
//		has 'setNeededWei(uint _neededWei)' 
// 
contract GenericTask is WeiAbsoluteExpense {
	address mc = 0x0;
	address employee = 0x0;		// who should complete this task and report on completion
										// this will be set later
	address output = 0x0;		// where to send money (can be split later)
										// can be set later too
	string public caption = "";
	string public desc = "";
	bool isPostpaid = false;		// prepaid/postpaid switch

	bool isDonation = false;		// if true -> any price
	// TODO: use it
	uint64 public timeToCancel = 0;

	enum State {
		Init,
		Cancelled,
		// only for (isPostpaid==false) tasks
		// anyone can use 'processFunds' to send money to this task
		PrePaid,

		// These are set by Employee:
		InProgress,
		CompleteButNeedsEvaluation,	// in case neededWei is 0 -> we should evaluate task first and set it
												// please call 'evaluateAndSetNeededWei'
		Complete,

		// These are set by Creator or Client:
		CanGetFunds,						// call flush to get funds	
		Finished								// funds are transferred to the output and the task is finished
	}
	// Use 'getCurrentState' method instead to access state outside of contract
	State state = State.Init;

	modifier onlyEmployeeOrOwner() { 
		require(msg.sender==employee || msg.sender==owner); 
		_; 
	}

	modifier onlyAnyEmployeeOrOwner() { 
		IMicrocompany tmp = IMicrocompany(mc);
		require(tmp.isEmployee(msg.sender) || msg.sender==owner); 
		_; 
	}

	// if _neededWei==0 -> this is an 'Unknown cost' situation. use 'setNeededWei' method of WeiAbsoluteExpense
	function GenericTask(address _mc, string _caption, string _desc, bool _isPostpaid, bool _isDonation, uint _neededWei) public 
		WeiAbsoluteExpense(_neededWei) 
	{
		mc = _mc;
		caption = _caption;
		desc = _desc;
		isPostpaid = _isPostpaid;
		isDonation = _isDonation;
	}

	// who will complete this task
	function setEmployee(address _employee) public onlyOwner {
		employee = _employee;
	}

	// where to send money
	function setOutput(address _output) public onlyOwner {
		output = _output;
	}

	function getCurrentState()public constant returns(State){
		// for Prepaid task -> client should call processFunds method to put money into this task
		// when state is Init
		if((State.Init==state) && (neededWei!=0) && (!isPostpaid)){
			if(neededWei==this.balance){
				return State.PrePaid;
			}
		}

		// for Postpaid task -> client should call processFunds method to put money into this task
		// when state is Complete. He is confirming the task by doing that (no need to call confirmCompletion)
		if((State.Complete==state) && (neededWei!=0) && (isPostpaid)){
			if(neededWei==this.balance){
				return State.CanGetFunds;
			}
		}

		return state; 
	}

	function cancell() public onlyOwner {
		require(getCurrentState()==State.Init || getCurrentState()==State.PrePaid);
		if(getCurrentState()==State.PrePaid){
			// return money to 'moneySource'
			moneySource.transfer(this.balance);
		}
		state = State.Cancelled;
	}

	function notifyOnCompletion() public onlyEmployeeOrOwner {
		require(getCurrentState()==State.InProgress);

		if((0!=neededWei) || (isDonation)){
			state = State.Complete;
		}else{
			state = State.CompleteButNeedsEvaluation;
		}
	}

	function evaluateAndSetNeededWei(uint _neededWei) public onlyOwner {
		require(getCurrentState()==State.CompleteButNeedsEvaluation);
		require(0==neededWei);

		neededWei = _neededWei;
		state = State.Complete;
	}

	// for Prepaid tasks only! 
	// for Postpaid: call processFunds and transfer money instead!
	function confirmCompletion() public onlyByMoneySource {
		require(getCurrentState()==State.Complete);
		require(!isPostpaid);
		assert(0!=neededWei);

		state = State.CanGetFunds;
	}

// IWeiDestination overrides:
	// pull model
	function flush() public {
		require(getCurrentState()==State.CanGetFunds);
		require(0x0!=output);

		output.transfer(this.balance);
		state = State.Finished;
	}

	function processFunds(uint _currentFlow) public payable{
		if(isPostpaid && (0==neededWei) && (State.Complete==state)){
			// this is a donation
			// client can send any sum!
			neededWei = msg.value;		
		}

		// TODO: this doesn't compile. is it ok?
		//super.processFunds.value(msg.value)(_currentFlow);
		super.processFunds(_currentFlow);
	}

	// non-payable
	function()public{
	}
}

contract WeiTask is GenericTask {
	function WeiTask(address _mc, string _caption, string _desc, bool _isPostpaid, bool _isDonation, uint _neededWei) public 
		GenericTask(_mc, _caption, _desc, _isPostpaid, _isDonation, _neededWei) 
	{
	}

	// callable by any Employee of the current Microcompany or Owner
	function startTask(address _employee) public onlyAnyEmployeeOrOwner {
		require(getCurrentState()==State.Init || getCurrentState()==State.PrePaid);

		if(getCurrentState()==State.Init){
			// can start only if postpaid task 
			require(isPostpaid);
		}

		employee = _employee;	
		state = State.InProgress;
	}
}

// Bounty is always prepaid 
contract WeiBounty is GenericTask {
	function WeiBounty(address _mc, string _caption, string _desc, uint _neededWei) public 
		GenericTask(_mc, _caption, _desc, false, false, _neededWei) 
	{
	}

	// callable by anyone
	function startTask() public {
		require(getCurrentState()==State.PrePaid);

		employee = msg.sender;	
		state = State.InProgress;
	}
}