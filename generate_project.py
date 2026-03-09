#!/usr/bin/env python3
"""
Generates Tract.xcodeproj/project.pbxproj for the Spline app.
Run from the project root after adding/removing source files:
    python3 generate_project.py
"""

import os
import hashlib
import re

BASE = os.path.dirname(os.path.abspath(__file__))

# ── All source files relative to project root ──────────────────────────────
SOURCE_FILES = [
    "App/SplineApp.swift",
    # Canvas
    "Canvas/CanvasContainerView.swift",
    "Canvas/CanvasView.swift",
    "Canvas/CanvasUIView.swift",
    "Canvas/CanvasRenderer.swift",
    "Canvas/CanvasViewModel.swift",
    "Canvas/CanvasTransform.swift",
    # Toolbar
    "Toolbar/TopBarView.swift",
    "Toolbar/DocumentTitleView.swift",
    "Toolbar/UndoRedoView.swift",
    "Toolbar/SelectToolButton.swift",
    "Toolbar/ExportButton.swift",
    # Palette
    "Palette/PaletteView.swift",
    "Palette/ToolButton.swift",
    "Palette/PenToolButton.swift",
    "Palette/PencilToolButton.swift",
    "Palette/MarkerToolButton.swift",
    "Palette/EraserToolButton.swift",
    "Palette/LassoToolButton.swift",
    "Palette/StrokeWeightButton.swift",
    "Palette/StrokeWeightFlyout.swift",
    "Palette/ColorSwatchButton.swift",
    # ColorPanel
    "ColorPanel/ColorPanelView.swift",
    "ColorPanel/ColorPresetGrid.swift",
    "ColorPanel/CustomColorRow.swift",
    "ColorPanel/OpacitySlider.swift",
    # Overlay
    "Overlay/ZoomIndicatorView.swift",
    "Overlay/SelectionBoxView.swift",
    # Stroke
    "Stroke/StrokePoint.swift",
    "Stroke/Stroke.swift",
    "Stroke/StrokeStyle.swift",
    # Document
    "Document/SplineDocument.swift",
    "Document/DocumentStore.swift",
    "Document/DocumentListView.swift",
    "Document/DocumentListRow.swift",
    # Export
    "Export/ExportAdapter.swift",
    "Export/ExportSheetView.swift",
    "Export/SVGExporter.swift",
    "Export/PDFExporter.swift",
    "Export/PNGExporter.swift",
    # Utilities
    "Utilities/CGPoint+Math.swift",
    "Utilities/Color+Hex.swift",
    "Utilities/View+GlassCard.swift",
]

# ── Stable UUID generation (deterministic from path) ──────────────────────
def make_id(seed: str) -> str:
    """24-character hex ID derived from seed — stable across re-runs."""
    h = hashlib.md5(seed.encode()).hexdigest()
    return h[:24].upper()

# OpenStep plist: only alphanum, underscore, hyphen, period, $ are safe unquoted.
_SAFE_UNQUOTED = re.compile(r'^[A-Za-z0-9_\-\.$]+$')

def plist_str(s: str) -> str:
    """Quote a string if it contains any character unsafe in unquoted OpenStep plist."""
    if _SAFE_UNQUOTED.match(s):
        return s
    # Escape backslashes and double-quotes, then wrap in double-quotes.
    escaped = s.replace('\\', '\\\\').replace('"', '\\"')
    return f'"{escaped}"'

# ── Fixed element IDs ──────────────────────────────────────────────────────
PROJECT_ID               = make_id("project")
TARGET_ID                = make_id("target")
MAIN_GROUP_ID            = make_id("main_group")
PRODUCTS_ID              = make_id("products_group")
SOURCES_PHASE            = make_id("sources_phase")
FRAMEWORKS_PHASE         = make_id("frameworks_phase")
RESOURCES_PHASE          = make_id("resources_phase")
BUILD_CONFIG_LIST_PROJECT = make_id("config_list_project")
BUILD_CONFIG_LIST_TARGET  = make_id("config_list_target")
DEBUG_CONFIG_PROJECT     = make_id("debug_project")
RELEASE_CONFIG_PROJECT   = make_id("release_project")
DEBUG_CONFIG_TARGET      = make_id("debug_target")
RELEASE_CONFIG_TARGET    = make_id("release_target")
PRODUCT_REF              = make_id("product_ref")

# Assets
ASSETS_FILE_REF  = make_id("assets_ref")
ASSETS_BUILD_REF = make_id("assets_build")

