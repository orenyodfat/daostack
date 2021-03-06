pragma solidity ^0.4.11;

import "../VotingMachines/IntVoteInterface.sol";
import "./UniversalScheme.sol";

/**
 * @title VoteInOrganizationScheme.
 * @dev A scheme to allow an organization to vote in a proposal.
 */


// ToDo: Documentation and tests!

contract VoteInOrganizationScheme is UniversalScheme, ExecutableInterface, ActionInterface {
    // Details of a voting proposal:
    struct VoteProposal {
      IntVoteInterface originalIntVote;
      bytes32 originalProposalId;
      uint originalNumOfChoices;
    }

    // Struct holding the data for each organization
    struct Organization {
      bool isRegistered;
    }

    mapping(bytes32=>VoteProposal) proposals;

    // A mapping from thr organization (Avatar) address to the saved data of the organization:
    mapping(address=>Organization) organizations;

    // A mapping from hashes to parameters (use to store a particular configuration on the controller)
    struct Parameters {
      IntVoteInterface intVote;
      bytes32 voteParams;
    }

    mapping(bytes32=>Parameters) parameters;

    /**
     * @dev the constructor takes a token address, fee and beneficiary
     */
    function VoteInOrganizationScheme(StandardToken _nativeToken, uint _fee, address _beneficiary) {
        updateParameters(_nativeToken, _fee, _beneficiary, bytes32(0));
    }

    /**
     * @dev hash the parameters, save them if necessary, and return the hash value
     */
    function setParameters(
        bytes32 _voteParams,
        IntVoteInterface _intVote
    ) returns(bytes32)
    {
        bytes32 paramsHash = getParametersHash(_voteParams, _intVote);
        parameters[paramsHash].voteParams = _voteParams;
        parameters[paramsHash].intVote = _intVote;
        return paramsHash;
    }

    /**
     * @dev return a hash of the given parameters
     */
    function getParametersHash(
        bytes32 _voteParams,
        IntVoteInterface _intVote
    ) constant returns(bytes32)
    {
        bytes32 paramsHash = (sha3(_voteParams, _intVote));
        return paramsHash;
    }

    function isRegistered(address _avatar) constant returns(bool) {
      return organizations[_avatar].isRegistered;
    }

    /**
     * @dev registering an organization to the univarsal scheme
     * @param _avatar avatar of the organization
     */
    function registerOrganization(Avatar _avatar) {
      // Pay fees for using scheme:
      if ((fee > 0) && (! organizations[_avatar].isRegistered)) {
        nativeToken.transferFrom(_avatar, beneficiary, fee);
      }

      Organization memory org;
      org.isRegistered = true;
      organizations[_avatar] = org;
      LogOrgRegistered(_avatar);
    }

    function proposeVote(Avatar _avatar, IntVoteInterface _originalIntVote, bytes32 _originalProposalId) returns(bytes32) {
      Organization memory org = organizations[_avatar];
      require(org.isRegistered); // Check org is registred to use this universal scheme.
      uint numOfChoices = _originalIntVote.getNumberOfChoices(_originalProposalId);
      Parameters memory params = parameters[getParametersFromController(_avatar)];
      IntVoteInterface intVote = params.intVote;
      bytes32 proposalId = intVote.propose(numOfChoices+1, params.voteParams, _avatar, ExecutableInterface(this));
      if (proposals[proposalId].originalNumOfChoices != 0) {
        revert();
      }
      proposals[proposalId] = VoteProposal({
        originalIntVote: _originalIntVote,
        originalProposalId: _originalProposalId,
        originalNumOfChoices: numOfChoices
      });
      LogNewProposal(proposalId);
      return proposalId;
    }

    /**
     * @dev execution of proposals, can only be called by the voting machine in which the vote is held.
     * @param _proposalId the ID of the voting in the voting machine
     * @param _avatar address of the controller
     * @param _param a parameter of the voting result, 0 is no and 1 is yes.
     */
    function execute(bytes32 _proposalId, address _avatar, int _param) returns(bool) {
      // Check the caller is indeed the voting machine:
      require(parameters[getParametersFromController(Avatar(_avatar))].intVote == msg.sender);

      // Save proposal to memory and delete from storage:
      VoteProposal memory proposal = proposals[_proposalId];
      delete proposals[_proposalId];

      // If no decision do nothing:
      if (_param == 0) {
        return true;
      }

      // Define controller and get the parmas:
      Controller controller = Controller(Avatar(_avatar).owner());
      if (_param >  int(proposal.originalNumOfChoices)) {
        _param = 0;
      }
      bytes32[] memory tmp = new bytes32[](3);
      tmp[0] = bytes32(address(proposal.originalIntVote));
      tmp[2] = proposal.originalProposalId;
      tmp[3] = bytes32(_param);
      controller.genericAction(this, tmp);
      return true;
    }

    function action(bytes32[] _params) returns(bool) {
      IntVoteInterface intVote = IntVoteInterface(address(_params[0]));
      bytes32 proposalId = _params[1];
      uint vote = uint(_params[2]);
      intVote.vote(proposalId, vote);
    }
}
