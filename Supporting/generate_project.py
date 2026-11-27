#!/usr/bin/env python3
"""Generates Pulse.xcodeproj.

Hand-maintaining a three-target pbxproj is how projects get corrupted, so the
file is generated and then checked: every object id referenced anywhere must
be defined somewhere. A dangling id is what makes Xcode report a project as
damaged, and that check catches it before the file is written.

Run from the repository root:  python3 Supporting/generate_project.py
"""
import hashlib
import re
import sys

APP_BUNDLE_ID = "com.pulse.polymarket"


def oid(name: str) -> str:
    """Stable 24-hex-character object id derived from a name."""
    return hashlib.sha256(("pulse:" + name).encode()).hexdigest()[:24].upper()


K = {k: oid(k) for k in [
    "project", "mainGroup", "productsGroup", "projectConfigList",
    "projDebug", "projRelease", "xcconfigRef",
    "infoPlistRef", "widgetsPlistRef", "watchPlistRef",
    # app
    "app.target", "app.product", "app.sources", "app.frameworks",
    "app.resources", "app.embedExtensions", "app.embedWatch",
    "app.configList", "app.debug", "app.release", "app.syncGroup",
    "app.pkgProduct", "app.pkgBuildFile",
    "privyPkgRef", "app.privyProduct", "app.privyBuildFile",
    # widgets
    "wx.target", "wx.product", "wx.sources", "wx.frameworks", "wx.resources",
    "wx.configList", "wx.debug", "wx.release", "wx.syncGroup",
    "wx.pkgProduct", "wx.pkgBuildFile", "wx.embedFile",
    "wx.dependency", "wx.containerProxy",
    # watch
    "wk.target", "wk.product", "wk.sources", "wk.frameworks", "wk.resources",
    "wk.configList", "wk.debug", "wk.release", "wk.syncGroup",
    "wk.pkgProduct", "wk.pkgBuildFile", "wk.embedFile",
    "wk.dependency", "wk.containerProxy",
    # package
    "packageRef",
]}

