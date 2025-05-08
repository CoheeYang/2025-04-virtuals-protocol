// SPDX-License-Identifier: MIT
// Modified from https://github.com/sourlodine/Pump.fun-Smart-Contract/blob/main/contracts/PumpFun.sol
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./FFactory.sol";
import "./IFPair.sol";
import "./FRouter.sol";
import "./FERC20.sol";
import "../virtualPersona/IAgentFactoryV3.sol";

contract Bonding is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address private _feeTo;

    FFactory public factory;
    FRouter public router;
    uint256 public initialSupply;
    uint256 public fee;
    uint256 public constant K = 3_000_000_000_000;//y = kx
    uint256 public assetRate;
    uint256 public gradThreshold;
    uint256 public maxTx;
    address public agentFactory;
    struct Profile {
        address user;
        address[] tokens;
    }

    struct Token {
        address creator;
        address token;
        address pair;
        address agentToken;
        Data data;
        string description;
        uint8[] cores;
        string image;
        string twitter;
        string telegram;
        string youtube;
        string website;
        bool trading;
        bool tradingOnUniswap;
    }

    struct Data {
        address token;
        string name;
        string _name;
        string ticker;
        uint256 supply;
        uint256 price;
        uint256 marketCap;
        uint256 liquidity;
        uint256 volume;
        uint256 volume24H;
        uint256 prevPrice;
        uint256 lastUpdated;
    }

    struct DeployParams {
        bytes32 tbaSalt;
        address tbaImplementation;
        uint32 daoVotingPeriod;
        uint256 daoThreshold;
    }

    DeployParams private _deployParams;

    mapping(address => Profile) public profile;
    address[] public profiles;

    mapping(address => Token) public tokenInfo;
    address[] public tokenInfos;

    event Launched(address indexed token, address indexed pair, uint);
    event Deployed(address indexed token, uint256 amount0, uint256 amount1);
    event Graduated(address indexed token, address agentToken);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address factory_,
        address router_,
        address feeTo_,
        uint256 fee_,
        uint256 initialSupply_,
        uint256 assetRate_,
        uint256 maxTx_,
        address agentFactory_,
        uint256 gradThreshold_
    ) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        factory = FFactory(factory_);
        router = FRouter(router_);

        _feeTo = feeTo_;
        fee = (fee_ * 1 ether) / 1000;

        initialSupply = initialSupply_;
        assetRate = assetRate_;
        maxTx = maxTx_;

        agentFactory = agentFactory_;
        gradThreshold = gradThreshold_;
    }

    function _createUserProfile(address _user) internal returns (bool) {
        address[] memory _tokens;

        Profile memory _profile = Profile({user: _user, tokens: _tokens});

        profile[_user] = _profile;

        profiles.push(_user);

        return true;
    }

    function _checkIfProfileExists(address _user) internal view returns (bool) {
        return profile[_user].user == _user;
    }

    function _approval(address _spender, address _token, uint256 amount) internal returns (bool) {
        IERC20(_token).forceApprove(_spender, amount);

        return true;
    }
//only owner set functions
    function setInitialSupply(uint256 newSupply) public onlyOwner {
        initialSupply = newSupply;
    }

    function setGradThreshold(uint256 newThreshold) public onlyOwner {
        gradThreshold = newThreshold;
    }

    function setFee(uint256 newFee, address newFeeTo) public onlyOwner {
        fee = newFee;
        _feeTo = newFeeTo;
    }

    function setMaxTx(uint256 maxTx_) public onlyOwner {
        maxTx = maxTx_;
    }

    function setAssetRate(uint256 newRate) public onlyOwner {
        require(newRate > 0, "Rate err");

        assetRate = newRate;
    }

    function setDeployParams(DeployParams memory params) public onlyOwner {
        _deployParams = params;
    }
///
    function getUserTokens(address account) public view returns (address[] memory) {
        require(_checkIfProfileExists(account), "User Profile dose not exist.");

        Profile memory _profile = profile[account];

        return _profile.tokens;
    }

    function launch(
        string memory _name,
        string memory _ticker,
        uint8[] memory cores,
        string memory desc,
        string memory img,
        string[4] memory urls,
        uint256 purchaseAmount
    ) public nonReentrant returns (address, address, uint) {//nonReentrant BUG,Upgrade中，一个用了nonReentrant去call另外一个有nonReentrant的函数不支持，因为slot都是一个地方的
        return launchFor(_name, _ticker, cores, desc, img, urls, purchaseAmount, msg.sender);
    }

