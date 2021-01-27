pragma solidity ^0.6.0;

import { TokenInterface } from "../common/interfaces.sol";
import { Stores } from "../common/stores.sol";
import { DSMath } from "../common/math.sol";

import '@uniswap/lib/contracts/libraries/Babylonian.sol';
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";


interface ILinkswapRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, uint tradingFeePercent) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, uint tradingFeePercent) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path, uint tradingFeePercent) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path, uint tradingFeePercent) external view returns (uint[] memory amounts);
}

interface ILinkswapFactory {
  function getPair(address tokenA, address tokenB) external view returns (address pair);
  function allPairs(uint) external view returns (address pair);
  function allPairsLength() external view returns (uint);

  function createPair(
        address newToken,
        uint256 newTokenAmount,
        address lockupToken, // LINK or WETH
        uint256 lockupTokenAmount,
        uint256 lockupPeriod,
        address listingFeeToken
    ) external returns (address pair);
}

interface ILinkswapERC20 {
  function balanceOf(address owner) external view returns (uint);

  function approve(address spender, uint value) external returns (bool);
  function transfer(address to, uint value) external returns (bool);
  function transferFrom(address from, address to, uint value) external returns (bool);
}

interface ILinkswapPair {
  function factory() external view returns (address);
  function token0() external view returns (address);
  function token1() external view returns (address);
  function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
  function price0CumulativeLast() external view returns (uint);
  function price1CumulativeLast() external view returns (uint);
}

contract LinkswapHelpers is Stores, DSMath {
    using SafeMath for uint256;

    /**
     * @dev Return WETH address
     */
    function getAddressWETH() internal pure returns (address) {
        return 0x514910771af9ca656af840dff83e8264ecf986ca; // mainnet
        // return 0xa36085f69e2889c224210f603d836748e7dc0088; // kovan
    }
    
    /**
     * @dev Return WETH address
     */
    function getAddressLINK() internal pure returns (address) {
        return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // mainnet
        // return 0xd0A1E359811322d97991E03f863a0C30C2cF029C; // kovan
    }

    /**
     * @dev Return LINKSWAP router Address
     */
    function getLinkswapAddr() internal pure returns (address) {
        return 0xA7eCe0911FE8C60bff9e99f8fAFcDBE56e07afF1;
    }

    function convert18ToDec(uint _dec, uint256 _amt) internal pure returns (uint256 amt) {
        amt = (_amt / 10 ** (18 - _dec));
    }

    function convertTo18(uint _dec, uint256 _amt) internal pure returns (uint256 amt) {
        amt = mul(_amt, 10 ** (18 - _dec));
    }

    function getTokenBalace(address token) internal view returns (uint256 amt) {
        amt = token == getEthAddr() ? address(this).balance : TokenInterface(token).balanceOf(address(this));
    }

    function changeEthAddress(address buy, address sell) internal pure returns(TokenInterface _buy, TokenInterface _sell){
        _buy = buy == getEthAddr() ? TokenInterface(getAddressWETH()) : TokenInterface(buy);
        _sell = sell == getEthAddr() ? TokenInterface(getAddressWETH()) : TokenInterface(sell);
    }

    function convertEthToWeth(TokenInterface token, uint amount) internal {
        if(address(token) == getAddressWETH()) token.deposit.value(amount)();
    }

    function convertWethToEth(TokenInterface token, uint amount) internal {
       if(address(token) == getAddressWETH()) {
            token.approve(getAddressWETH(), amount);
            token.withdraw(amount);
        }
    }

    function getExpectedBuyAmt(
        ILinkswapRouter router,
        address[] memory paths,
        uint sellAmt
    ) internal view returns(uint buyAmt) {
        ILinkswapFactory factory = ILinkswapFactory(router.factory());
        address pair = factory.getPair(paths[0], paths[1]);
        address token0Addr = ILinkswapPair(factory.pair.token0());
        address token1Addr = ILinkswapPair(factory.pair.token1());
        address linkAddr = TokenInterface(getAddressLINK());
        uint tradingFeePercent = (token0Addr == linkAddr || token1Addr == linkAddr) ? 2500: 3000; // TODO check with Tec
        uint[] memory amts = router.getAmountsOut(
            sellAmt,
            paths,
            tradingFeePercent
        );
        buyAmt = amts[1];
    }

    function getExpectedSellAmt(
        ILinkswapRouter router,
        address[] memory paths,
        uint buyAmt
    ) internal view returns(uint sellAmt) {
        ILinkswapFactory factory = ILinkswapFactory(router.factory());
        address pair = factory.getPair(paths[0], paths[1]);
        address token0Addr = ILinkswapPair(factory.pair.token0());
        address token1Addr = ILinkswapPair(factory.pair.token1());
        address linkAddr = TokenInterface(getAddressLINK());
        uint tradingFeePercent = (token0Addr == linkAddr || token1Addr == linkAddr) ? 2500: 3000;
        uint[] memory amts = router.getAmountsIn(
            buyAmt,
            paths,
            tradingFeePercent
        );
        sellAmt = amts[0];
    }

    function checkPair(
        ILinkswapRouter router,
        address[] memory paths
    ) internal view {
        address pair = ILinkswapFactory(router.factory()).getPair(paths[0], paths[1]);
        require(pair != address(0), "No-exchange-address");
    }

    function getPaths(
        address buyAddr,
        address sellAddr
    ) internal pure returns(address[] memory paths) {
        paths = new address[](2);
        paths[0] = address(sellAddr);
        paths[1] = address(buyAddr);
    }

    function changeEthToWeth(
        address[] memory tokens
    ) internal pure returns(TokenInterface[] memory _tokens) {
        _tokens = new TokenInterface[](2);
        _tokens[0] = tokens[0] == getEthAddr() ? TokenInterface(getAddressWETH()) : TokenInterface(tokens[0]);
        _tokens[1] = tokens[1] == getEthAddr() ? TokenInterface(getAddressWETH()) : TokenInterface(tokens[1]);
    }

    function calculateSwapInAmount(uint256 reserveIn, uint256 userIn)
        internal
        pure
        returns (uint256)
    {
         return
         // TODO I don't understand this or where the numbers come from
            Babylonian
                .sqrt(
                    reserveIn.mul(
                        userIn.mul(3988000).add(reserveIn.mul(3988009))
                    )
                ).sub(reserveIn.mul(1997)) / 1994;
    }
}

