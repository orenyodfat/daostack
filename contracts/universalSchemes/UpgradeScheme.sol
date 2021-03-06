pragma solidity ^0.4.11;

import "../VotingMachines/BoolVoteInterface.sol";
import "./UniversalScheme.sol";

/**
 * @title A schme to manage the upgrade of an organization.
 * @dev The schme is used to upgrade the controller of an organization to a new controller.
 */

contract UpgradeScheme is UniversalScheme, ExecutableInterface {
    // Details of an upgrade proposal:
    struct UpgradeProposal {
        address newContOrScheme; // Either the new conroller we upgrade to, or the new upgrading scheme.
        bytes32 params; // Params for the new upgrading scheme.
        uint proposalType; // 1: Upgrade controller, 2: change upgrade scheme.
        StandardToken tokenFee;
        uint fee;
    }

    // Struct holding the data for each organization
    struct Organization {
        bool isRegistered;
    }

    mapping(bytes32=>UpgradeProposal) proposals;

    // A mapping from thr organization (Avatar) address to the saved data of the organization:
    mapping(address=>Organization) organizations;

    // A mapping from hashes to parameters (use to store a particular configuration on the controller)
    struct Parameters {
        bytes32 voteParams;
        BoolVoteInterface boolVote;
    }

    mapping(bytes32=>Parameters) parameters;

    /**
     * @dev the constructor takes a token address, fee and beneficiary
     */
    function UpgradeScheme(StandardToken _nativeToken, uint _fee, address _beneficiary) {
        updateParameters(_nativeToken, _fee, _beneficiary, bytes32(0));
    }

    /**
     * @dev hash the parameters, save them if necessary, and return the hash value
     */
    function setParameters(
        bytes32 _voteParams,
        BoolVoteInterface _boolVote
    ) returns(bytes32) 
    {
        bytes32 paramsHash = getParametersHash(_voteParams, _boolVote);
        parameters[paramsHash].voteParams = _voteParams;
        parameters[paramsHash].boolVote = _boolVote;
        return paramsHash;
    }

    /**
     * @dev return a hash of the given parameters
     */
    function getParametersHash(
        bytes32 _voteParams,
        BoolVoteInterface _boolVote
    ) constant returns(bytes32) 
    {
        bytes32 paramsHash = (sha3(_voteParams, _boolVote));
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

  /**
   * @dev porpose an upgrade of the organization's controller
   * @param _avatar avatar of the organization
   * @param _newController address of the new controller that is being porposed
   * @return an id which represents the porposal
   */
    function proposeUpgrade(Avatar _avatar, address _newController) returns(bytes32) {
        Organization memory org = organizations[_avatar];
        require(org.isRegistered); // Check org is registred to use this universal scheme.
        Parameters memory params = parameters[getParametersFromController(_avatar)];
        BoolVoteInterface boolVote = params.boolVote;
        bytes32 proposalId = boolVote.propose(params.voteParams, _avatar, ExecutableInterface(this));
        if (proposals[proposalId].proposalType != 0) {
            revert();
        }
        proposals[proposalId].proposalType = 1;
        proposals[proposalId].newContOrScheme = _newController;
        boolVote.vote(proposalId, true, msg.sender); // Automatically votes `yes` in the name of the opener.
        LogNewProposal(proposalId);
        return proposalId;
    }

    /**
     * @dev porpose to replace this schme by another upgrading scheme
     * @param _avatar avatar of the organization
     * @param _scheme address of the new upgrad ing scheme
     * @param _params ???
     * @param _tokenFee  ???
     * @param _fee ???
     * @return an id which represents the porposal
     */
    function proposeChangeUpgradingScheme(
        Avatar _avatar,
        address _scheme,
        bytes32 _params,
        StandardToken _tokenFee,
        uint _fee
    )
        returns(bytes32)
    {
        Organization memory org = organizations[_avatar];
        Parameters memory params = parameters[getParametersFromController(_avatar)];

        require(org.isRegistered); // Check org is registred to use this universal scheme.
        BoolVoteInterface boolVote = params.boolVote;
        bytes32 proposalId = boolVote.propose(params.voteParams, _avatar, ExecutableInterface(this));
        if (proposals[proposalId].proposalType != 0) {
            revert();
        }
        proposals[proposalId].proposalType = 2;
        proposals[proposalId].newContOrScheme = _scheme;
        proposals[proposalId].params = _params;
        proposals[proposalId].tokenFee = _tokenFee;
        proposals[proposalId].fee = _fee;
        boolVote.vote(proposalId, true, msg.sender); // Automatically votes `yes` in the name of the opener.
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
        require(parameters[getParametersFromController(Avatar(_avatar))].boolVote == msg.sender);
        // Check if vote was successful:
        if (_param != 1) {
            delete proposals[_proposalId];
            return true;
        }
        // Define controller and get the parmas:
        Controller controller = Controller(Avatar(_avatar).owner());
        UpgradeProposal memory proposal = proposals[_proposalId];

        // Upgrading controller:
        if (proposal.proposalType == 1) {
            if (!controller.upgradeController(proposal.newContOrScheme)) {
                revert();
            }
        }

        // Changing upgrade scheme:
        if (proposal.proposalType == 2) {
            bytes4 permissions = controller.getSchemePermissions(this);
            if (proposal.fee != 0) {
                if (!controller.externalTokenApprove(proposal.tokenFee, proposal.newContOrScheme, proposal.fee)) {
                    revert();
                }
            }
            if (!controller.registerScheme(proposal.newContOrScheme, proposal.params, permissions)) {
                revert();
            }
            if (!controller.unregisterSelf()) {
                revert();
            }
        }
        delete proposals[_proposalId];
        return true;
    }
}