///`launchFor` function before

//出现的转账动作
//1.assetToken，从msg.sender转initial purchase 到这里（费用转给Feeto）

    function launchFor(
        string memory _name,
        string memory _ticker,
        uint8[] memory cores,
        string memory desc,
        string memory img,
        string[4] memory urls,
        uint256 purchaseAmount,
        address creator
    ) public nonReentrant returns (address, address, uint) {
        //检查钱并转钱
        require(purchaseAmount > fee, "Purchase amount must be greater than fee");
        address assetToken = router.assetToken();
        require(IERC20(assetToken).balanceOf(msg.sender) >= purchaseAmount, "Insufficient amount");
        uint256 initialPurchase = (purchaseAmount - fee);
        IERC20(assetToken).safeTransferFrom(msg.sender, _feeTo, fee);
        IERC20(assetToken).safeTransferFrom(msg.sender, address(this), initialPurchase);//initialPurchase不可能为0

        //创建fERC20
        FERC20 token = new FERC20(string.concat("fun ", _name), _ticker, initialSupply, maxTx);//initial supply是固定的 note 此时此合约有fToken 所有的supply
        uint256 supply = token.totalSupply();//initialSupply，乘了decimal的

        address _pair = factory.createPair(address(token), assetToken);//就硬new pair，不判断之前有无

        bool approved = _approval(address(router), address(token), supply);///approve fERC20,通过safeERC20来进行approve
        require(approved);

        uint256 k = ((K * 10000) / assetRate);/// 3_000_000_000_000 * 10_000 / assetRate(10_000)

        uint256 liquidity = (((k * 10000 ether) / supply) * 1 ether) / 10000;// note supply带decimal 1e18，L也带decimal 1e18
        // 写错了吧?应该是l=k/s，但是 k*10000 ether / supply * 1 ether / 10000 = k*ether/supply *1 ether 
        //而不是 k*ether/(supply *1 ether) 
        //没有，这里是正确的，supply是1e18，相当于l=(K*1e18/supply) *1e18,
        //l和最后的1e18消掉，supply和上面的分子的1e18消掉
        //这个意思是assetToken = k个 fToken (L=k/s)
        
        //数值上，L = (3_000_000_000_000 * 10_000 *1e18/1_000_000_000 *1e18) * 1e18/10_000  
        //         L = 3000 *1e18, S = 1_000_000_000 *1e18

        router.addInitialLiquidity(address(token), supply, liquidity);//note fToken转入pool（pair）中，并让pair mint方法记录此时pool中reserve
        //@audit  bug 现在它说他的reserve有liquidty这么多，但是实际上真实的assetToken金额是purchaseAmount

        Data memory _data = Data({ 
            token: address(token),
            name: string.concat("fun ", _name),
            _name: _name,
            ticker: _ticker,
            supply: supply,
            price: supply / liquidity,
            marketCap: liquidity,
            liquidity: liquidity * 2,
            volume: 0,
            volume24H: 0,
            prevPrice: supply / liquidity,///@audit bug 会成0，如果supply <liquidity，有这种可能性，因为l = k/s, 如果 s/l = s^2/k
            lastUpdated: block.timestamp
        });

        Token memory tmpToken = Token({
            creator: creator,
            token: address(token),
            agentToken: address(0),
            pair: _pair,
            data: _data,
            description: desc,
            cores: cores,
            image: img,
            twitter: urls[0],
            telegram: urls[1],
            youtube: urls[2],
            website: urls[3],
            trading: true, // Can only be traded once creator made initial purchase
            tradingOnUniswap: false
        });
        tokenInfo[address(token)] = tmpToken;
        tokenInfos.push(address(token));
      
    //查一下creator是否在之前的profile中存在，不在就创建profile
        bool exists = _checkIfProfileExists(creator);

        if (exists) {
            Profile storage _profile = profile[creator];

            _profile.tokens.push(address(token));
        } else {
            bool created = _createUserProfile(creator);

            if (created) {
                Profile storage _profile = profile[creator];

                _profile.tokens.push(address(token));
            }
        }

        uint n = tokenInfos.length;

        emit Launched(address(token), _pair, n);

    // Make initial purchase note 开始买intial purchase，approve router转账ip，将assetToken转给router，所获得的funToken转给msg.sender
        IERC20(assetToken).forceApprove(address(router), initialPurchase);
        router.buy(initialPurchase, address(token), address(this));
        token.transfer(msg.sender, token.balanceOf(address(this)));

        return (address(token), _pair, n);
    }