# Core Data model — needs an XCVersionGroup containing the .xcdatamodel child
COREDATA_VERSION_GROUP = make_id("coredata_version_group")
COREDATA_MODEL_REF     = make_id("coredata_model_ref")     # the .xcdatamodel inside
COREDATA_BUILD_REF     = make_id("coredata_build")

# Folder group IDs
FOLDER_GROUPS = {
    "App":        make_id("group_app"),
    "Canvas":     make_id("group_canvas"),
    "Toolbar":    make_id("group_toolbar"),
    "Palette":    make_id("group_palette"),
    "ColorPanel": make_id("group_colorpanel"),
    "Overlay":    make_id("group_overlay"),
    "Stroke":     make_id("group_stroke"),
    "Document":   make_id("group_document"),
    "Export":     make_id("group_export"),
    "Utilities":  make_id("group_utilities"),
}

file_refs  = {f: make_id(f"file_ref_{f}")  for f in SOURCE_FILES}
build_refs = {f: make_id(f"build_ref_{f}") for f in SOURCE_FILES}


def pbxproj() -> str:
    lines = []
    def ln(s=""): lines.append(s)

    ln("// !$*UTF8*$!")
    ln("{")
    ln("\tarchiveVersion = 1;")
    ln("\tclasses = {")
    ln("\t};")
    ln("\tobjectVersion = 77;")
    ln("\tobjects = {")
    ln()

    # ── PBXBuildFile ──────────────────────────────────────────────────────
    ln("/* Begin PBXBuildFile section */")
    for f in SOURCE_FILES:
        name = os.path.basename(f)
        ln(f"\t\t{build_refs[f]} /* {name} in Sources */ = "
           f"{{isa = PBXBuildFile; fileRef = {file_refs[f]} /* {name} */; }};")
    ln(f"\t\t{ASSETS_BUILD_REF} /* Assets.xcassets in Resources */ = "
       f"{{isa = PBXBuildFile; fileRef = {ASSETS_FILE_REF} /* Assets.xcassets */; }};")
    ln(f"\t\t{COREDATA_BUILD_REF} /* Persistence.xcdatamodeld in Sources */ = "
       f"{{isa = PBXBuildFile; fileRef = {COREDATA_VERSION_GROUP} /* Persistence.xcdatamodeld */; }};")
    ln("/* End PBXBuildFile section */")
    ln()

    # ── PBXFileReference ──────────────────────────────────────────────────
    ln("/* Begin PBXFileReference section */")
    for f in SOURCE_FILES:
        name = os.path.basename(f)
        safe_name = plist_str(name)
        ln(f"\t\t{file_refs[f]} /* {name} */ = "
           f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
           f"path = {safe_name}; sourceTree = \"<group>\"; }};")
    ln(f"\t\t{ASSETS_FILE_REF} /* Assets.xcassets */ = "
       f"{{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; "
       f"path = Assets.xcassets; sourceTree = \"<group>\"; }};")
    # The inner .xcdatamodel file reference
    ln(f"\t\t{COREDATA_MODEL_REF} /* Persistence.xcdatamodel */ = "
       f"{{isa = PBXFileReference; lastKnownFileType = wrapper.xcdatamodel; "
       f"path = Persistence.xcdatamodel; sourceTree = \"<group>\"; }};")
    ln(f"\t\t{PRODUCT_REF} /* Tract.app */ = "
       f"{{isa = PBXFileReference; explicitFileType = wrapper.application; "
       f"includeInIndex = 0; path = Tract.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    ln("/* End PBXFileReference section */")
    ln()

    # ── PBXFrameworksBuildPhase ────────────────────────────────────────────
    ln("/* Begin PBXFrameworksBuildPhase section */")
    ln(f"\t\t{FRAMEWORKS_PHASE} /* Frameworks */ = {{")
    ln("\t\t\tisa = PBXFrameworksBuildPhase;")
    ln("\t\t\tbuildActionMask = 2147483647;")
    ln("\t\t\tfiles = (")
    ln("\t\t\t);")
    ln("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    ln("\t\t};")
    ln("/* End PBXFrameworksBuildPhase section */")
    ln()

    # ── PBXGroup ──────────────────────────────────────────────────────────
    ln("/* Begin PBXGroup section */")

    # Root group
    ln(f"\t\t{MAIN_GROUP_ID} = {{")
    ln("\t\t\tisa = PBXGroup;")
    ln("\t\t\tchildren = (")
    for folder, group_id in FOLDER_GROUPS.items():
        ln(f"\t\t\t\t{group_id} /* {folder} */,")
    ln(f"\t\t\t\t{ASSETS_FILE_REF} /* Assets.xcassets */,")
    ln(f"\t\t\t\t{COREDATA_VERSION_GROUP} /* Persistence.xcdatamodeld */,")
    ln(f"\t\t\t\t{PRODUCTS_ID} /* Products */,")
    ln("\t\t\t);")
    ln('\t\t\tsourceTree = "<group>";')
    ln("\t\t};")

    # Products group
    ln(f"\t\t{PRODUCTS_ID} /* Products */ = {{")
    ln("\t\t\tisa = PBXGroup;")
    ln("\t\t\tchildren = (")
    ln(f"\t\t\t\t{PRODUCT_REF} /* Tract.app */,")
    ln("\t\t\t);")
    ln("\t\t\tname = Products;")
    ln('\t\t\tsourceTree = "<group>";')
    ln("\t\t};")

    # Feature folder groups
    for folder, group_id in FOLDER_GROUPS.items():
        folder_files = [f for f in SOURCE_FILES if f.startswith(folder + "/")]
        ln(f"\t\t{group_id} /* {folder} */ = {{")
        ln("\t\t\tisa = PBXGroup;")
        ln("\t\t\tchildren = (")
        for f in folder_files:
            name = os.path.basename(f)
            ln(f"\t\t\t\t{file_refs[f]} /* {name} */,")
        ln("\t\t\t);")
        ln(f"\t\t\tpath = {folder};")
        ln('\t\t\tsourceTree = "<group>";')
        ln("\t\t};")

    ln("/* End PBXGroup section */")
    ln()

    # ── PBXNativeTarget ────────────────────────────────────────────────────
    ln("/* Begin PBXNativeTarget section */")
    ln(f"\t\t{TARGET_ID} /* Tract */ = {{")
    ln("\t\t\tisa = PBXNativeTarget;")
    ln(f"\t\t\tbuildConfigurationList = {BUILD_CONFIG_LIST_TARGET}"
       f" /* Build configuration list for PBXNativeTarget \"Tract\" */;")
    ln("\t\t\tbuildPhases = (")
    ln(f"\t\t\t\t{SOURCES_PHASE} /* Sources */,")
    ln(f"\t\t\t\t{FRAMEWORKS_PHASE} /* Frameworks */,")
    ln(f"\t\t\t\t{RESOURCES_PHASE} /* Resources */,")
    ln("\t\t\t);")
    ln("\t\t\tbuildRules = (")
    ln("\t\t\t);")
    ln("\t\t\tdependencies = (")
    ln("\t\t\t);")
    ln("\t\t\tname = Tract;")
    ln("\t\t\tproductName = Tract;")
    ln(f"\t\t\tproductReference = {PRODUCT_REF} /* Tract.app */;")
    ln('\t\t\tproductType = "com.apple.product-type.application";')
    ln("\t\t};")
    ln("/* End PBXNativeTarget section */")
    ln()

    # ── PBXProject ─────────────────────────────────────────────────────────
    ln("/* Begin PBXProject section */")
    ln(f"\t\t{PROJECT_ID} /* Project object */ = {{")
    ln("\t\t\tisa = PBXProject;")
    ln(f"\t\t\tbuildConfigurationList = {BUILD_CONFIG_LIST_PROJECT}"
       f" /* Build configuration list for PBXProject \"Tract\" */;")
    ln('\t\t\tcompatibilityVersion = "Xcode 16.0";')
    ln("\t\t\tdevelopmentRegion = en;")
    ln("\t\t\thasScannedForEncodings = 0;")
    ln("\t\t\tknownRegions = (")
    ln("\t\t\t\ten,")
    ln("\t\t\t\tBase,")
    ln("\t\t\t);")
    ln(f"\t\t\tmainGroup = {MAIN_GROUP_ID};")
    ln(f"\t\t\tproductRefGroup = {PRODUCTS_ID} /* Products */;")
    ln('\t\t\tprojectDirPath = "";')
    ln('\t\t\tprojectRoot = "";')
    ln("\t\t\ttargets = (")
    ln(f"\t\t\t\t{TARGET_ID} /* Tract */,")
    ln("\t\t\t);")
    ln("\t\t};")
    ln("/* End PBXProject section */")
    ln()

    # ── PBXResourcesBuildPhase ─────────────────────────────────────────────
    ln("/* Begin PBXResourcesBuildPhase section */")
    ln(f"\t\t{RESOURCES_PHASE} /* Resources */ = {{")
    ln("\t\t\tisa = PBXResourcesBuildPhase;")
    ln("\t\t\tbuildActionMask = 2147483647;")
    ln("\t\t\tfiles = (")
    ln(f"\t\t\t\t{ASSETS_BUILD_REF} /* Assets.xcassets in Resources */,")
    ln("\t\t\t);")
    ln("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    ln("\t\t};")
    ln("/* End PBXResourcesBuildPhase section */")
    ln()

    # ── PBXSourcesBuildPhase ───────────────────────────────────────────────
    ln("/* Begin PBXSourcesBuildPhase section */")
    ln(f"\t\t{SOURCES_PHASE} /* Sources */ = {{")
    ln("\t\t\tisa = PBXSourcesBuildPhase;")
    ln("\t\t\tbuildActionMask = 2147483647;")
    ln("\t\t\tfiles = (")
    for f in SOURCE_FILES:
        name = os.path.basename(f)
        ln(f"\t\t\t\t{build_refs[f]} /* {name} in Sources */,")
    ln(f"\t\t\t\t{COREDATA_BUILD_REF} /* Persistence.xcdatamodeld in Sources */,")
    ln("\t\t\t);")
    ln("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    ln("\t\t};")
    ln("/* End PBXSourcesBuildPhase section */")
    ln()

    # ── XCVersionGroup (Core Data model) ──────────────────────────────────
    ln("/* Begin XCVersionGroup section */")
    ln(f"\t\t{COREDATA_VERSION_GROUP} /* Persistence.xcdatamodeld */ = {{")
    ln("\t\t\tisa = XCVersionGroup;")
    ln("\t\t\tchildren = (")
    ln(f"\t\t\t\t{COREDATA_MODEL_REF} /* Persistence.xcdatamodel */,")
    ln("\t\t\t);")
    ln(f"\t\t\tcurrentVersion = {COREDATA_MODEL_REF} /* Persistence.xcdatamodel */;")
    ln("\t\t\tpath = Persistence.xcdatamodeld;")
    ln('\t\t\tsourceTree = "<group>";')
    ln("\t\t\tversionGroupType = wrapper.xcdatamodel;")
    ln("\t\t};")
    ln("/* End XCVersionGroup section */")
    ln()

    # ── XCBuildConfiguration ───────────────────────────────────────────────
    ln("/* Begin XCBuildConfiguration section */")

    def write_project_debug():
        ln(f"\t\t{DEBUG_CONFIG_PROJECT} /* Debug */ = {{")
        ln("\t\t\tisa = XCBuildConfiguration;")
        ln("\t\t\tbuildSettings = {")
        ln("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
        ln('\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";')
        ln("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
        ln("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
        ln("\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;")
        ln("\t\t\t\tCLANG_WARN_COMMA = YES;")
        ln("\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;")
        ln("\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;")
        ln("\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;")
        ln("\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;")
        ln("\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;")
        ln("\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;")
        ln("\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;")
        ln("\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;")
        ln("\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;")
        ln("\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;")
        ln("\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;")
        ln("\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;")
        ln("\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_DECL = YES;")
        ln("\t\t\t\tCOPY_PHASE_STRIP = NO;")
        ln("\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;")
        ln("\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
        ln("\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
        ln("\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;")
        ln("\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;")
        ln("\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
        ln("\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
        ln("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;")
        ln("\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
        ln("\t\t\t\tSDKROOT = iphoneos;")
        ln('\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";')
        ln("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
        ln('\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";')
        ln("\t\t\t\tSWIFT_VERSION = 6.2;")
        ln("\t\t\t\tTARGETED_DEVICE_FAMILY = 2;")
        ln("\t\t\t};")
        ln("\t\t\tname = Debug;")
        ln("\t\t};")

    def write_project_release():
        ln(f"\t\t{RELEASE_CONFIG_PROJECT} /* Release */ = {{")
        ln("\t\t\tisa = XCBuildConfiguration;")
        ln("\t\t\tbuildSettings = {")
        ln("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
        ln('\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";')
        ln("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
        ln("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
        ln("\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;")
        ln("\t\t\t\tCLANG_WARN_COMMA = YES;")
        ln("\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;")
        ln("\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;")
        ln("\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;")
        ln("\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;")
        ln("\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;")
        ln("\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;")
        ln("\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;")
        ln("\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;")
        ln("\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;")
        ln("\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;")
        ln("\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;")
        ln("\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;")
        ln("\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_DECL = YES;")
        ln("\t\t\t\tCOPY_PHASE_STRIP = NO;")
        ln("\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;")
        ln("\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;")
        ln("\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;")
        ln("\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;")
        ln("\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;")
        ln("\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;")
        ln("\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;")
        ln("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;")
        ln("\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;")
        ln("\t\t\t\tSDKROOT = iphoneos;")
        ln('\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";')
        ln('\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "";')
        ln('\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";')
        ln("\t\t\t\tSWIFT_VERSION = 6.2;")
        ln("\t\t\t\tTARGETED_DEVICE_FAMILY = 2;")
        ln("\t\t\t};")
        ln("\t\t\tname = Release;")
        ln("\t\t};")

    def write_target_config(config_id: str, name: str):
        ln(f"\t\t{config_id} /* {name} */ = {{")
        ln("\t\t\tisa = XCBuildConfiguration;")
        ln("\t\t\tbuildSettings = {")
        ln("\t\t\t\tASETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
        ln("\t\t\t\tASETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
        # Simulator builds sign ad-hoc (no team needed). Device builds use Automatic.
        ln('\t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphonesimulator*]" = "-";')
        ln("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
        ln("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
        ln("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
        ln("\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;")
        ln("\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;")
        ln("\t\t\t\tINFOPLIST_KEY_UIRequiresFullScreen = YES;")
        ln('\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown";')
        ln("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;")
        ln("\t\t\t\tMARKETING_VERSION = 1.0;")
        ln('\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.spline.app";')
        ln('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
        ln("\t\t\t\tSDKROOT = iphoneos;")
        ln("\t\t\t\tSUPPORTS_MACCATALYST = NO;")
        ln("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
        ln("\t\t\t\tSWIFT_VERSION = 6.2;")
        ln("\t\t\t\tTARGETED_DEVICE_FAMILY = 2;")
        ln("\t\t\t};")
        ln(f"\t\t\tname = {name};")
        ln("\t\t};")

    write_project_debug()
    write_project_release()
    write_target_config(DEBUG_CONFIG_TARGET, "Debug")
    write_target_config(RELEASE_CONFIG_TARGET, "Release")

    ln("/* End XCBuildConfiguration section */")
    ln()

    # ── XCConfigurationList ────────────────────────────────────────────────
    ln("/* Begin XCConfigurationList section */")

    ln(f"\t\t{BUILD_CONFIG_LIST_PROJECT}"
       f" /* Build configuration list for PBXProject \"Tract\" */ = {{")
    ln("\t\t\tisa = XCConfigurationList;")
    ln("\t\t\tbuildConfigurations = (")
    ln(f"\t\t\t\t{DEBUG_CONFIG_PROJECT} /* Debug */,")
    ln(f"\t\t\t\t{RELEASE_CONFIG_PROJECT} /* Release */,")
    ln("\t\t\t);")
    ln("\t\t\tdefaultConfigurationIsVisible = 0;")
    ln("\t\t\tdefaultConfigurationName = Release;")
    ln("\t\t};")

    ln(f"\t\t{BUILD_CONFIG_LIST_TARGET}"
       f" /* Build configuration list for PBXNativeTarget \"Tract\" */ = {{")
    ln("\t\t\tisa = XCConfigurationList;")
    ln("\t\t\tbuildConfigurations = (")
    ln(f"\t\t\t\t{DEBUG_CONFIG_TARGET} /* Debug */,")
    ln(f"\t\t\t\t{RELEASE_CONFIG_TARGET} /* Release */,")
    ln("\t\t\t);")
    ln("\t\t\tdefaultConfigurationIsVisible = 0;")
    ln("\t\t\tdefaultConfigurationName = Release;")
    ln("\t\t};")

    ln("/* End XCConfigurationList section */")
    ln()

    # Close objects dict and root
    ln("\t};")
    ln(f"\trootObject = {PROJECT_ID} /* Project object */;")
    ln("}")

    return "\n".join(lines)


if __name__ == "__main__":
    out_dir = os.path.join(BASE, "Tract.xcodeproj")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "project.pbxproj")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(pbxproj())
    print(f"Written: {out_path}")
