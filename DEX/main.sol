// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


// CPMM (xy=k) 방식의 AMM을 사용하는 DEX
// Pool을 이루는 두 개의 토큰의 곱이 상수 k로 일정하다

// Swap : Pool 생성 시 지정된 두 종류의 토큰을 서로 교환할 수 있어야 합니다. 
// Input 토큰과 Input 수량, 최소 Output 요구량을 받아서 Output 토큰으로 바꿔주고 최소 요구량에 미달할 경우 revert 해야합니다. 
// 수수료 0.1%
// Add / Remove Liquidity : ERC-20 기반 LP 토큰을 사용해야 합니다. 
// 수수료 수입과 Pool에 기부된 금액을 제외하고는 더 많은 토큰을 회수할 수 있는 취약점이 없어야 합니다. 
// Concentrated Liquidity는 필요 없습니다.

contract DEX is ERC20, ERC20Permit, ERC20Burnable, ERC20Mintable {
    uint256 liquidityPool_TokenX;
    uint256 liquidityPool_TokenY;

    uint k; // = TokenX * TokenY 항상 일정
    
    mapping(address => uint256) public myTokenXOnPool;
    mapping(address => uint256) public myTokenYOnPool;

    constructor{
        ERC20("Dreamacademy LP Token", "DLT"); // LP토큰 만들기

        ERC20("TokenX", "TKX"); // TokenX 만들기
        ERC20("TokenY", "TKY"); // TokenY 만들기
        // 1. 어떤 방법으로든 어떤 토큰을 대상으로 하는지가 없기 때문에 -> 호출하는 쪽에서 control하는게 아닐까?
        // 예를 들면 X -> Y를 요청하면 transfer로 받은 것은 자연스럽게 Y일 것이다...라는 식으로..다른(호출) 컨트랙트에 의존

        // 2. 토큰을 아예 다른 체인이 아닌 이 DEX 컨트랙트에서 다 만들어졌다는 느낌으로 가야하는건지
        // 다른 체인에서 만들어졌다면 다른 체인과 상호작용해야할테니 일단 개념 프로젝트는 위 가정이 맞는 것 같다
        // 근데 이렇게 해도 transfer할 때 어떤 토큰을 보낼지가 없기때문에 1.도 맞는 가정이라 생각함

        liquidityPool_TokenX = 0;
        liquidityPool_TokenY = 0;

        k = 1; // 이렇게 임의로 둬도 되는건지...
    }

    /* DEX 거래소 순서
        // 일단 두 가지의 토큰만 교환하는 거래소

        A. 유동성 풀 기반 만들기
        (1) 유동성 풀에 기부자들이 토큰을 등록한다 (고객이 addLiquidity 함수 호출)
        (2) 기부자들은 LP토큰을 보상으로 받는다
        (3) 기부자 각각이 얼마나 기부했는지 저장하는 공간 필요
        (4) 기부한 걸 빼낼 때 LP토큰도 같이 반납
    
        B. 교환하기 
        (1) swap을 통해서 고객이 교환을 요청
            (단, 이 때 최소 Output 요구량을 함께 받아서 풀에 남아있는 토큰이 이것보다 작으면 우리 거래소에서 불가능하다고 revert할 것)
        (2) swap의 대상이 되는 토큰에 대해 removeLiquidity 
        (3) 들어온 토큰은 유동성 풀에 저장/transfer을 통해 교환 대상이 되는 토큰 보내주기
            (단, 얼마나 보내줄 지는 0.1% 수수료 떼고 계산해야 함 - 수수료는 유동성 풀에 저장됨)
    */

    function swap(uint256 tokenXAmount, uint256 tokenYAmount, uint256 tokenMinimumOutputAmount) external returns (uint256 outputAmount)
    { // 교환은 고객만...
        // tokenXAmount / tokenYAmount 중 하나는 무조건 0이어야 합니다. 수량이 0인 토큰으로 스왑됨.
        require(!(tokenXAmount == 0 && tokenYAmount == 0));
        require(tokenXAmount == 0 || tokenYAmount == 0);

        if(tokenXAmount != 0){
            swap_tokenYAmount = (k / tokenXAmount);
            swap_fee = swap_tokenYAmount * 0.001;
            swap_tokenYAmount -= swap_fee;

            if (swap_tokenYAmount < tokenMinimumOutputAmount) revert(); // 요구한 것보다 적게 환전되면 거부

            else{
                this.addLiquidity(tokenXAmount, 0, tokenMinimumOutputAmount); // 들어온 X만큼 유동성 풀에 등록
                liquidityPool_TokenY -= swap_tokenYAmount; // 교환한 Y만큼 유동성 풀에서 빼내고
                transfer(msg.sender, swap_tokenYAmount); // 전송하기
                return swap_tokenYAmount;
            }
        }
        else{ // tokenYAmount != 0 // 위에서 tokenX와 Y만 바뀌면 됨
            swap_tokenXAmount = (k / tokenYAmount);
            swap_fee = swap_tokenXAmount * 0.001;
            swap_tokenXAmount -= swap_fee;
            if (swap_tokenXAmount < tokenMinimumOutputAmount) revert(); // 요구한 것보다 적게 환전되면 거부
            else{
                this.addLiquidity(tokenYAmount, 0, tokenMinimumOutputAmount); // 들어온 Y만큼 유동성 풀에 등록
                liquidityPool_TokenX -= swap_tokenXAmount; // 교환한 X만큼 유동성 풀에서 빼내고
                transfer(msg.sender, swap_tokenXAmount); // 전송하기
                return swap_tokenXAmount;
                // return으로 outputAmount를 돌려주는 걸 보니 사실 교환 transfer 로직은 밖에서 되는 게 아닐까? 
                // => 이렇게 하면 두 컨트랙트 간 무결성 검증은...
            }
        }
    }
    
    function addLiquidity(uint256 tokenXAmount, uint256 tokenYAmount, uint256 minimumLPTokenAmount) external returns (uint256 LPTokenAmount){
        // 유동성 풀에 토큰을 등록하기
        // 1. 기부할 때 - minimumLPTokenAmount가 0일 것
        // 2. 교환할 때 - minimumLPTokenAmount가 0 초과일 것
        // (실제 DEX에서 이런 식으로 하는지는 모르겠지만...)

        if (minimumLPTokenAmount == 0){ // 기부할때
            if(tokenXAmount != 0){
                liquidityPool_TokenX += tokenXAmount; 
                myTokenXOnPool[msg.sender] += tokenXAmount;
                
                // 유동성 풀에 내 지분이 얼마나 있느냐에 따라서 LP Token 지급
                LP_stake = myTokenXOnPool[msg.sender] / liquidityPool_TokenX;
                transfer(msg.sender, LP_stake); 
                // 근데 이렇게 발급해주면 다른 기부자가 pool에 많이 기부하게 되면 자산이 변동되어야 하는 것 아닌지
            }
            else{
                liquidityPool_TokenY += tokenYAmount; 
                myTokenYOnPool[msg.sender] += tokenYAmount;

                LP_stake = myTokenYOnPool[msg.sender] / liquidityPool_TokenY;
                transfer(msg.sender, LP_stake); 
            }
            
        }
        else{ // 교환할 때
            if(tokenXAmount != 0){
                liquidityPool_TokenX += tokenXAmount; 
            }
            else{ liquidityPool_TokenY += tokenYAmount; }
        }
    }
    function removeLiquidity(uint256 LPTokenAmount, uint256 minimumTokenXAmount, uint256 minimumTokenYAmount) external{
        // 유동성 풀에서 토큰을 빼내기(기부자)
        require(!(minimumTokenXAmount == 0 && minimumTokenYAmount == 0));
        require(minimumTokenXAmount == 0 || minimumTokenYAmount == 0);

        if(minimumTokenXAmount != 0){
            // 일정 LP토큰만큼을 TokenX로 교환하기
            // LP_stake는 LPTokenAmount와 동일
            returnToken = LPTokenAmount * liquidityPool_TokenX;

            if(returnToken < minimumTokenXAmount) revert(); // 요구한 것보다 적게 환전되면 거부
            else{
                myTokenXOnPool[msg.sender] -= returnToken;
                liquidityPool_TokenX -= returnToken;
                transfer(msg.sender, returnToken);
            }

        }
        else{ // minimumTokenYAmount != 0
            returnToken = LPTokenAmount * liquidityPool_TokenY;

            if(returnToken < minimumTokenYAmount) revert(); // 요구한 것보다 적게 환전되면 거부
            else{
                myTokenYOnPool[msg.sender] -= returnToken;
                liquidityPool_TokenY -= returnToken;
                transfer(msg.sender, returnToken);
            }
        }
    }

    function transfer(address to, uint256 lpAmount) external returns (bool){ 
        // 기부 보상인 LP를 송금할 때 사용하는 함수...이지만 다른 토큰도 통용되어야할 것 같다.
        require(to != address(0), "transfer to the zero address");

        emit Transfer(this.address, to, lpAmount);
    }
}