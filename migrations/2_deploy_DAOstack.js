// Imports:
var Avatar = artifacts.require('./schemes/controller/Avatar.sol');
var Controller = artifacts.require('./schemes/controller/Controller.sol');
var GenesisScheme = artifacts.require('./schemes/GenesisScheme.sol');
var GlobalConstraintRegistrar = artifacts.require('./schemes/GlobalConstraintRegistrar.sol');
var MintableToken = artifacts.require('./schemes/controller/MintableToken.sol');
var Reputation = artifacts.require('./schemes/controller/Reputation.sol');
var SchemeRegistrar = artifacts.require('./schemes/SchemeRegistrar.sol');
var SimpleICO = artifacts.require('./SimpleICO.sol');
var SimpleVote = artifacts.require('./SimpleVote.sol');
var SimpleContributionScheme = artifacts.require('./SimpleContributionScheme.sol');
var TokenCapGC = artifacts.require('./TokenCapGC.sol');
var UpgradeScheme = artifacts.require('./UpgradeScheme.sol');

// Instances:
var simpleVoteInst;
var UniversalGenesisSchemeInst;
var schemeRegistrarInst;
var globalConstraintRegistrarInst;
var upgradeSchemeInst;
var ControllerInst;
var OrganizationsBoardInst;
var ReputationInst;
var MintableTokenInst;
var AvatarInst;
var SimpleICOInst;

// DAOstack ORG parameters:
var orgName = "DAOstack";
var tokenName = "Stack";
var tokenSymbol = "STK";
var founders = [web3.eth.accounts[0]];
var initRep = 10;
var initRepInWei = [web3.toWei(initRep)];
var initToken = 1000;
var initTokenInWei = [web3.toWei(initToken)];
var tokenAddress;
var reputationAddress;
var avatarAddress;
var controllerAddress;

// DAOstack parameters for universal schemes:
var voteParametersHash;
var votePrec = 50;
var schemeRegisterParams;
var schemeGCRegisterParams;
var schemeUpgradeParams;

// Universal schemes fees:
var UniversalRegisterFee = web3.toWei(5);

module.exports = async function(deployer) {
    // Deploy GenesisScheme:
    // apparently we must wrap the first deploy call in a then to avoid
    // what seem to be race conditions during deployment
    // await deployer.deploy(GenesisScheme)
    deployer.deploy(GenesisScheme).then(async function(){
      genesisSchemeInst = await GenesisScheme.deployed();
      // Create DAOstack:
      returnedParams = await genesisSchemeInst.forgeOrg(orgName, tokenName, tokenSymbol, founders,
          initTokenInWei, initRepInWei);
      AvatarInst = await Avatar.at(returnedParams.logs[0].args._avatar);
      avatarAddress = AvatarInst.address;
      controllerAddress = await AvatarInst.owner();
      ControllerInst = await Controller.at(controllerAddress);
      tokenAddress = await ControllerInst.nativeToken();
      reputationAddress = await ControllerInst.nativeReputation();
      MintableTokenInst = await MintableToken.at(tokenAddress);
      await deployer.deploy(SimpleVote);
      // Deploy SimpleVote:
      simpleVoteInst = await SimpleVote.deployed();
      // Deploy SchemeRegistrar:
      await deployer.deploy(SchemeRegistrar, tokenAddress, UniversalRegisterFee, avatarAddress);
      schemeRegistrarInst = await SchemeRegistrar.deployed();
      // Deploy UniversalUpgrade:
      await deployer.deploy(UpgradeScheme, tokenAddress, UniversalRegisterFee, avatarAddress);
      upgradeSchemeInst = await UpgradeScheme.deployed();
      // Deploy UniversalGCScheme register:
      await deployer.deploy(GlobalConstraintRegistrar, tokenAddress, UniversalRegisterFee, avatarAddress);
      globalConstraintRegistrarInst = await GlobalConstraintRegistrar.deployed();

      // Voting parameters and schemes params:
      voteParametersHash = await simpleVoteInst.getParametersHash(reputationAddress, votePrec);

      await schemeRegistrarInst.setParameters(voteParametersHash, voteParametersHash, simpleVoteInst.address);
      schemeRegisterParams = await schemeRegistrarInst.getParametersHash(voteParametersHash, voteParametersHash, simpleVoteInst.address);

      await globalConstraintRegistrarInst.setParameters(reputationAddress, votePrec);
      schemeGCRegisterParams = await globalConstraintRegistrarInst.getParametersHash(reputationAddress, votePrec);

      await upgradeSchemeInst.setParameters(voteParametersHash, simpleVoteInst.address);
      schemeUpgradeParams = await upgradeSchemeInst.getParametersHash(voteParametersHash, simpleVoteInst.address);

      // Transferring tokens to org to pay fees:
      await MintableTokenInst.transfer(AvatarInst.address, 3*UniversalRegisterFee);

      var schemesArray = [schemeRegistrarInst.address, globalConstraintRegistrarInst.address, upgradeSchemeInst.address];
      var paramsArray = [schemeRegisterParams, schemeGCRegisterParams, schemeUpgradeParams];
      var permissionArray = [3, 5, 9];
      var tokenArray = [tokenAddress, tokenAddress, tokenAddress];
      var feeArray = [UniversalRegisterFee, UniversalRegisterFee, UniversalRegisterFee];

      // set DAOstack initial schmes:
      await genesisSchemeInst.setInitialSchemes(
        AvatarInst.address,
        schemesArray,
        paramsArray,
        tokenArray,
        feeArray,
        permissionArray);

      // Set SchemeRegistrar nativeToken and register DAOstack to it:
      // TODO: how can this work without having the fees?
      await schemeRegistrarInst.registerOrganization(AvatarInst.address);
      await globalConstraintRegistrarInst.registerOrganization(AvatarInst.address);
      await upgradeSchemeInst.registerOrganization(AvatarInst.address);


      // also deploy a SimpleContributionScheme for general use
      deployer.deploy(SimpleICO, tokenAddress, UniversalRegisterFee, avatarAddress);
    });

    deployer.deploy(SimpleContributionScheme);
    deployer.deploy(TokenCapGC);
};
