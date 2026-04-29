pragma solidity 0.8.25;

contract FailingReceiver {
    fallback() external payable {
        revert("FailingReceiver: fallback reverted");
    }
}
