import hashlib, os, sys
root=sys.argv[1]
def i(name): return hashlib.md5(name.encode()).hexdigest()[:24].upper()
P=i('project');MAIN=i('maingroup');PRODG=i('products');SYNC=i('syncgroup');APP=i('appref')
TGT=i('target');SRC=i('sources');FW=i('frameworks');RES=i('resources');BF=i('bf-gamecore')
LPKG=i('localpkg');UT=i('uitarget');UTREF=i('uitestref');UTSYNC=i('uisync');UTSRC=i('uisources');UTFW=i('uiframeworks');UTRES=i('uiresources');UTDEP=i('uidep');UTPROXY=i('uiproxy');UTCL=i('ui-cl');UTD=i('ui-debug');UTR=i('ui-release');DEP=i('dep-gamecore');PCL=i('proj-cl');TCL=i('tgt-cl')
PD=i('proj-debug');PR=i('proj-release');TD=i('tgt-debug');TR=i('tgt-release')
common_proj='''				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_NO_COMMON_BLOCKS = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 6.0;
'''
proj_debug=common_proj+'''				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
'''
proj_release=common_proj+'''				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
'''
ui_settings='''				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = X6LZQ3FS36;
				GENERATE_INFOPLIST_FILE = YES;
				MARKETING_VERSION = 0.11.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.phoronomicstudios.neongetaway.uitests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = NO;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
				TEST_TARGET_NAME = NeonGetaway;
'''
tgt='''				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = X6LZQ3FS36;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Config/Info.plist;
				CODE_SIGN_ENTITLEMENTS = Config/NeonGetaway.entitlements;
				INFOPLIST_KEY_CFBundleDisplayName = "Neon Getaway";
				INFOPLIST_KEY_CADisableMinimumFrameDurationOnPhone = YES;
				INFOPLIST_KEY_GCSupportsControllerUserInteraction = YES;
				INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "Neon Getaway saves pictures you take in photo mode.";
				INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.racing-games";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UIRequiresFullScreen = YES;
				INFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleLightContent;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 0.11.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.phoronomicstudios.neongetaway;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = 1;
'''
s=f'''// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{BF} /* GameCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {DEP} /* GameCore */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{APP} /* NeonGetaway.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = NeonGetaway.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{UTREF} /* NeonGetawayUITests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = NeonGetawayUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXContainerItemProxy section */
		{UTPROXY} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {P} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {TGT};
			remoteInfo = NeonGetaway;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{SYNC} /* NeonGetaway */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = NeonGetaway;
			sourceTree = "<group>";
		}};
		{UTSYNC} /* NeonGetawayUITests */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = NeonGetawayUITests;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{FW} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{BF} /* GameCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{UTFW} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{MAIN} = {{
			isa = PBXGroup;
			children = (
				{SYNC} /* NeonGetaway */,
				{UTSYNC} /* NeonGetawayUITests */,
				{PRODG} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{PRODG} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{APP} /* NeonGetaway.app */,
				{UTREF} /* NeonGetawayUITests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{TGT} /* NeonGetaway */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {TCL} /* Build configuration list for PBXNativeTarget "NeonGetaway" */;
			buildPhases = (
				{SRC} /* Sources */,
				{FW} /* Frameworks */,
				{RES} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{SYNC} /* NeonGetaway */,
			);
			name = NeonGetaway;
			packageProductDependencies = (
				{DEP} /* GameCore */,
			);
			productName = NeonGetaway;
			productReference = {APP} /* NeonGetaway.app */;
			productType = "com.apple.product-type.application";
		}};
		{UT} /* NeonGetawayUITests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {UTCL} /* Build configuration list for PBXNativeTarget "NeonGetawayUITests" */;
			buildPhases = (
				{UTSRC} /* Sources */,
				{UTFW} /* Frameworks */,
				{UTRES} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{UTDEP} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{UTSYNC} /* NeonGetawayUITests */,
			);
			name = NeonGetawayUITests;
			productName = NeonGetawayUITests;
			productReference = {UTREF} /* NeonGetawayUITests.xctest */;
			productType = "com.apple.product-type.bundle.ui-testing";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{P} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2600;
				LastUpgradeCheck = 2600;
				TargetAttributes = {{
					{TGT} = {{
						CreatedOnToolsVersion = 26.0;
					}};
					{UT} = {{
						CreatedOnToolsVersion = 26.0;
						TestTargetID = {TGT};
					}};
				}};
			}};
			buildConfigurationList = {PCL} /* Build configuration list for PBXProject "NeonGetaway" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {MAIN};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{LPKG} /* XCLocalSwiftPackageReference "Packages/GameCore" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {PRODG} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{TGT} /* NeonGetaway */,
				{UT} /* NeonGetawayUITests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{RES} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{UTRES} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{SRC} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{UTSRC} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{UTDEP} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {TGT} /* NeonGetaway */;
			targetProxy = {UTPROXY} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{PD} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{proj_debug}			}};
			name = Debug;
		}};
		{PR} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{proj_release}			}};
			name = Release;
		}};
		{TD} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{tgt}			}};
			name = Debug;
		}};
		{TR} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{tgt}			}};
			name = Release;
		}};
		{UTD} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{ui_settings}			}};
			name = Debug;
		}};
		{UTR} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{ui_settings}			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{PCL} /* Build configuration list for PBXProject "NeonGetaway" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{PD} /* Debug */,
				{PR} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{TCL} /* Build configuration list for PBXNativeTarget "NeonGetaway" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{TD} /* Debug */,
				{TR} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{UTCL} /* Build configuration list for PBXNativeTarget "NeonGetawayUITests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{UTD} /* Debug */,
				{UTR} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{LPKG} /* XCLocalSwiftPackageReference "Packages/GameCore" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/GameCore;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{DEP} /* GameCore */ = {{
			isa = XCSwiftPackageProductDependency;
			productName = GameCore;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {P} /* Project object */;
}}
'''
d=os.path.join(root,'NeonGetaway.xcodeproj'); os.makedirs(os.path.join(d,'xcshareddata/xcschemes'),exist_ok=True)
open(os.path.join(d,'project.pbxproj'),'w').write(s)
ref=f'''            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{TGT}"
               BuildableName = "NeonGetaway.app"
               BlueprintName = "NeonGetaway"
               ReferencedContainer = "container:NeonGetaway.xcodeproj">
            </BuildableReference>'''
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
{ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES" shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference skipped = "NO" parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{UT}"
               BuildableName = "NeonGetawayUITests.xctest"
               BlueprintName = "NeonGetawayUITests"
               ReferencedContainer = "container:NeonGetaway.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
{ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
{ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
open(os.path.join(d,'xcshareddata/xcschemes/NeonGetaway.xcscheme'),'w').write(scheme)
print('ok')
