pragma solidity ^0.6.0;
/* SPDX-License-Identifier: MIT */

contract xSafeMath 
{
    function add(uint256 a, uint256 b) internal pure returns (uint256)
    {   uint256 c = a + b;
        require(c >= a, "xSafeMath: addition overflow.");
        return c;}

    function sub(uint256 a, uint256 b) internal pure returns (uint256)
    {   return sub(a, b, "xSafeMath: subtraction overflow.");}

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) 
    {   require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;}

    function mul(uint256 a, uint256 b) internal pure returns (uint256)
    {   if (a == 0) { return 0; }
        uint256 c = a * b;
        require(c / a == b, "xSafeMath: multiplication overflow.");
        return c;}

    function div(uint256 a, uint256 b) internal pure returns (uint256)
    {   return div(a, b, "xSafeMath: division by zero.");  }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256)
    {   require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;}

    function percent(uint numerator, uint denominator, uint precision) internal pure returns(uint quotient) 
    {   uint _numerator  = numerator * 10 ** (precision+1);
        uint _quotient =  ((_numerator / denominator) + 5) / 10;
        return ( _quotient);}

    function getPercent(uint256 xpercent, uint256 number) internal pure returns (uint256 result)
    {   return number * xpercent / 100;   }
}

interface DOGS_ERC20
{
    function transfer(address _to, uint _value) external returns (bool success);
    function balanceOf(address _owner) external returns (uint256 balance);
    function approve(address _spender, uint256 _amount) external returns (bool success);
    function mintStableDOG(uint256 _amount) external returns (bool success);
    function burn(uint256 _amount) external returns (bool success);
}

interface OMNIDEX_INTERFACE
{
    function getReserves() external pure returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) 
             external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
    external returns (uint[] memory amounts);
}