contract LiquidityHelpers is LinkswapHelpers {
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint slippage
    ) internal returns (uint _amtA, uint _amtB, uint _liquidity) {
        ILinkswapRouter router = ILinkswapRouter(getLinkswapAddr());
        (TokenInterface _tokenA, TokenInterface _tokenB) = changeEthAddress(tokenA, tokenB);

        convertEthToWeth(_tokenA, amountADesired);
        convertEthToWeth(_tokenB, amountBDesired);
        _tokenA.approve(address(router), 0);
        _tokenA.approve(address(router), amountADesired);

        _tokenB.approve(address(router), 0);
        _tokenB.approve(address(router), amountBDesired);

        uint minAmtA = wmul(sub(WAD, slippage), amountADesired);
        uint minAmtB = wmul(sub(WAD, slippage), amountBDesired);

       (_amtA, _amtB, _liquidity) = router.addLiquidity(
            address(_tokenA),
            address(_tokenB),
            amountADesired,
            amountBDesired,
            minAmtA,
            minAmtB,
            address(this),
            now + 1
        );

        if (_amtA < amountADesired) {
            convertWethToEth(_tokenA, _tokenA.balanceOf(address(this)));
        }

        if (_amtB < amountBDesired) {
            convertWethToEth(_tokenB, _tokenB.balanceOf(address(this)));
        }
    }

    function _addSingleLiquidity(
        address tokenA,
        address tokenB,
        uint amountA,
        uint minLSLPAmount
    ) internal returns (uint _amtA, uint _amtB, uint _liquidity) {
        ILinkswapRouter router = ILinkswapRouter(getLinkswapAddr());
        (TokenInterface _tokenA, TokenInterface _tokenB) = changeEthAddress(tokenA, tokenB);
        
        uint256 _amountA = amountA;
        
        if (amountA == uint(-1)) {
            _amountA = tokenA == getEthAddr() ? address(this).balance : _tokenA.balanceOf(address(this));
        }

        convertEthToWeth(_tokenA, _amountA);


        uint256 _amountB; 
        
        (_amountA, _amountB)= _swapSingleToken(router, _tokenA, _tokenB, _amountA);

        _tokenA.approve(address(router), 0);
        _tokenA.approve(address(router), _amountA);

        _tokenB.approve(address(router), 0);
        _tokenB.approve(address(router), _amountB);

       (_amtA, _amtB, _liquidity) = router.addLiquidity(
            address(_tokenA),
            address(_tokenB),
            _amountA,
            _amountB,
            1, // TODO check LS minumums
            1, // TODO check LS minumums
            address(this),
            now + 1
        );

        require(_liquidity >= minLSLPAmount, "too much slippage");

        if (_amountA > _amtA) {
            convertWethToEth(_tokenA, _tokenA.balanceOf(address(this)));
        }

        if (_amountB > _amtB) {
            convertWethToEth(_tokenB, _tokenB.balanceOf(address(this)));
        }
    }

    function _swapSingleToken(
        ILinkswapRouter router,
        TokenInterface tokenA,
        TokenInterface tokenB,
        uint _amountA
    ) internal returns(uint256 amountA, uint256 amountB){
        ILinkswapFactory factory = ILinkswapFactory(router.factory());
        ILinkswapPair lpToken = ILinkswapPair(factory.getPair(address(tokenA), address(tokenB)));
        require(address(lpToken) != address(0), "No-exchange-address");
        
        (uint256 reserveA, uint256 reserveB, ) = lpToken.getReserves();
        uint256 reserveIn = lpToken.token0() == address(tokenA) ? reserveA : reserveB;
        uint256 swapAmtA = calculateSwapInAmount(reserveIn, _amountA);

        address[] memory paths = getPaths(address(tokenB), address(tokenA));

        tokenA.approve(address(router), swapAmtA);

        amountB = router.swapExactTokensForTokens(
            swapAmtA,
            1, // TODO check LS minimum
            paths,
            address(this),
            now + 1
        )[1];

        amountA = sub(_amountA, swapAmtA);
    }

    function _removeLiquidity(
        address tokenA,
        address tokenB,
        uint _amt,
        uint unitAmtA,
        uint unitAmtB
    ) internal returns (uint _amtA, uint _amtB, uint _uniAmt) {
        ILinkswapRouter router;
        TokenInterface _tokenA;
        TokenInterface _tokenB;
        (router, _tokenA, _tokenB, _uniAmt) = _getRemoveLiquidityData(
            tokenA,
            tokenB,
            _amt
        );
        {
        uint minAmtA = convert18ToDec(_tokenA.decimals(), wmul(unitAmtA, _uniAmt));
        uint minAmtB = convert18ToDec(_tokenB.decimals(), wmul(unitAmtB, _uniAmt));
        (_amtA, _amtB) = router.removeLiquidity(
            address(_tokenA),
            address(_tokenB),
            _uniAmt,
            minAmtA,
            minAmtB,
            address(this),
            now + 1
        );
        }
        convertWethToEth(_tokenA, _amtA);
        convertWethToEth(_tokenB, _amtB);
    }

    function _getRemoveLiquidityData(
        address tokenA,
        address tokenB,
        uint _amt
    ) internal returns (ILinkswapRouter router, TokenInterface _tokenA, TokenInterface _tokenB, uint _lslpAmt) {
        router = ILinkswapRouter(getLinkswapAddr());
        (_tokenA, _tokenB) = changeEthAddress(tokenA, tokenB);
        address exchangeAddr = ILinkswapFactory(router.factory()).getPair(address(_tokenA), address(_tokenB));
        require(exchangeAddr != address(0), "pair-not-found.");

        TokenInterface lslpToken = TokenInterface(exchangeAddr);
        _lslpAmt = _amt == uint(-1) ? lslpToken.balanceOf(address(this)) : _amt;
        lslpToken.approve(address(router), _lslpAmt);
    }
}