//function after 

//卖出funToken，换回assetToken
    function sell(uint256 amountIn, address tokenAddress) public returns (bool) {
        require(tokenInfo[tokenAddress].trading, "Token not trading");

        address pairAddress = factory.getPair(tokenAddress, router.assetToken());

        IFPair pair = IFPair(pairAddress);

        (uint256 reserveA, uint256 reserveB) = pair.getReserves();//A是funToken,B是assetToken

        (uint256 amount0In, uint256 amount1Out) = router.sell(amountIn, tokenAddress, msg.sender);

        uint256 newReserveA = reserveA + amount0In;//一致
        uint256 newReserveB = reserveB - amount1Out;//一致

        //下面内容与buy逻辑一致
        uint256 duration = block.timestamp - tokenInfo[tokenAddress].data.lastUpdated;

        uint256 liquidity = newReserveB * 2;
        uint256 mCap = (tokenInfo[tokenAddress].data.supply * newReserveB) / newReserveA;
        uint256 price = newReserveA / newReserveB;
        uint256 volume = duration > 86400 ? amount1Out : tokenInfo[tokenAddress].data.volume24H + amount1Out;
        uint256 prevPrice = duration > 86400
            ? tokenInfo[tokenAddress].data.price
            : tokenInfo[tokenAddress].data.prevPrice;


         ///赋值7个值，没少
        tokenInfo[tokenAddress].data.price = price;
        tokenInfo[tokenAddress].data.marketCap = mCap;
        tokenInfo[tokenAddress].data.liquidity = liquidity;
        tokenInfo[tokenAddress].data.volume = tokenInfo[tokenAddress].data.volume + amount1Out;//流水历史，进出都算
        tokenInfo[tokenAddress].data.volume24H = volume;
        tokenInfo[tokenAddress].data.prevPrice = prevPrice;
     

        if (duration > 86400) {//大于24小时
            tokenInfo[tokenAddress].data.lastUpdated = block.timestamp;
        }

        return true;
    }




