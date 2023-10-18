import os, rlocks
import ./abstract_asset_bundle
import ../utils/lock_utils

var nativeAssetBasePathLock: RLock
nativeAssetBasePathLock.initRLock()
var nativeAssetBasePath {.guard: nativeAssetBasePathLock.} = getAppDir()

proc setNativeAssetBasePath*(basePath: string) =
    withRLockGCsafe(nativeAssetBasePathLock):
        nativeAssetBasePath = basePath

type NativeAssetBundle* = ref object of AssetBundle
    mBaseUrl: string

proc newNativeAssetBundle*(): NativeAssetBundle =
    result.new()
    withRLockGCsafe(nativeAssetBasePathLock):
        when defined(ios):
            result.mBaseUrl = "file://" & nativeAssetBasePath
        elif defined(macosx):
            result.mBaseUrl = "file://" & nativeAssetBasePath & "/../Resources"
        else:
            result.mBaseUrl = "file://" & nativeAssetBasePath & "/res"

method urlForPath*(ab: NativeAssetBundle, path: string): string =
    return ab.mBaseUrl & "/" & path