contract LinkswapLiquidity is LiquidityHelpers {
    event LogDepositLiquidity(
        address indexed tokenA,
        address indexed tokenB,
        uint amtA,
        uint amtB,
        uint lslpAmount,
        uint getIdA,
        uint getIdB,
        uint setId
    );

    event LogWithdrawLiquidity(
        address indexed tokenA,
        address indexed tokenB,
        uint amountA,
        uint amountB,
        uint lslpAmount,
        uint getId,
        uint[] setId
    );


    /**
     * @dev Deposit Liquidity.
     * @param tokenA tokenA address.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
     * @param tokenB tokenB address.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
     * @param amountADesired tokenA amount.
     * @param amountBDesired tokenB amount.
     * @param slippage slippage for tokenA & tokenB.(For 1%: 1e16, 10%: 1e17)
     * @param getIdA Get tokenA amount at this ID from `InstaMemory` Contract.
     * @param getIdB Get tokenB amount at this ID from `InstaMemory` Contract.
     * @param setId Set token amount at this ID in `InstaMemory` Contract.
    */
    function deposit(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint slippage,
        uint getIdA,
        uint getIdB,
        uint setId
    ) external payable {
        uint _amtADesired = getUint(getIdA, amountADesired);
        uint _amtBDesired = getUint(getIdB, amountBDesired);

        (uint _amtA, uint _amtB, uint _lslpAmt) = _addLiquidity(
                                            tokenA,
                                            tokenB,
                                            _amtADesired,
                                            _amtBDesired,
                                            slippage
                                        );
        setUint(setId, _lslpAmt);

        emit LogDepositLiquidity(
            tokenA,
            tokenB,
            _amtA,
            _amtB,
            _lslpAmt,
            getIdA,
            getIdB,
            setId
        );

    }


     /**
     * @dev Deposit Liquidity using Single token.
     * @param tokenA tokenA address.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
     * @param tokenB tokenB address.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
     * @param amountA tokenA amount.
     * @param minLSLPAmount min LSLP token amount.
     * @param getId Get tokenA amount at this ID from `InstaMemory` Contract.
     * @param setId Set token amount at this ID in `InstaMemory` Contract.
    */
    function singleDeposit(
        address tokenA,
        address tokenB,
        uint amountA,
        uint minLSLPAmount,
        uint getId,
        uint setId
    ) external payable {
        uint _amt = getUint(getId, amountA);

        (uint _amtA, uint _amtB, uint _lslpAmt) = _addSingleLiquidity(
                                            tokenA,
                                            tokenB,
                                            _amt,
                                            minLSLPAmount
                                        );
        setUint(setId, _lslpAmt);

        emit LogDepositLiquidity(
            tokenA,
            tokenB,
            _amtA,
            _amtB,
            _lslpAmt,
            getId,
            0,
            setId
        );
    }

       

    /**
     * @dev Withdraw Liquidity.
     * @param tokenA tokenA address.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
     * @param tokenB tokenB address.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
     * @param lslpAmt LSLP token amount.
     * @param unitAmtA unit amount of amtA/lslpAmt with slippage.
     * @param unitAmtB unit amount of amtB/lslpAmt with slippage.
     * @param getId Get token amount at this ID from `InstaMemory` Contract.
     * @param setIds Set token amounts at this IDs in `InstaMemory` Contract.
    */
    function withdraw(
        address tokenA,
        address tokenB,
        uint lslpAmt,
        uint unitAmtA,
        uint unitAmtB,
        uint getId,
        uint[] calldata setIds
    ) external payable {
        uint _amt = getUint(getId, lslpAmt);

        (uint _amtA, uint _amtB, uint _lslpAmt) = _removeLiquidity(
            tokenA,
            tokenB,
            _amt,
            unitAmtA,
            unitAmtB
        );

        setUint(setIds[0], _amtA);
        setUint(setIds[1], _amtB);

         emit LogWithdrawLiquidity(
            tokenA,
            tokenB,
            _amtA,
            _amtB,
            _lslpAmt,
            getId,
            setIds
        );
    }
}

