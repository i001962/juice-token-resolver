//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {console} from "../lib/forge-std/src/console.sol";
import {IJBTokenUriResolver} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBTokenUriResolver.sol";
import {IJBToken, IJBTokenStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBTokenStore.sol";
import {JBFundingCycle} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {JBTokens} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import {JBCurrencies} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBCurrencies.sol";
import {IJBController, IJBDirectory, IJBFundingCycleStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBPayoutRedemptionPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal.sol";
import {IJBSingleTokenPaymentTerminalStore, IJBSingleTokenPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore.sol";
import {JBPayoutRedemptionPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBPayoutRedemptionPaymentTerminal.sol";
import {IJBProjects} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBProjects.sol";
import {IJBProjectHandles} from "@jbx-protocol/project-handles/contracts/interfaces/IJBProjectHandles.sol"; // Needs updating when NPM is renamed to /juice-project-handles
import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";
import {IJBTiered721DelegateStore} from "@jbx-protocol/juice-721-delegate/contracts/interfaces/IJBTiered721DelegateStore.sol";
import {JBUriOperations} from "./Libraries/JBUriOperations.sol";
import {Theme} from "./Structs/Theme.sol";
//import {JB721Tier} from "@jbx-protocol/juice-721-delegate/contracts/structs/JB721Tier.sol";
import {JB721TierDefifa} from "./Structs/JB721TierDefifa.sol";
import {Base64} from "base64-sol/base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Font, ITypeface} from "typeface/interfaces/ITypeface.sol";

// // ENS RESOLUTION
interface IReverseRegistrar {
    function node(address) external view returns (bytes32);
}

interface IResolver {
    function name(bytes32) external view returns (string memory);
}

contract StringSlicer {
    // This function is in a separate contract so that TokenUriResolver can pass it a string memory and we can still use Array Slices (which only work on calldata)
    function slice(
        string calldata _str,
        uint256 _start,
        uint256 _end
    ) external pure returns (string memory) {
        return string(bytes(_str)[_start:_end]);
    }
}

contract DefaultTokenUriResolver is IJBTokenUriResolver, JBOperatable {
    using Strings for uint256;
    // for testing
    struct TestMintedTiers {
        uint256 id;
        uint256 remainingQuantity;
        uint256 initialQuantity;
    }
    TestMintedTiers[] public myTestMintedTiers = [
        TestMintedTiers({id: 1, remainingQuantity: 80, initialQuantity: 100}),
        TestMintedTiers({id: 2, remainingQuantity: 95, initialQuantity: 100}),
        TestMintedTiers({id: 3, remainingQuantity: 87, initialQuantity: 100}),
        TestMintedTiers({id: 4, remainingQuantity: 92, initialQuantity: 100}),
        TestMintedTiers({id: 5, remainingQuantity: 93, initialQuantity: 100}),
        TestMintedTiers({id: 6, remainingQuantity: 99, initialQuantity: 100}),
        TestMintedTiers({id: 7, remainingQuantity: 98, initialQuantity: 100}),
        TestMintedTiers({id: 8, remainingQuantity: 95, initialQuantity: 100}),
        TestMintedTiers({id: 9, remainingQuantity: 80, initialQuantity: 100}),
        TestMintedTiers({id: 10, remainingQuantity: 95, initialQuantity: 100}),
        TestMintedTiers({id: 11, remainingQuantity: 87, initialQuantity: 100}),
        TestMintedTiers({id: 12, remainingQuantity: 92, initialQuantity: 100}),
        TestMintedTiers({id: 13, remainingQuantity: 93, initialQuantity: 100}),
        TestMintedTiers({id: 14, remainingQuantity: 99, initialQuantity: 100}),
        TestMintedTiers({id: 15, remainingQuantity: 98, initialQuantity: 100}),
        TestMintedTiers({id: 16, remainingQuantity: 95, initialQuantity: 100})
    ];
    
    StringSlicer slice = new StringSlicer();
    
    event Log(string message);
    event ThemeSet(uint256 projectId, Theme theme);
    error InvalidTheme();

    IJBFundingCycleStore public fundingCycleStore;
    IJBProjects public projects;
    IJBDirectory public directory;
    IJBTokenStore public tokenStore;
    IJBSingleTokenPaymentTerminalStore public singleTokenPaymentTerminalStore;
    IJBController public controller;
    IJBProjectHandles public projectHandles;
    ITypeface public capsulesTypeface; // Capsules typeface
    // IReverseRegistrar public reverseRegistrar; // ENS
    // IResolver public resolver; // ENS
    IJBTiered721DelegateStore public tiered721DelegateStore;
    mapping(uint256 => Theme) public themes;

    // ?? Should this be in constructor? how to get this address? Deploy script??
    address internal _NFT_ADDRESS = 0x600f3b83cD74175B9f10867B8218855d755c8923;

    constructor(
        IJBOperatorStore _operatorStore,
        IJBDirectory _directory,
        IJBProjectHandles _projectHandles,
        ITypeface _capsulesTypeface,
        IJBTiered721DelegateStore _tiered721DelegateStore
    )
        // IReverseRegistrar _reverseRegistrar,
        // IResolver _resolver
        JBOperatable(_operatorStore)
    {
        directory = _directory;
        projects = directory.projects();
        fundingCycleStore = directory.fundingCycleStore();
        controller = IJBController(directory.controllerOf(1));
        tokenStore = controller.tokenStore();
        singleTokenPaymentTerminalStore = IJBSingleTokenPaymentTerminalStore(
            IJBPayoutRedemptionPaymentTerminal(
                address(
                    IJBPaymentTerminal(
                        directory.primaryTerminalOf(1, JBTokens.ETH)
                    )
                )
            ).store()
        );
        projectHandles = _projectHandles;
        capsulesTypeface = _capsulesTypeface;
        tiered721DelegateStore = _tiered721DelegateStore;
        // reverseRegistrar = _reverseRegistrar;
        // resolver = _resolver;
        themes[0] = Theme({
            projectId: 0,
            textColor: "#333333", //"#FF9213",
            bgColor: "#44190F",
            bgColorDark: "#3A0F0C"
        });
    }

    // @notice Gets the Base64 encoded Capsules-500.otf typeface
    /// @return fontSource The Base64 encoded font file
    function getFontSource() internal view returns (bytes memory fontSource) {
        return
            ITypeface(capsulesTypeface).sourceOf(
                Font({weight: 700, style: "normal"})
            ); // Capsules font source
    }

    /// @notice Transform strings to target length by abbreviation or left padding with spaces.
    /// @dev Shortens long strings to 13 characters including an ellipsis and adds left padding spaces to short strings. Allows variable target length to account for strings that have unicode characters that are longer than 1 byte but only take up 1 character space.
    /// @param left True adds padding to the left of the passed string, and false adds padding to the right
    /// @param str The string to transform
    /// @param targetLength The length of the string to return
    /// @return string The transformed string
    function pad(
        bool left,
        string memory str,
        uint256 targetLength
    ) internal view returns (string memory) {
        uint256 length = bytes(str).length;
        if (left) {
            // Left pad
            if (length > targetLength) {
                // Shorten strings strings longer than target length
                str = string.concat(
                    slice.slice(str, 0, targetLength - 1),
                    unicode"…"
                ); // Shortens to 1 character less than target length and adds an ellipsis unicode character
            } else if (length == targetLength) {
                return str;
            } else {
                // Pad strings shorter than target length
                string memory padding;
                for (uint256 i = 0; i < targetLength - length; i++) {
                    padding = string.concat(padding, " ");
                }
                str = string.concat(padding, str);
            }
            return str;
        } else {
            // Right pad
            if (length > targetLength) {
                str = string.concat(
                    slice.slice(str, 0, targetLength - 1),
                    unicode"…"
                ); // Shortens to 1 character less than target length and adds an ellipsis unicode character
            } else if (length == targetLength) {
                return str;
            } else {
                string memory padding;
                for (uint256 i = 0; i < targetLength - length; i++) {
                    padding = string.concat(padding, " ");
                }
                str = string.concat(str, padding);
            }
            return str;
        }
    }

    function getProjectName(uint256 _projectId)
        internal
        view
        returns (string memory projectName)
    {
        // Project Handle
        string memory _projectName;
        // If handle is set
        if (
            keccak256(abi.encode(projectHandles.handleOf(_projectId))) !=
            keccak256(abi.encode(string("")))
        ) {
            // Set projectName to handle
            _projectName = string.concat(
                projectHandles.handleOf(_projectId),
                ".net"
            );
        } else {
            // Set projectName to name to 'Project #projectId'
            _projectName = string.concat("Project #", _projectId.toString());
        }
        // Abbreviate handle to 27 chars if longer
        if (bytes(_projectName).length > 26) {
            _projectName = string.concat(
                slice.slice(_projectName, 0, 26),
                unicode"…"
            );
        }
        return _projectName;
    }

    function getOverflowString(uint256 _projectId)
        internal
        view
        returns (string memory overflowString)
    {
        uint256 overflow = singleTokenPaymentTerminalStore
            .currentTotalOverflowOf(_projectId, 0, 1); // Project's overflow to 0 decimals
        return string.concat(unicode"Ξ", overflow.toString());
    }

    function getOverflowRow(string memory overflowString)
        internal
        view
        returns (string memory overflowRow)
    {
        string memory paddedOverflowLeft = string.concat(
            pad(true, overflowString, 14),
            "  "
        ); // Length of 14 because Ξ counts as 2 characters, but has character width of 1
        string memory paddedOverflowRight = string.concat(
            pad(false, unicode"  ovᴇʀꜰʟow    ", 21)
        ); //  E = 3, ʀ = 2, ꜰ = 3, ʟ = 2
        return string.concat(paddedOverflowRight, paddedOverflowLeft);
    }

    function getRightPaddedFC(JBFundingCycle memory _fundingCycle)
        internal
        view
        returns (string memory rightPaddedFCString)
    {
        uint256 currentFundingCycleId = _fundingCycle.number; // Project's current funding cycle id
        string memory fundingCycleIdString = currentFundingCycleId.toString();
        return string.concat(unicode"Phase ", fundingCycleIdString);
    }

    function getLeftPaddedTimeLeft(JBFundingCycle memory _fundingCycle)
        internal
        view
        returns (string memory leftPaddedTimeLeftString)
    {
        // Time Left
        uint256 start = _fundingCycle.start; // Project's funding cycle start time
        uint256 duration = _fundingCycle.duration; // Project's current funding cycle duration
        uint256 timeLeft;
        string memory paddedTimeLeft;
        string memory countString;
        if (duration == 0) {
            paddedTimeLeft = string.concat("Not set"); // If the funding cycle has no duration, show infinite duration
        } else {
            timeLeft = start + duration - block.timestamp; // Project's current funding cycle time left
            if (timeLeft > 2 days) {
                countString = (timeLeft / 1 days).toString();
                paddedTimeLeft = string.concat(
                            " ",
                            unicode"",
                            " ",
                            countString,
                            " Days");
            } else if (timeLeft > 2 hours) {
                countString = (timeLeft / 1 hours).toString(); // 12 bytes || 8 visual + countString
                paddedTimeLeft = string.concat(
                            unicode"",
                            " ",
                            countString,
                            unicode" ʜouʀs"
                        );
            } else if (timeLeft > 2 minutes) {
                countString = (timeLeft / 1 minutes).toString();
                paddedTimeLeft = string.concat(
                    pad(
                        true,
                        string.concat(
                            unicode"",
                            " ",
                            countString,
                            unicode" ᴍɪɴuᴛᴇs"
                        ),
                        23
                    ),
                    "  "
                );
            } else {
                countString = (timeLeft / 1 seconds).toString();
                paddedTimeLeft = string.concat(
                    pad(
                        true,
                        string.concat(
                            unicode"",
                            " ",
                            countString,
                            unicode" sᴇcoɴᴅs"
                        ),
                        20
                    ),
                    "  "
                );
            }
        }
        return paddedTimeLeft;
    }

    function getFCTimeLeftRow(JBFundingCycle memory fundingCycle)
        internal
        view
        returns (string memory fCTimeLeftRow)
    {
        return
            string.concat(
                getRightPaddedFC(fundingCycle),
                getLeftPaddedTimeLeft(fundingCycle)
            );
    }

    function getBalanceRow(
        IJBPaymentTerminal primaryEthPaymentTerminal,
        uint256 _projectId
    ) internal view returns (string memory balanceRow) {
        // Balance
        uint256 balance = singleTokenPaymentTerminalStore.balanceOf(
            IJBSingleTokenPaymentTerminal(address(primaryEthPaymentTerminal)),
            _projectId
        ) / 10**18; // Project's ETH balance //TODO Try/catch
        string memory paddedBalanceLeft = string.concat(unicode"Ξ", balance.toString());
        // Project's ETH balance as a string
        string memory paddedBalanceRight = "Prize pool:   ";
        return string.concat(paddedBalanceRight, paddedBalanceLeft);
    }

    function getDistributionLimitRow(
        IJBPaymentTerminal primaryEthPaymentTerminal,
        uint256 _projectId
    ) internal view returns (string memory distributionLimitRow) {
        // Distribution Limit
        uint256 latestConfiguration = fundingCycleStore.latestConfigurationOf(
            _projectId
        ); // Get project's current FC  configuration
        string memory distributionLimitCurrency;
        (
            uint256 distributionLimitPreprocessed,
            uint256 distributionLimitCurrencyPreprocessed
        ) = controller.distributionLimitOf(
                _projectId,
                latestConfiguration,
                primaryEthPaymentTerminal,
                JBTokens.ETH
            ); // Project's distribution limit
        if (distributionLimitCurrencyPreprocessed == 1) {
            distributionLimitCurrency = unicode"Ξ";
        } else {
            distributionLimitCurrency = "$";
        }
        string memory distributionLimit = string.concat(
            distributionLimitCurrency,
            (distributionLimitPreprocessed / 10**18).toString()
        ); // Project's distribution limit
        string memory paddedDistributionLimitLeft = string.concat(
            pad(
                true,
                distributionLimit,
                12 + bytes(distributionLimitCurrency).length
            ),
            "  "
        );
        string memory paddedDistributionLimitRight = string.concat(
            pad(false, unicode"  ᴅɪsᴛʀ. ʟɪᴍɪᴛ", 28)
        ); // ᴅ = 3, ɪ = 2, T = 3, ʀ = 2, ʟ = 2, ɪ = 2, ᴍ = 3, ɪ = 2, T = 3
        return
            string.concat(
                paddedDistributionLimitRight,
                paddedDistributionLimitLeft
            );
    }

    function getTotalSupplyRow(uint256 _projectId)
        internal
        view
        returns (string memory totalSupplyRow)
    {
        // Supply
        uint256 totalSupply = tokenStore.totalSupplyOf(_projectId) / 10**18; // Project's token total supply
        string memory paddedTotalSupplyLeft = string.concat(
            pad(true, totalSupply.toString(), 13),
            "  "
        ); // Project's token total supply as a string
        string memory paddedTotalSupplyRight = pad(
            false,
            unicode"  ᴛoᴛᴀʟ suᴘᴘʟʏ",
            28
        );
        return string.concat(paddedTotalSupplyRight, paddedTotalSupplyLeft);
    }
    function getTotalMinted(address _nft)
        internal
        view
        returns (string memory totalMint)
    {
        // Minted
        uint256 totalMinted = tiered721DelegateStore.totalSupply(_nft); // Project's _nft address
        string memory paddedTotalMintedLeft = string.concat(
            pad(true, totalMinted.toString(), 13),
            "  "
        ); // Project's token total mint as a string
        string memory paddedTotalMintedRight = "Total minted: ";
        return string.concat(paddedTotalMintedRight,  totalMinted.toString());
    }
    
    /* function getTiersMinted(address _nft)
        internal
        view
        returns (string memory tiers)
    {
        // Minted  
        JB721TierDefifa[] memory totalTiersMinted = tiered721DelegateStore.tiers(_nft,0,0,32);
        string memory paddedTotalMintedLeft =
            totalTiersMinted[0].id.toString(); // Project's token total mint as a string
        console.log(paddedTotalMintedLeft);
        string memory paddedTotalMintedRight = "Total minted: ";
        return string.concat(paddedTotalMintedRight,  paddedTotalMintedLeft);
    } */
    // function setTokenUriResolverForProject(uint256 _projectId, IJBTokenUriResolver _resolver) external requirePermission(projects.ownerOf(_projectId), _projectId, JBUriOperations.SET_TOKEN_URI) {
    //     if(_resolver == IJBTokenUriResolver(address(0))){
    //         delete tokenUriResolvers[_projectId];
    //     } else {
    //         tokenUriResolvers[_projectId]= _resolver;
    //     }
    // }
    function getMintedTiersTest(address _nft)
        internal
        view
        returns (string memory mintedChart)
    {
        // Tiers and Minted  
        // JB721TierDefifa[] memory totalTiersMinted = tiered721DelegateStore.tiers(_nft,0,0,32);
        string memory paddedTotalMintedRight = "ID:";
        string[] memory parts = new string[](11);
        string memory textHolder;
        uint256 yValue = 40;
        uint256 xValue = 65;
        
        //string memory textHolder;
        for (uint256 i = 0; i < myTestMintedTiers.length; i++) {
            yValue = yValue + 20;
            uint256 yBarValue = yValue - 7;
            uint256 amtMinted = myTestMintedTiers[i].initialQuantity - myTestMintedTiers[i].remainingQuantity;
            string memory amtMintedString = amtMinted.toString();
            parts[0] = string('<text x="15" y="');
            parts[1] = string(yValue.toString());
            parts[2] = string('" style="font-size: 1rem;">');
            parts[3] = string.concat(myTestMintedTiers[i].id.toString(), "- ", amtMintedString);
            parts[4] = string('</text>');
            //parts[5] = string('<line x1="20" y1="380" x2="100" y2="380" style="stroke:#ED7149;stroke-width:15" />');
            parts[5] = string('<line x1="65" y1="');
            parts[6] = string(yBarValue.toString());
            parts[7] = string('" x2="');
            uint256 barLength = amtMinted + xValue;
            string memory barLengthString = barLength.toString();
            parts[8] = string(barLengthString);
            parts[9] = string('" y2="');
            parts[10] = string.concat(parts[6],'" style="stroke:#FAC15C;stroke-width:15" />');         
            textHolder = string.concat(textHolder,parts[0], parts[1], parts[2],parts[3],parts[4], parts[5], parts[6], parts[7], parts[8], parts[9], parts[10]);
        }
        return string.concat(textHolder);
    }


    // TODO write tests
    function setTheme(Theme memory _theme)
        external
        requirePermission(
            projects.ownerOf(_theme.projectId),
            _theme.projectId,
            JBUriOperations.SET_TOKEN_URI
        )
    {
        if (_theme.projectId == 0) revert InvalidTheme(); // Cannot set theme for project 0
        themes[_theme.projectId] = _theme;
        emit ThemeSet(_theme.projectId, _theme);
    }

    function getUri(uint256 _projectId)
        external
        view
        override
        returns (string memory tokenUri)
    {
        // Load theme
        Theme memory theme;
        if (themes[_projectId].projectId == 0) {
            theme = themes[0];
        } else {
            theme = themes[_projectId];
        }

        // Funding Cycle
        // FC#
        JBFundingCycle memory fundingCycle = fundingCycleStore.currentOf(
            _projectId
        ); // Project's current funding cycle

        // Get Primary Terminal
        IJBPaymentTerminal primaryEthPaymentTerminal = directory
            .primaryTerminalOf(_projectId, JBTokens.ETH); // Project's primary ETH payment terminal

        // JBToken ERC20
        IJBToken jbToken = tokenStore.tokenOf(_projectId);
        bool tokenIssued;
        string memory jbTokenString;
        string memory tokenIssuedString;
        address jbTokenAddress = address(jbToken);
        if (jbTokenAddress == address(0)) {
            tokenIssued = false;
        } else {
            tokenIssued = true;
            jbTokenString = toAsciiString(jbTokenAddress);
        }
        if (tokenIssued) {
            tokenIssuedString = "True";
        } else {
            tokenIssuedString = "False";
        }

        // Owner
        address owner = projects.ownerOf(_projectId); // Project's owner
        string memory ownerName;
        // TODO Use AddressToENSString library (wip) to resolve ENS address onchain
        // try resolver.name(reverseRegistrar.node(owner)) returns (string memory _ownerName) {
        //     ownerName = _ownerName;
        // } catch {
        ownerName = string.concat(
            "0x",
            slice.slice(toAsciiString(owner), 0, 4),
            unicode"…",
            slice.slice(toAsciiString(owner), 36, 40)
        ); // Abbreviate owner address
        // }

        string memory projectOwnerPaddedRight = pad(
            false,
            unicode"  ᴘʀoᴊᴇcᴛ owɴᴇʀ",
            28
        );

        string memory projectName = getProjectName(_projectId);

        string[] memory parts = new string[](4);
        parts[0] = string("data:application/json;base64,");
        parts[1] = string(
            abi.encodePacked(
                '{"name":"',
                projectName,
                '", "description":"',
                projectName,
                " is a project on the Juicebox Protocol. It has an overflow of ",
                getOverflowString(_projectId),
                ' ETH.", "image":"data:image/svg+xml;base64,'
            )
        );
        // Each line (row) of the SVG is 30 monospaced characters long
        // The first half of each line (15 chars) is the title
        // The second half of each line (15 chars) is the value
        // The first and last characters on the line are two spaces
        // The first line (head) is an exception.
        parts[2] = Base64.encode(
            abi.encodePacked(
                '<svg width="500" height="600" viewBox="0 0 500 500" xmlns="http://www.w3.org/2000/svg"><style>@font-face{font-family:"Capsules-500";src:url(data:font/truetype;charset=utf-8;base64,',
                getFontSource(), // import Capsules typeface
                ');format("opentype");}a,a:visited,a:hover{fill:inherit;text-decoration:none;}text{font-size:16px;fill:',
                theme.textColor,
                ';font-family:"Capsules-500",monospace;font-weight:500;white-space:pre;}#head text{fill:',
                theme.bgColor,
                ';}</style><g clip-path="url(#clip0)"><path d="M500 0H0V500H500V0Z" fill="url(#paint1)"/><rect width="500" height="22" fill="',
                theme.textColor,
                '"/><g id="head">',
                                // Hoops
                /* <svg version="1.1" id="Layer_1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px"
	                viewBox="0 0 512 512" style="enable-background:new 0 0 512 512;" xml:space="preserve"> */
                '<rect x="7.875" y="25.665" style="fill:#ED7149;" width="496.246" height="318.319"/>',
                '<rect x="95.915" y="95.851" style="fill:#F18D6D;" width="320.167" height="192.102"/>',
                '<rect x="143.94" y="271.941" style="fill:#F9B233;" width="224.116" height="32.017"/>',
                '<rect x="143.94" y="271.941" style="fill:#FAC15C;" width="128.065" height="32.017"/>',
                '<g>',
                    '<path style="fill:#1D1D1B;" d="M375.931,311.834H136.068v-47.765h239.863L375.931,311.834L375.931,311.834z M151.818,296.084 h208.364v-16.266H151.818V296.084z"/>',
                    '<polygon style="fill:#1D1D1B;" points="512,351.854 368.057,351.854 368.057,336.105 496.25,336.105 496.25,31.693 15.75,31.693 15.75,336.105 143.943,336.105 143.943,351.854 0,351.854 0,15.943 512,15.943"/>',
                    '<polygon style="fill:#1D1D1B;" points="423.956,295.826 384.065,295.826 384.065,280.076 408.206,280.076 408.206,103.729 103.794,103.729 103.794,280.076 127.935,280.076 127.935,295.826 88.044,295.826 88.044,87.979 423.956,87.979 "/>',
                    '<path style="fill:#1D1D1B;" d="M344.174,319.968v16.137h-16.267v-16.137h-15.75v16.137h-16.266v-16.137h-15.75v16.137h-16.266',
                        'v-16.137h-15.75v16.137h-16.267v-16.137h-15.75v16.137h-16.267v-16.137h-15.75v16.137h-16.267v-16.137h-15.75v176.089h15.75',
                        'v-16.138h16.267v16.138h15.75v-16.138h16.267v16.138h15.75v-16.138h16.267v16.138h15.75v-16.138h16.266v16.138h15.75v-16.138',
                        'h16.267v16.138h15.75v-16.138h16.267v16.138h15.75V319.968H344.174z M184.093,464.169h-16.267v-16.267h16.267V464.169z',
                        'M184.093,432.153h-16.267v-16.266h16.267V432.153z M184.093,400.137h-16.267V383.87h16.267V400.137z M184.093,368.12h-16.267',
                        'v-16.266h16.267V368.12z M216.11,464.169h-16.267v-16.267h16.267V464.169z M216.11,432.153h-16.267v-16.266h16.267V432.153z',
                        'M216.11,400.137h-16.267V383.87h16.267V400.137z M216.11,368.12h-16.267v-16.266h16.267V368.12z M248.125,464.169h-16.267v-16.267',
                        'h16.267V464.169z M248.125,432.153h-16.267v-16.266h16.267V432.153z M248.125,400.137h-16.267V383.87h16.267V400.137z',
                        'M248.125,368.12h-16.267v-16.266h16.267V368.12z M280.142,464.169h-16.266v-16.267h16.266V464.169z M280.142,432.153h-16.266',
                        'v-16.266h16.266V432.153z M280.142,400.137h-16.266V383.87h16.266V400.137z M280.142,368.12h-16.266v-16.266h16.266V368.12z',
                        'M312.158,464.169h-16.266v-16.267h16.267v16.267H312.158z M312.158,432.153h-16.266v-16.266h16.267v16.266H312.158z',
                        'M312.158,400.137h-16.266V383.87h16.267v16.267H312.158z M312.158,368.12h-16.266v-16.266h16.267v16.266H312.158z',
                        'M344.174,464.169h-16.267v-16.267h16.267V464.169z M344.174,432.153h-16.267v-16.266h16.267V432.153z M344.174,400.137h-16.267',
                        'V383.87h16.267V400.137z M344.174,368.12h-16.267v-16.266h16.267V368.12z"/>',
                '</g>',
                //end hoops
                '<a href="https://juicebox.money/v2/p/',
                _projectId.toString(),
                '">', // Line 0: Head
                '<text x="42" y="45">',
                projectName,
                '</text></a>',
                '<a href="https://juicebox.money"><text x="420" y="45">',
                unicode"",
                "</text></a></g>",
                // Line 1: FC + Time left
                '<g><text x="105" y="210" style="font-size: 1.75rem;">',
                getFCTimeLeftRow(fundingCycle),
                "</text>",
                '<text x="105" y="130" style="font-size: 1.75rem;">',
                getBalanceRow(primaryEthPaymentTerminal, _projectId),
                "</text>",
                '<text x="105" y="170" style="font-size: 1.75rem;">',
                getTotalMinted(_NFT_ADDRESS),
                "</text>",
                //'<text x="15" y="380" style="font-size: 1rem;">',
                //getTiersMinted(_NFT_ADDRESS),
                getMintedTiersTest(_NFT_ADDRESS),
                //"</text>",
                '</g></g><defs><filter id="filter1" x="-3.36" y="26.04" width="294.539" height="226.12" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB"><feFlood flood-opacity="0" result="BackgroundImageFix"/><feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0" result="hardAlpha"/><feOffset/><feGaussianBlur stdDeviation="2"/><feComposite in2="hardAlpha" operator="out"/> <feColorMatrix type="matrix" values="0 0 0 0 1 0 0 0 0 0.572549 0 0 0 0 0.0745098 0 0 0 0.68 0"/><feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_150_56"/><feBlend mode="normal" in="SourceGraphic" in2="effect1_dropShadow_150_56" result="shape"/></filter><linearGradient id="paint0" x1="0" y1="202" x2="500" y2="202" gradientUnits="userSpaceOnUse"><stop stop-color="',
                theme.bgColorDark,
                '"/><stop offset="0.119792" stop-color="',
                theme.bgColor,
                '"/><stop offset="0.848958" stop-color="',
                theme.bgColor,
                '"/><stop offset="1" stop-color="',
                theme.bgColorDark,
                '"/></linearGradient><clipPath id="clip0"><rect width="500" height="600" /></clipPath></defs></svg>'
            )
        );
        parts[3] = string('"}');
        string memory uri = string.concat(
            parts[0],
            Base64.encode(abi.encodePacked(parts[1], parts[2], parts[3]))
        );
        return uri;
    }

    // borrowed from https://ethereum.stackexchange.com/questions/8346/convert-address-to-string
    function toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(x)) / (2**(8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(s);
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