contract StableDOG is xSafeMath
{
    /* <------ StableDOG Gateway ------> */
    /* <------ StableDOG Gateway ------> */
    OMNIDEX_INTERFACE private OMNIDEX_USDOG_WTLOS;
    OMNIDEX_INTERFACE private OMNIDEX_USDC_WTLOS;

    OMNIDEX_INTERFACE private OMNIDEX_ROUTER;

    DOGS_ERC20 private USDOG_CALL;
    DOGS_ERC20 private DOG_CALL;

    address public omnidex_router_address = 0xF9678db1CE83f6f51E5df348E2Cc842Ca51EfEc1; /*  */
    address public usdog_pair = 0x0BD752Bd703f44417f4B24D0608C03eF508A6904; /* stabledog/wtlos pair, needed for getReserves() init OmniDex interface. */
    address public usdc_pair  = 0x651Fcc98a348C91FDF087903c25A638a25344dFf; /* usdc/wtlos pair, needed for getReserves(). */
    address public dog_token  = 0x5C8F2334BD0e7B76e15a7869E31c1F1A654a2B62;
    address public usdog_token = 0x470Bb4C2499726DC7329A7874E82b9b3578eA891;
    address public fee_address = 0xA9cdf57F08149243493aA52a62D0C511c5D9620a;
    address public lp_fee_address = 0x39a986d7Deb4c3Ec096f3dDb349527bd3d820E3a;
    address public owner_addr;
    address public self_address;

    uint256 public upper_limit = 105; // $1.05
    uint256 public lower_limit = 95;  // $0.95

    uint256 public stabilize_base_usdog = 100;  /* 250 USDOG is the base that will be sold, increased according to actual price. */
    uint256 public stabilize_base_dog   = 1000; /* 1000 DOG is the base that will be sold, increased according to actual price. */

    uint256 public fee = 4; /* 4% protocol revenue */
    uint256 public lp_fee = 4; /* 4% LP increase */
    uint256 public dog_save_fee = 25; /* Percentage of dogs that we save from the burn. Increasing the reserve fund. */

    constructor() public 
    {  
        OMNIDEX_USDC_WTLOS  = OMNIDEX_INTERFACE(usdc_pair);
        OMNIDEX_USDOG_WTLOS = OMNIDEX_INTERFACE(usdog_pair);
        OMNIDEX_ROUTER      = OMNIDEX_INTERFACE(omnidex_router_address);
        DOG_CALL            = DOGS_ERC20(dog_token);
        USDOG_CALL          = DOGS_ERC20(usdog_token);
        owner_addr          = msg.sender;
        self_address        = address(this); /* Own address. */
    }

    modifier onlyOwner() {require (msg.sender == owner_addr);_;}

    receive() external payable 
    {
        return;
    }

    /* <----- StableDOG Functions -----> */
    /* <----- StableDOG Functions -----> */
    function stabilize() public onlyOwner returns (bool success)
    {   
        /* 1. Check USDT/WTLOS Price */
        (uint112 usdcwtlos_reserve0, uint112 usdcwtlos_reserve1,) = OMNIDEX_USDC_WTLOS.getReserves();
        /* 2. Check StableDOG/WTLOS Price */
        (uint112 usdogwtlos_reserve0, uint112 usdogwtlos_reserve1,) = OMNIDEX_USDOG_WTLOS.getReserves();
        /* 3. Determine StableDOG price in USD */
        uint256 wtlos_price_in_usdc = 1000000000000000/(usdcwtlos_reserve1/usdcwtlos_reserve0); /* 788 means 0.788 cents for a Telos */
        uint256 usdog_price_in_tlos = 10000*usdogwtlos_reserve1/usdogwtlos_reserve0; /* 456 means 0.456 TLOS for a DOG */
        /* To find out dog dollar price */
        uint256 current_price = wtlos_price_in_usdc*usdog_price_in_tlos/100000; /* 35 means $0.35 */ 

        if (current_price >= 95 && current_price <= 105) 
            revert(); 

        uint256 usdog_sell_before_fee;
        uint256 usdog_sell_after_fee;

        uint256 dog_sell; /* No fees taken when selling dog into usdog */

        if (current_price >= 105) /* $1.05 */
        {   
            if (current_price <= 200) /* At $2.00 or below, we sell up to 1.95x the amount of base stabledog depending on the price */
                usdog_sell_before_fee = (getPercent((current_price-upper_limit),stabilize_base_usdog)+stabilize_base_usdog)*1000000000000000000;
            else /* Price is over $2 */                                                
                usdog_sell_before_fee = stabilize_base_usdog * 4 * 1000000000000000000; /* At above $2.00, we sell 4x the amount of base stabledog. */

                /* Mint the starting usdog */
                USDOG_CALL.mintStableDOG(usdog_sell_before_fee);

                /* Calculate fee, send it to the fee account, substract it from the amount */
                uint256 fee_to_send = getPercent(fee, usdog_sell_before_fee);
                USDOG_CALL.transfer(fee_address, fee_to_send);

                /* LP Fees */
                uint256 lp_fee_to_add = getPercent(lp_fee, usdog_sell_before_fee);
                usdog_sell_after_fee = USDOG_CALL.balanceOf(self_address) - lp_fee_to_add;

                /* Figure out how much DOG we actually received from selling. Must not confuse it with the reserve fund. */
                uint256 prev_balance = DOG_CALL.balanceOf(self_address);
                swapStableDOGforDOG(usdog_sell_after_fee);
                uint256 after_balance = DOG_CALL.balanceOf(self_address);

                /* At this point, we should have just a little bit of USDOG left in the contract balances. Sell half to WTLOS. */
                uint256 usdog_remaining = USDOG_CALL.balanceOf(self_address);
                swapStableDogForWTLOS(getPercent(50, usdog_remaining));
                /* Transfer the remaining USDOG to the LP fee address. */
                USDOG_CALL.transfer(lp_fee_address, USDOG_CALL.balanceOf(self_address));
                /* Transfer the WTLOS to the LP fee address. */
                address payable to_fee = address(uint160(lp_fee_address));
                to_fee.transfer(address(this).balance);

                /* Burn the DOG that we got by selling the USDOG for this round. */
                uint256 to_burn = after_balance - prev_balance; /* Should use safe math here. */
                uint256 dog_to_save = getPercent(dog_save_fee, to_burn); /* Percentage of dogs we save. */
                to_burn = to_burn - dog_to_save; /* Save some dogs from the inferno! */

                DOG_CALL.burn(to_burn);
        }

        if (current_price <= 95)
        {    /* We will have no fees taken if price is below $0.95. */
            if (current_price >= 50)
                dog_sell = (getPercent((lower_limit-current_price+10),stabilize_base_usdog)+stabilize_base_dog) * 1000000000000000000;
            else
                dog_sell = stabilize_base_dog * 4 * 1000000000000000000; /* At below $0.5, we sell 4x the amount of base dog. */

            /* Sell the DOG into Stabledog and burn it */
            swapDOGforStableDOG(dog_sell);
            USDOG_CALL.burn(USDOG_CALL.balanceOf(self_address));
        }
        return true;
    }

    function swapStableDOGforDOG(uint256 amount) private 
    {
        address[] memory path = new address[](3);
        path[0] = usdog_token;                 /* StableDOG Contract Address. */
        path[1] = OMNIDEX_ROUTER.WETH();       /* Gets turned into WTLOS first */
        path[2] = dog_token;                   /* And then into DOG */
        /* Approve router. */
        USDOG_CALL.approve(omnidex_router_address, amount);

        OMNIDEX_ROUTER.swapExactTokensForTokens(amount,0,path,address(this),block.timestamp);
    }

    function swapDOGforStableDOG(uint256 amount) private 
    {
        address[] memory path = new address[](3);
        path[0] = dog_token;   
        path[1] = OMNIDEX_ROUTER.WETH();
        path[2] = usdog_token;            
        /* Approve router. */
        DOG_CALL.approve(omnidex_router_address, amount);

        OMNIDEX_ROUTER.swapExactTokensForTokens(amount,0,path,address(this),block.timestamp);
    }

    function swapStableDogForWTLOS(uint256 amount) private 
    {
        address[] memory path = new address[](2);
        path[0] = usdog_token;
        path[1] = OMNIDEX_ROUTER.WETH(); 
        /* Approve router. */
        USDOG_CALL.approve(omnidex_router_address, amount);

        OMNIDEX_ROUTER.swapExactTokensForETH(amount,0,path,address(this),block.timestamp);
    }

    function withdrawAll() public onlyOwner
    {   /* Withdraw TLOS */
        address payable owner = address(uint160(msg.sender));
        owner.transfer(address(this).balance);
        /* Withdraw DOG */
        DOG_CALL.transfer(msg.sender, DOG_CALL.balanceOf(self_address));
        /* Withdraw Stabledog */
        USDOG_CALL.transfer(msg.sender, USDOG_CALL.balanceOf(self_address));
    }

    /* <----- Setter Functions -----> */
    /* <----- Setter Functions -----> */
    function D_SET_OMNIDEX_USDOG_WTLOS     (address new_address) public onlyOwner { OMNIDEX_USDOG_WTLOS   = OMNIDEX_INTERFACE(new_address);                    }
    function D_SET_OMNIDEX_USDC_WTLOS      (address new_address) public onlyOwner { OMNIDEX_USDC_WTLOS    = OMNIDEX_INTERFACE(new_address);                    }
    function D_SET_OMNIDEX_ROUTER          (address new_address) public onlyOwner { OMNIDEX_ROUTER        = OMNIDEX_INTERFACE(new_address);                    }
    function D_SET_dog_token               (address new_address) public onlyOwner { dog_token             = new_address; DOG_CALL = DOGS_ERC20(dog_token);     }
    function D_SET_usdog_token             (address new_address) public onlyOwner { usdog_token           = new_address; USDOG_CALL = DOGS_ERC20(usdog_token); }
    function D_SET_fee_address             (address new_address) public onlyOwner { fee_address           = new_address;                                       }
    function D_SET_lp_fee_address          (address new_address) public onlyOwner { lp_fee_address        = new_address;                                       }
    function D_SET_owner_addr              (address new_address) public onlyOwner { owner_addr            = new_address;                                       }
    function D_SET_stabilize_base_usdog    (uint256 new_value)   public onlyOwner { stabilize_base_usdog  = new_value;                                         }
    function D_SET_stabilize_base_dog      (uint256 new_value)   public onlyOwner { stabilize_base_dog    = new_value;                                         }
    function D_SET_upper_limit             (uint256 new_limit)   public onlyOwner { upper_limit           = new_limit;                                         }
    function D_SET_lower_limit             (uint256 new_limit)   public onlyOwner { lower_limit           = new_limit;                                         }
    function D_SET_fee                     (uint256 new_fee)     public onlyOwner { fee                   = new_fee;                                           }
    function D_SET_lp_fee                  (uint256 new_fee)     public onlyOwner { lp_fee                = new_fee;                                           }
    function D_SET_dog_save_fee            (uint256 new_fee)     public onlyOwner { dog_save_fee          = new_fee;                                           }
}