//call router.buy，还可能会继续call Bonding tax，BondingTax会把转进去的veToken换成真钱给admin取
//已经检查reentry的可能，不太像
    function buy(uint256 amountIn, address tokenAddress) public payable returns (bool) {
        require(tokenInfo[tokenAddress].trading, "Token not trading");//trading状态，launch后默认是true

        address pairAddress = factory.getPair(tokenAddress, router.assetToken());

        IFPair pair = IFPair(pairAddress);

        (uint256 reserveA, uint256 reserveB) = pair.getReserves();//A是funToken,B是assetToken

        (uint256 amount1In, uint256 amount0Out) = router.buy(amountIn, tokenAddress, msg.sender);//买入funToken，转款金额amounIn是assetToken，输出金额amount1In是去除交易费成功转入的assetToken，amount0Out是获得的funToken

        uint256 newReserveA = reserveA - amount0Out;//funToken reserve中少掉这么多
        uint256 newReserveB = reserveB + amount1In;//assetToken reserve中多了这么多



        uint256 duration = block.timestamp - tokenInfo[tokenAddress].data.lastUpdated;

        uint256 liquidity = newReserveB * 2;  // 我不是很清楚为什么是这样的，但是前面也一直规定是*2
        uint256 mCap = (tokenInfo[tokenAddress].data.supply * newReserveB) / newReserveA; // bug 妈逼的不考虑买完的情况， `mCap = s * newAssetReserve / newFunTokenReserve` ，原本的mCap =liquidity，即 original AssetReserve， 
        uint256 price = newReserveA / newReserveB;///@audit bug 就是不怕decimal loss出现0，如果很火热的话，池子的funToken数应该很少，此时价格应该高，但是事实是decimal loss使得价格显示为0
        
        //判断是否超过了24小时
        uint256 volume = duration > 86400 ? amount1In : tokenInfo[tokenAddress].data.volume24H + amount1In;
        uint256 _price = duration > 86400 ? tokenInfo[tokenAddress].data.price : tokenInfo[tokenAddress].data.prevPrice;



        ///赋值7个值，没少
        tokenInfo[tokenAddress].data.price = price;
        tokenInfo[tokenAddress].data.marketCap = mCap;
        tokenInfo[tokenAddress].data.liquidity = liquidity;
        tokenInfo[tokenAddress].data.volume = tokenInfo[tokenAddress].data.volume + amount1In;//累加所有历史
        tokenInfo[tokenAddress].data.volume24H = volume;
        tokenInfo[tokenAddress].data.prevPrice = _price;
 
        if (duration > 86400) {
            tokenInfo[tokenAddress].data.lastUpdated = block.timestamp;
        }

       //最初的reserve是10^9 *1e18，如果买到最后funToken的数量小于85_000_000 *1e18则毕业，
       //INIT_SUPPLY*1e18 - GRADUAL_THRESHOLD = 9.15 *1e8 *1e18
       //理论上需要 assetToken = 3_000_000_000_000/ 9.15 *1e8,大约3k assetToken即可毕业
        if (newReserveA <= gradThreshold && tokenInfo[tokenAddress].trading) {
            _openTradingOnUniswap(tokenAddress);//真奇怪，这些又拿agentFactory创建agentToken作为新的token，然后之前的token通过unwrapToken来换
        }

        return true;
    }



    function _openTradingOnUniswap(address tokenAddress) private {
     //状态信息   
        FERC20 token_ = FERC20(tokenAddress);

        Token storage _token = tokenInfo[tokenAddress];

        require(_token.trading && !_token.tradingOnUniswap, "trading is already open");

        _token.trading = false;
        _token.tradingOnUniswap = true;

        // Transfer asset tokens to bonding contract
        address pairAddress = factory.getPair(tokenAddress, router.assetToken());

        IFPair pair = IFPair(pairAddress);

        uint256 assetBalance = pair.assetBalance();
        uint256 tokenBalance = pair.balance();
    //操作
        router.graduate(tokenAddress);//fToken对应的pair的asset token全部转到这里
    
        IERC20(router.assetToken()).forceApprove(agentFactory, assetBalance);
        uint256 id = IAgentFactoryV3(agentFactory).initFromBondingCurve(
            string.concat(_token.data._name, " by Virtuals"),
            _token.data.ticker,
            _token.cores,
            _deployParams.tbaSalt,
            _deployParams.tbaImplementation,
            _deployParams.daoVotingPeriod,
            _deployParams.daoThreshold,
            assetBalance,
            _token.creator
        );

        address agentToken = IAgentFactoryV3(agentFactory).executeBondingCurveApplication(
            id,//tokenSupplyParams_:
            _token.data.supply / (10 ** token_.decimals()),
            //除去之前的supply带的decimal，即agentToken的supply参数
            //从处为INIT_SUPPLY=1_000_000_000

            tokenBalance / (10 ** token_.decimals()),
            //pair剩下的Ftoken，这里是lpSupply，即agentToken合约中给pool的流通的
            //此时毕业了换的就剩GRADUAL_THRESHOLD =85_000_000

            pairAddress//vault，其他的agentToken都会送入pair，此时pair将拥有1_000_000_000-85_000_000=915_000_000的agentToken
        );
        _token.agentToken = agentToken;

        router.approval(pairAddress, agentToken, address(this), IERC20(agentToken).balanceOf(pairAddress));
        //call router让 pair对bonding此合约进行approve，上限即为pair中agentToken的余额，非常大够unwrapToken花

        token_.burnFrom(pairAddress, tokenBalance);//烧掉pair中所有的fERC20 Token

        emit Graduated(tokenAddress, agentToken);
    }


///funToken转AgentToken，可以让之前fToken的人全部立马转为agentToken，转来的钱都来自pair
///但是当mitigate后 用户还能Unwrap吗？ 
    function unwrapToken(address srcTokenAddress, address[] memory accounts) public {
        Token memory info = tokenInfo[srcTokenAddress];
        require(info.tradingOnUniswap, "Token is not graduated yet");

        FERC20 token = FERC20(srcTokenAddress);
        IERC20 agentToken = IERC20(info.agentToken);
        address pairAddress = factory.getPair(srcTokenAddress, router.assetToken());
        for (uint i = 0; i < accounts.length; i++) {
            address acc = accounts[i];
            uint256 balance = token.balanceOf(acc);
            if (balance > 0) {
                token.burnFrom(acc, balance);
                agentToken.transferFrom(pairAddress, acc, balance);
            }
        }
    }
}