contract LinkswapResolver is LinkswapLiquidity {
    event LogBuy(
        address indexed buyToken,
        address indexed sellToken,
        uint256 buyAmt,
        uint256 sellAmt,
        uint256 getId,
        uint256 setId
    );

    event LogSell(
        address indexed buyToken,
        address indexed sellToken,
        uint256 buyAmt,
        uint256 sellAmt,
        uint256 getId,
        uint256 setId
    );

    /**
     * @dev Buy ETH/ERC20_Token.
     * @param buyAddr buying token address.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
     * @param sellAddr selling token amount.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
     * @param buyAmt buying token amount.
     * @param unitAmt unit amount of sellAmt/buyAmt with slippage.
     * @param getId Get token amount at this ID from `InstaMemory` Contract.
     * @param setId Set token amount at this ID in `InstaMemory` Contract.
    */
    function buy(
        address buyAddr,
        address sellAddr,
        uint buyAmt,
        uint unitAmt,
        uint getId,
        uint setId
    ) external payable {
        uint _buyAmt = getUint(getId, buyAmt);
        (TokenInterface _buyAddr, TokenInterface _sellAddr) = changeEthAddress(buyAddr, sellAddr);
        address[] memory paths = getPaths(address(_buyAddr), address(_sellAddr));

        uint _slippageAmt = convert18ToDec(_sellAddr.decimals(),
            wmul(unitAmt, convertTo18(_buyAddr.decimals(), _buyAmt)));

        ILinkswapRouter router = ILinkswapRouter(getLinkswapAddr());

        checkPair(router, paths);
        uint _expectedAmt = getExpectedSellAmt(router, paths, _buyAmt);
        require(_slippageAmt >= _expectedAmt, "Too much slippage");

        convertEthToWeth(_sellAddr, _expectedAmt);
        _sellAddr.approve(address(router), _expectedAmt);

        uint _sellAmt = router.swapTokensForExactTokens(
            _buyAmt,
            _expectedAmt,
            paths,
            address(this),
            now + 1
        )[0];

        convertWethToEth(_buyAddr, _buyAmt);

        setUint(setId, _sellAmt);

        emit LogBuy(buyAddr, sellAddr, _buyAmt, _sellAmt, getId, setId);
    }

    /**
     * @dev Sell ETH/ERC20_Token.
     * @param buyAddr buying token address.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
     * @param sellAddr selling token amount.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
     * @param sellAmt selling token amount.
     * @param unitAmt unit amount of buyAmt/sellAmt with slippage.
     * @param getId Get token amount at this ID from `InstaMemory` Contract.
     * @param setId Set token amount at this ID in `InstaMemory` Contract.
    */
    function sell(
        address buyAddr,
        address sellAddr,
        uint sellAmt,
        uint unitAmt,
        uint getId,
        uint setId
    ) external payable {
        uint _sellAmt = getUint(getId, sellAmt);
        (TokenInterface _buyAddr, TokenInterface _sellAddr) = changeEthAddress(buyAddr, sellAddr);
        address[] memory paths = getPaths(address(_buyAddr), address(_sellAddr));

        if (_sellAmt == uint(-1)) {
            _sellAmt = sellAddr == getEthAddr() ? address(this).balance : _sellAddr.balanceOf(address(this));
        }

        uint _slippageAmt = convert18ToDec(_buyAddr.decimals(),
            wmul(unitAmt, convertTo18(_sellAddr.decimals(), _sellAmt)));

        ILinkswapRouter router = ILinkswapRouter(getLinkswapAddr());

        checkPair(router, paths);
        uint _expectedAmt = getExpectedBuyAmt(router, paths, _sellAmt);
        require(_slippageAmt <= _expectedAmt, "Too much slippage");

        convertEthToWeth(_sellAddr, _sellAmt);
        _sellAddr.approve(address(router), _sellAmt);

        uint _buyAmt = router.swapExactTokensForTokens(
            _sellAmt,
            _expectedAmt,
            paths,
            address(this),
            now + 1
        )[1];

        convertWethToEth(_buyAddr, _buyAmt);

        setUint(setId, _buyAmt);

        emit LogSell(buyAddr, sellAddr, _buyAmt, _sellAmt, getId, setId);
    }
}


contract ConnectLinkswap is LinkswapResolver {
    string public name = "LINKSWAP-v1.1";
}