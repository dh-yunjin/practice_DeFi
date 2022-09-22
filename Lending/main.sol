// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract DreamOracle{
    address public operator;
    mapping(address=>uint256) prices;
    
    constructor() {
        operator = msg.sender;
    }
    
    function getPrice(address token) external view returns (uint256) {
        require(prices[token] != 0, "the price cannot be zero");
        return prices[token];
    }
    
    function setPrice(address token, uint256 price) external {
        require(msg.sender == operator, "only operator can set the price");
        prices[token] = price;
    }
}

/* lending
    ETH를 담보로 사용해서 USDC를 빌리고 빌려줄 수 있는 서비스를 구현하세요.
    // USDC = 미국 달러 기반 스테이블 코인
    
    이자율은 24시간에 0.1% (복리), 
    Loan To Value (LTV)는 50%, // 대출은 담보의 50%까지만 가능
    liquidation threshold는 75%로 하고 // 청산 임계값 - 빌릴 때 코인의 가치보다 75% 아래로 떨어지면 담보가 부족해져서 position이 청산(liquidate)될 수 있다
    // 청산: 은행에 맡겨진 담보를 팔아 대출을 회수하는 과정
    // 청산 방법은 다양하기 때문에 조사 후 bad debt을 최소화에 가장 적합하다고 생각하는 방식을 적용하고 그 이유를 쓰세요.

    담보 가격 정보는 “참고코드"를 참고해 생성한 컨트랙트에서 갖고 오세요.

    실제 토큰을 사용하지 않고 컨트랙트 생성자의 인자로 받은 주소들을 토큰의 주소로 간주합니다.
*/
contract DreamLending is ERC20{
    dOracle = DreamOracle();

    ETH_address = 0x11111111111111111111;
    USDC_address = 0x22222222222222222222;

    mapping(mapping(address => uint256)) public balance; // 이 컨트랙트에 있는 잔고

    mapping(address => mapping(address => uint256)) public balances; // 토큰 별 deposit 잔고
    mapping(address => mapping(address => uint256)) public holdBalance; // 대출로 묶여진 deposit (담보)
    mapping(address => mapping(address => uint256)) public borrow; // 토큰 별 borrow 값
    
    mapping(address => mapping(address => uint)) public borrowStartTime; // 토큰 별 borrow 시간
    
    constructor() {
        // dreamOracle setPrice(임의의토큰주소, 가격)를 통해서 세팅하는 과정 필요
        dOracle.setPrice(ETH_address, 1287.91 USDC); // ETH, 20바이트
        dOracle.setPrice(USDC_address, 0.0007522 ETH); // USDC, 20바이트
    }
    function deposit(address tokenAddress, uint256 amount)
    { // ETH, USDC 입금
        balances[msg.sender][tokenAddress] += amount;
    }
    function withdraw(address tokenAddress, uint256 amount)
    { // Deposit한 본인의 자산은 withdraw할 수 있어야 함
        require(balances[msg.sender][tokenAddress] > amount);
        balances[msg.sender][tokenAddress] -= amount;
    }
    function borrow(address tokenAddress, uint256 amount)
    { // 저장해둔 담보만큼 대출 // tokenAddress는 USDC_address를 의미함
    // tokenAddress는 빌리고자 하는 토큰
        if (tokenAddress == ETH_address){ // deposit된 USDC 잔고로 ETH를 빌려야 함
            // Loan To Value (LTV)는 50%, // 대출은 담보의 50%까지만 가능
            // 대출 리밋 ETH 값 // USDC 잔고 50%에 현재 USDC의 ETH값 곱해서 담보로 등록된 ETH가 어느정도인지
            limit_amount = balances[msg.sender][USDC_address] * 0.5 * dOracle.getPrice(USDC_address); 
            require(limit_amount >= amount); // 담보

            borrow_amount = amount * dOracle.getPrice(ETH_address); // 빌리려는 ETH개수 * 현재 ETH의 USDC값 곱해서 빌리려는 ETH의 USDC가 어느정도인지
            borrow[msg.sender][ETH_address] += amount;
            balances[msg.sender][USDC_address] -= borrow_amount; // 잔고는 감소
            holdBalance[msg.sender][USDC_address] += borrow_amount; // 담보는 증가
            transfer(msg.sender, amount); // 빌린 만큼의 ETH 송금해주기
            borrowStartTime[msg.sender][ETH_address] = block.timestamp;
        }
        else{ // tokenAddress == USDC_address
            limit_amount = balances[msg.sender][ETH_address] * 0.5 * dOracle.getPrice(ETH_address); // 대출 리밋 USDC 값
            require(limit_amount >= amount);

            borrow_amount = amount * dOracle.getPrice(USDC_address); // 빌리려는 USDC개수 * 현재 USDC의 ETH값 곱해서 빌리려는 USDC의 ETH가 어느정도인지
            borrow[msg.sender][USDC_address] += amount;
            balances[msg.sender][ETH_address] -= borrow_amount; // 잔고는 감소
            holdBalance[msg.sender][ETH_address] += borrow_amount; // 담보는 증가
            transfer(msg.sender, amount); // 빌린 만큼의 USDC 송금해주기
            borrowStartTime[msg.sender][USDC_address] = block.timestamp;
        }
        
    }
    function repay(address tokenAddress, uint256 amount)
    { // 대출 상환 / 이자율은 24시간에 0.1% (복리),
        // borrow 시 계약이 생성된 시점과 현재 시간의 차이를 계산? 또는 블록이 생성된 지 몇 시간 지났는지 바로 알기? 24시간으로 나눠서 몫을
        // 그냥 빌려줄 때 부터 컨트랙트에 저장하는 방법밖에 없는 것 같다        
        if (tokenAddress == ETH_address){
            borrow_day = (borrowStartTime[msg.sender][ETH_address] - now) / 24 hours;
            interest = amount * 0.001 ** borrow_day;
            repay_amount = amount + interest; // 갚아야할 금액 계산(이자 포함)
            
            // transfer이 아닌 deposit을 통해서만 => 만약 부족하면 deposit 갔다가 오라고...
            // 부분 상환 없이 100% 상환만 가능하다는 전제로...
            require(balances[msg.sender][ETH_address] >= repay_amount);
            
            borrow[msg.sender][ETH_address] = 0;
            balances[msg.sender][ETH_address] -= interest; // 수수료 떼서 가져가기
            balance[ETH_address] += interest;

            balances[msg.sender][USDC_address] += holdBalance[msg.sender][USDC_address]; // 잔고 증가 - 담보 만큼만 증가
            holdBalance[msg.sender][USDC_address] = 0; // 담보 감소
            borrowStartTime[msg.sender][ETH_address] = 0;
        }
        else{ // tokenAddress == USDC_address
            borrow_day = (borrowStartTime[msg.sender][USDC_address] - now) / 24 hours;
            interest = amount * 0.001 ** borrow_day;
            repay_amount = amount + interest; // 갚아야할 금액 계산(이자 포함)
            
            require(balances[msg.sender][USDC_address] >= repay_amount);

            borrow[msg.sender][USDC_address] -= amount;
            balances[msg.sender][USDC_address] -= interest; // 수수료 떼서 가져가기
            balance[USDC_address] += interest;

            balances[msg.sender][ETH_address] += holdBalance[msg.sender][ETH_address];
            holdBalance[msg.sender][ETH_address] = 0;
            borrowStartTime[msg.sender][USDC_address] = 0;
        }
        
    }
    function liquidate(address user, address tokenAddress, uint256 amount)
    { // 담보를 청산하여 USDC 확보
    // liquidation threshold(75%)가 되었을 경우 담보를 청산해서 토큰을 확보함
    // 75%일 때 liquidate 호출은 외부에서...
    // tokenAddress로는 청산할 토큰의 종류가 들어온다
    // 청산해서 대출금을 자동 상환하고 남은 금액은 잔고에 넣어두기

    // 청산 방법 - bad dept를 최소화하기 위해서 가장 높은 가격일 때(현재) 팔아서 바로 USDC로 확보하기
        if (tokenAddress == ETH_address){
            balance[user][USDC_address] += holdBalance[user][tokenAddress] * getPrice(tokenAddress);
            repay(tokenAddress, amount);
        }
        else{ // tokenAddress == USDC_address{
            balance[user][ETH_address] += holdBalance[user][tokenAddress] * getPrice(tokenAddress);
            repay(tokenAddress, amount);
        }
    }

    function transfer(address to, uint256 amount) external returns (bool){
        require(to != address(0), "transfer to the zero address");

        emit Transfer(this.address, to, amount);
    }
}

