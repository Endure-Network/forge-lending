pragma solidity 0.8.25;

import "../../venus-staging/Comptroller/Diamond/facets/MarketFacet.sol";
import "../../venus-staging/Comptroller/Diamond/facets/PolicyFacet.sol";
import "../../venus-staging/Comptroller/Diamond/facets/RewardFacet.sol";
import "../../venus-staging/Comptroller/Diamond/facets/SetterFacet.sol";
import "../../venus-staging/Comptroller/Diamond/facets/FlashLoanFacet.sol";
import "../../venus-staging/Comptroller/Unitroller.sol";

// This contract contains all methods of Comptroller implementation in different facets at one place for testing purpose
// This contract does not have diamond functionality(i.e delegate call to facets methods)
contract ComptrollerMock is MarketFacet, PolicyFacet, RewardFacet, SetterFacet, FlashLoanFacet {
    constructor() {
        admin = msg.sender;
    }

    function _become(Unitroller unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can");
        require(unitroller._acceptImplementation() == 0, "not authorized");
    }

    function _setComptrollerLens(ComptrollerLensInterface comptrollerLens_) external override returns (uint) {
        ensureAdmin();
        ensureNonzeroAddress(address(comptrollerLens_));
        address oldComptrollerLens = address(comptrollerLens);
        comptrollerLens = comptrollerLens_;
        emit NewComptrollerLens(oldComptrollerLens, address(comptrollerLens));

        return uint(Error.NO_ERROR);
    }
}