COMMON = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tPULSE_APP_BUNDLE_ID = %s;
\t\t\t\tSWIFT_VERSION = 6.0;
""" % APP_BUNDLE_ID

TARGET_COMMON = """\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = "$(DEVELOPMENT_TEAM)";
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
"""

APP_SETTINGS = TARGET_COMMON + """\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tINFOPLIST_FILE = Supporting/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "$(PULSE_APP_BUNDLE_ID)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
"""

WX_SETTINGS = TARGET_COMMON + """\t\t\t\tINFOPLIST_FILE = Supporting/Widgets-Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "$(PULSE_APP_BUNDLE_ID).PulseWidgets";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
"""

WK_SETTINGS = TARGET_COMMON + """\t\t\t\tINFOPLIST_FILE = Supporting/Watch-Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "$(PULSE_APP_BUNDLE_ID).watchkitapp";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = 4;
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 10.0;
"""


def build() -> str:
    p = []
    a = p.append
    a("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};")
    a("\tobjectVersion = 77;\n\tobjects = {\n")

    # ---- PBXBuildFile
    a("/* Begin PBXBuildFile section */")
    for key, product, label in [
        ("app.pkgBuildFile", "app.pkgProduct", "PulseCore"),
        ("app.privyBuildFile", "app.privyProduct", "Privy"),
        ("wx.pkgBuildFile", "wx.pkgProduct", "PulseCore"),
        ("wk.pkgBuildFile", "wk.pkgProduct", "PulseCore"),
    ]:
        a(f"\t\t{K[key]} /* {label} in Frameworks */ = {{isa = PBXBuildFile; "
          f"productRef = {K[product]} /* {label} */; }};")
    # Embedding the extension and the watch app into the phone app.
    a(f"\t\t{K['wx.embedFile']} /* PulseWidgets.appex in Embed Foundation Extensions */ = "
      f"{{isa = PBXBuildFile; fileRef = {K['wx.product']} /* PulseWidgets.appex */; "
      f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
    a(f"\t\t{K['wk.embedFile']} /* PulseWatch.app in Embed Watch Content */ = "
      f"{{isa = PBXBuildFile; fileRef = {K['wk.product']} /* PulseWatch.app */; "
      f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
    a("/* End PBXBuildFile section */\n")

    # ---- PBXContainerItemProxy
    a("/* Begin PBXContainerItemProxy section */")
    for key, target, name in [
        ("wx.containerProxy", "wx.target", "PulseWidgets"),
        ("wk.containerProxy", "wk.target", "PulseWatch"),
    ]:
        a(f"\t\t{K[key]} /* PBXContainerItemProxy */ = {{\n"
          f"\t\t\tisa = PBXContainerItemProxy;\n"
          f"\t\t\tcontainerPortal = {K['project']} /* Project object */;\n"
          f"\t\t\tproxyType = 1;\n"
          f"\t\t\tremoteGlobalIDString = {K[target]};\n"
          f"\t\t\tremoteInfo = {name};\n\t\t}};")
    a("/* End PBXContainerItemProxy section */\n")

    # ---- PBXCopyFilesBuildPhase
    a("/* Begin PBXCopyFilesBuildPhase section */")
    a(f"\t\t{K['app.embedExtensions']} /* Embed Foundation Extensions */ = {{\n"
      f"\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
      f"\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n"
      f"\t\t\t\t{K['wx.embedFile']} /* PulseWidgets.appex in Embed Foundation Extensions */,\n"
      f"\t\t\t);\n\t\t\tname = \"Embed Foundation Extensions\";\n"
      f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
    a(f"\t\t{K['app.embedWatch']} /* Embed Watch Content */ = {{\n"
      f"\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n"
      f"\t\t\tdstPath = \"$(CONTENTS_FOLDER_PATH)/Watch\";\n\t\t\tdstSubfolderSpec = 16;\n"
      f"\t\t\tfiles = (\n"
      f"\t\t\t\t{K['wk.embedFile']} /* PulseWatch.app in Embed Watch Content */,\n"
      f"\t\t\t);\n\t\t\tname = \"Embed Watch Content\";\n"
      f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
    a("/* End PBXCopyFilesBuildPhase section */\n")

    # ---- PBXFileReference
    a("/* Begin PBXFileReference section */")
    a(f"\t\t{K['app.product']} /* Pulse.app */ = {{isa = PBXFileReference; "
      f"explicitFileType = wrapper.application; includeInIndex = 0; path = Pulse.app; "
      f"sourceTree = BUILT_PRODUCTS_DIR; }};")
    a(f"\t\t{K['wx.product']} /* PulseWidgets.appex */ = {{isa = PBXFileReference; "
      f"explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; "
      f"path = PulseWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
    a(f"\t\t{K['wk.product']} /* PulseWatch.app */ = {{isa = PBXFileReference; "
      f"explicitFileType = wrapper.application; includeInIndex = 0; path = PulseWatch.app; "
      f"sourceTree = BUILT_PRODUCTS_DIR; }};")
    a(f"\t\t{K['xcconfigRef']} /* Config.xcconfig */ = {{isa = PBXFileReference; "
      f"lastKnownFileType = text.xcconfig; path = Config.xcconfig; sourceTree = \"<group>\"; }};")
    for key, path, name in [
        ("infoPlistRef", "Supporting/Info.plist", "Info.plist"),
        ("widgetsPlistRef", "Supporting/Widgets-Info.plist", "Widgets-Info.plist"),
        ("watchPlistRef", "Supporting/Watch-Info.plist", "Watch-Info.plist"),
    ]:
        a(f"\t\t{K[key]} /* {name} */ = {{isa = PBXFileReference; "
          f"lastKnownFileType = text.plist.xml; name = {name}; path = {path}; "
          f"sourceTree = \"<group>\"; }};")
    a("/* End PBXFileReference section */\n")

    # ---- PBXFileSystemSynchronizedRootGroup
    # Each target owns one folder; adding a file to it joins that target with
    # no project edit. Nothing that is also produced by a build setting may
    # live in these folders — see the Info.plist note in the README.
    a("/* Begin PBXFileSystemSynchronizedRootGroup section */")
    for key, path in [
        ("app.syncGroup", "Pulse"),
        ("wx.syncGroup", "PulseWidgets"),
        ("wk.syncGroup", "PulseWatch"),
    ]:
        a(f"\t\t{K[key]} /* {path} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
          f"\t\t\texceptions = (\n\t\t\t);\n\t\t\tpath = {path};\n"
          f"\t\t\tsourceTree = \"<group>\";\n\t\t}};")
    a("/* End PBXFileSystemSynchronizedRootGroup section */\n")

    # ---- PBXFrameworksBuildPhase
    a("/* Begin PBXFrameworksBuildPhase section */")
    # The app links Privy as well as PulseCore; the extension and watch
    # targets do not — neither signs, and the xcframework is large.
    a(f"\t\t{K['app.frameworks']} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n"
      f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
      f"\t\t\t\t{K['app.pkgBuildFile']} /* PulseCore in Frameworks */,\n"
      f"\t\t\t\t{K['app.privyBuildFile']} /* Privy in Frameworks */,\n\t\t\t);\n"
      f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
    for key, bf in [
        ("wx.frameworks", "wx.pkgBuildFile"),
        ("wk.frameworks", "wk.pkgBuildFile"),
    ]:
        a(f"\t\t{K[key]} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n"
          f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
          f"\t\t\t\t{K[bf]} /* PulseCore in Frameworks */,\n\t\t\t);\n"
          f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
    a("/* End PBXFrameworksBuildPhase section */\n")

    # ---- PBXGroup
    a("/* Begin PBXGroup section */")
    a(f"\t\t{K['mainGroup']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
      f"\t\t\t\t{K['xcconfigRef']} /* Config.xcconfig */,\n"
      f"\t\t\t\t{K['infoPlistRef']} /* Info.plist */,\n"
      f"\t\t\t\t{K['widgetsPlistRef']} /* Widgets-Info.plist */,\n"
      f"\t\t\t\t{K['watchPlistRef']} /* Watch-Info.plist */,\n"
      f"\t\t\t\t{K['app.syncGroup']} /* Pulse */,\n"
      f"\t\t\t\t{K['wx.syncGroup']} /* PulseWidgets */,\n"
      f"\t\t\t\t{K['wk.syncGroup']} /* PulseWatch */,\n"
      f"\t\t\t\t{K['productsGroup']} /* Products */,\n"
      f"\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
    a(f"\t\t{K['productsGroup']} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n"
      f"\t\t\tchildren = (\n"
      f"\t\t\t\t{K['app.product']} /* Pulse.app */,\n"
      f"\t\t\t\t{K['wx.product']} /* PulseWidgets.appex */,\n"
      f"\t\t\t\t{K['wk.product']} /* PulseWatch.app */,\n"
      f"\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
    a("/* End PBXGroup section */\n")

    # ---- PBXNativeTarget
    a("/* Begin PBXNativeTarget section */")
    a(f"\t\t{K['app.target']} /* Pulse */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
      f"\t\t\tbuildConfigurationList = {K['app.configList']};\n"
      f"\t\t\tbuildPhases = (\n"
      f"\t\t\t\t{K['app.sources']} /* Sources */,\n"
      f"\t\t\t\t{K['app.frameworks']} /* Frameworks */,\n"
      f"\t\t\t\t{K['app.resources']} /* Resources */,\n"
      f"\t\t\t\t{K['app.embedExtensions']} /* Embed Foundation Extensions */,\n"
      f"\t\t\t\t{K['app.embedWatch']} /* Embed Watch Content */,\n"
      f"\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n"
      f"\t\t\tdependencies = (\n"
      f"\t\t\t\t{K['wx.dependency']} /* PBXTargetDependency */,\n"
      f"\t\t\t\t{K['wk.dependency']} /* PBXTargetDependency */,\n"
      f"\t\t\t);\n"
      f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{K['app.syncGroup']} /* Pulse */,\n\t\t\t);\n"
      f"\t\t\tname = Pulse;\n"
      f"\t\t\tpackageProductDependencies = (\n\t\t\t\t{K['app.pkgProduct']} /* PulseCore */,\n"
      f"\t\t\t\t{K['app.privyProduct']} /* Privy */,\n\t\t\t);\n"
      f"\t\t\tproductName = Pulse;\n\t\t\tproductReference = {K['app.product']} /* Pulse.app */;\n"
      f"\t\t\tproductType = \"com.apple.product-type.application\";\n\t\t}};")

    a(f"\t\t{K['wx.target']} /* PulseWidgets */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
      f"\t\t\tbuildConfigurationList = {K['wx.configList']};\n"
      f"\t\t\tbuildPhases = (\n"
      f"\t\t\t\t{K['wx.sources']} /* Sources */,\n"
      f"\t\t\t\t{K['wx.frameworks']} /* Frameworks */,\n"
      f"\t\t\t\t{K['wx.resources']} /* Resources */,\n"
      f"\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n"
      f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{K['wx.syncGroup']} /* PulseWidgets */,\n\t\t\t);\n"
      f"\t\t\tname = PulseWidgets;\n"
      f"\t\t\tpackageProductDependencies = (\n\t\t\t\t{K['wx.pkgProduct']} /* PulseCore */,\n\t\t\t);\n"
      f"\t\t\tproductName = PulseWidgets;\n"
      f"\t\t\tproductReference = {K['wx.product']} /* PulseWidgets.appex */;\n"
      f"\t\t\tproductType = \"com.apple.product-type.app-extension\";\n\t\t}};")

    a(f"\t\t{K['wk.target']} /* PulseWatch */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
      f"\t\t\tbuildConfigurationList = {K['wk.configList']};\n"
      f"\t\t\tbuildPhases = (\n"
      f"\t\t\t\t{K['wk.sources']} /* Sources */,\n"
      f"\t\t\t\t{K['wk.frameworks']} /* Frameworks */,\n"
      f"\t\t\t\t{K['wk.resources']} /* Resources */,\n"
      f"\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n"
      f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{K['wk.syncGroup']} /* PulseWatch */,\n\t\t\t);\n"
      f"\t\t\tname = PulseWatch;\n"
      f"\t\t\tpackageProductDependencies = (\n\t\t\t\t{K['wk.pkgProduct']} /* PulseCore */,\n\t\t\t);\n"
      f"\t\t\tproductName = PulseWatch;\n"
      f"\t\t\tproductReference = {K['wk.product']} /* PulseWatch.app */;\n"
      f"\t\t\tproductType = \"com.apple.product-type.application\";\n\t\t}};")
    a("/* End PBXNativeTarget section */\n")

    # ---- PBXProject
    a("/* Begin PBXProject section */")
    a(f"\t\t{K['project']} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n"
      f"\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
      f"\t\t\t\tLastSwiftUpdateCheck = 1600;\n\t\t\t\tLastUpgradeCheck = 1600;\n"
      f"\t\t\t\tTargetAttributes = {{\n"
      f"\t\t\t\t\t{K['app.target']} = {{CreatedOnToolsVersion = 16.0; }};\n"
      f"\t\t\t\t\t{K['wx.target']} = {{CreatedOnToolsVersion = 16.0; }};\n"
      f"\t\t\t\t\t{K['wk.target']} = {{CreatedOnToolsVersion = 16.0; }};\n"
      f"\t\t\t\t}};\n\t\t\t}};\n"
      f"\t\t\tbuildConfigurationList = {K['projectConfigList']};\n"
      f"\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n"
      f"\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
      f"\t\t\tmainGroup = {K['mainGroup']};\n\t\t\tminimizedProjectReferenceProxies = 1;\n"
      f"\t\t\tpackageReferences = (\n"
      f"\t\t\t\t{K['packageRef']} /* XCLocalSwiftPackageReference \"PulseCore\" */,\n"
      f"\t\t\t\t{K['privyPkgRef']} /* XCRemoteSwiftPackageReference \"privy-ios\" */,\n\t\t\t);\n"
      f"\t\t\tpreferredProjectObjectVersion = 77;\n"
      f"\t\t\tproductRefGroup = {K['productsGroup']} /* Products */;\n"
      f"\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n"
      f"\t\t\ttargets = (\n"
      f"\t\t\t\t{K['app.target']} /* Pulse */,\n"
      f"\t\t\t\t{K['wx.target']} /* PulseWidgets */,\n"
      f"\t\t\t\t{K['wk.target']} /* PulseWatch */,\n"
      f"\t\t\t);\n\t\t}};")
    a("/* End PBXProject section */\n")

    # ---- Resources / Sources phases
    a("/* Begin PBXResourcesBuildPhase section */")
    for key in ["app.resources", "wx.resources", "wk.resources"]:
        a(f"\t\t{K[key]} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n"
          f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
          f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
    a("/* End PBXResourcesBuildPhase section */\n")

    a("/* Begin PBXSourcesBuildPhase section */")
    for key in ["app.sources", "wx.sources", "wk.sources"]:
        a(f"\t\t{K[key]} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n"
          f"\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
          f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
    a("/* End PBXSourcesBuildPhase section */\n")

    # ---- PBXTargetDependency
    a("/* Begin PBXTargetDependency section */")
    for key, target, proxy, name in [
        ("wx.dependency", "wx.target", "wx.containerProxy", "PulseWidgets"),
        ("wk.dependency", "wk.target", "wk.containerProxy", "PulseWatch"),
    ]:
        a(f"\t\t{K[key]} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n"
          f"\t\t\tname = {name};\n\t\t\ttarget = {K[target]} /* {name} */;\n"
          f"\t\t\ttargetProxy = {K[proxy]} /* PBXContainerItemProxy */;\n\t\t}};")
    a("/* End PBXTargetDependency section */\n")

    # ---- XCBuildConfiguration
    a("/* Begin XCBuildConfiguration section */")
    a(f"\t\t{K['projDebug']} /* Debug */ = {{\n\t\t\tisa = XCBuildConfiguration;\n"
      f"\t\t\tbaseConfigurationReference = {K['xcconfigRef']} /* Config.xcconfig */;\n"
      f"\t\t\tbuildSettings = {{\n{COMMON}"
      f"\t\t\t\tCOPY_PHASE_STRIP = NO;\n\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;\n"
      f"\t\t\t\tENABLE_TESTABILITY = YES;\n\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;\n"
      f"\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;\n"
      f"\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (\n\t\t\t\t\t\"DEBUG=1\",\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t);\n"
      f"\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;\n\t\t\t\tONLY_ACTIVE_ARCH = YES;\n"
      f"\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";\n"
      f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";\n"
      f"\t\t\t}};\n\t\t\tname = Debug;\n\t\t}};")
    a(f"\t\t{K['projRelease']} /* Release */ = {{\n\t\t\tisa = XCBuildConfiguration;\n"
      f"\t\t\tbaseConfigurationReference = {K['xcconfigRef']} /* Config.xcconfig */;\n"
      f"\t\t\tbuildSettings = {{\n{COMMON}"
      f"\t\t\t\tCOPY_PHASE_STRIP = NO;\n\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";\n"
      f"\t\t\t\tENABLE_NS_ASSERTIONS = NO;\n\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;\n"
      f"\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n\t\t\t\tVALIDATE_PRODUCT = YES;\n"
      f"\t\t\t}};\n\t\t\tname = Release;\n\t\t}};")
    for key, settings, name in [
        ("app.debug", APP_SETTINGS, "Debug"), ("app.release", APP_SETTINGS, "Release"),
        ("wx.debug", WX_SETTINGS, "Debug"), ("wx.release", WX_SETTINGS, "Release"),
        ("wk.debug", WK_SETTINGS, "Debug"), ("wk.release", WK_SETTINGS, "Release"),
    ]:
        a(f"\t\t{K[key]} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n"
          f"\t\t\tbuildSettings = {{\n{settings}\t\t\t}};\n\t\t\tname = {name};\n\t\t}};")
    a("/* End XCBuildConfiguration section */\n")

    # ---- XCConfigurationList
    a("/* Begin XCConfigurationList section */")
    for key, debug, release, label in [
        ("projectConfigList", "projDebug", "projRelease", "PBXProject \"Pulse\""),
        ("app.configList", "app.debug", "app.release", "PBXNativeTarget \"Pulse\""),
        ("wx.configList", "wx.debug", "wx.release", "PBXNativeTarget \"PulseWidgets\""),
        ("wk.configList", "wk.debug", "wk.release", "PBXNativeTarget \"PulseWatch\""),
    ]:
        a(f"\t\t{K[key]} /* Build configuration list for {label} */ = {{\n"
          f"\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
          f"\t\t\t\t{K[debug]} /* Debug */,\n\t\t\t\t{K[release]} /* Release */,\n"
          f"\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n"
          f"\t\t\tdefaultConfigurationName = Release;\n\t\t}};")
    a("/* End XCConfigurationList section */\n")

    # ---- Packages
    a("/* Begin XCLocalSwiftPackageReference section */")
    a(f"\t\t{K['packageRef']} /* XCLocalSwiftPackageReference \"PulseCore\" */ = {{\n"
      f"\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = PulseCore;\n\t\t}};")
    a("/* End XCLocalSwiftPackageReference section */\n")

    a("/* Begin XCRemoteSwiftPackageReference section */")
    a(f"\t\t{K['privyPkgRef']} /* XCRemoteSwiftPackageReference \"privy-ios\" */ = {{\n"
      f"\t\t\tisa = XCRemoteSwiftPackageReference;\n"
      f"\t\t\trepositoryURL = \"https://github.com/privy-io/privy-ios.git\";\n"
      f"\t\t\trequirement = {{\n\t\t\t\tkind = upToNextMajorVersion;\n"
      f"\t\t\t\tminimumVersion = 2.19.0;\n\t\t\t}};\n\t\t}};")
    a("/* End XCRemoteSwiftPackageReference section */\n")

    a("/* Begin XCSwiftPackageProductDependency section */")
    for key in ["app.pkgProduct", "wx.pkgProduct", "wk.pkgProduct"]:
        a(f"\t\t{K[key]} /* PulseCore */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n"
          f"\t\t\tproductName = PulseCore;\n\t\t}};")
    a(f"\t\t{K['app.privyProduct']} /* Privy */ = {{\n"
      f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
      f"\t\t\tpackage = {K['privyPkgRef']} /* XCRemoteSwiftPackageReference \"privy-ios\" */;\n"
      f"\t\t\tproductName = Privy;\n\t\t}};")
    a("/* End XCSwiftPackageProductDependency section */\n")

    a(f"\t}};\n\trootObject = {K['project']} /* Project object */;\n}}\n")
    return "\n".join(p)


def validate(text: str) -> list[str]:
    """Every referenced object id must be defined. A dangling id is what makes
    Xcode call a project damaged, so refuse to write one."""
    problems = []
    defined = set(re.findall(r"^\t\t([0-9A-F]{24}) ", text, re.M))
    referenced = set(re.findall(r"\b([0-9A-F]{24})\b", text))

    for ref in sorted(referenced - defined):
        problems.append(f"referenced but never defined: {ref}")
    for unused in sorted(defined - (referenced - defined)):
        if text.count(unused) < 2:
            problems.append(f"defined but never referenced: {unused}")
    if text.count("{") != text.count("}"):
        problems.append(f"unbalanced braces: {text.count('{')} vs {text.count('}')}")
    if text.count("(") != text.count(")"):
        problems.append(f"unbalanced parens: {text.count('(')} vs {text.count(')')}")
    return problems


if __name__ == "__main__":
    content = build()
    issues = validate(content)
    if issues:
        print("REFUSING TO WRITE — project would be malformed:")
        for issue in issues:
            print("  -", issue)
        sys.exit(1)
    with open("Pulse.xcodeproj/project.pbxproj", "w") as handle:
        handle.write(content)
    print(f"wrote Pulse.xcodeproj/project.pbxproj ({len(content.splitlines())} lines)")
    print("targets: Pulse (iOS), PulseWidgets (extension), PulseWatch (watchOS)")
