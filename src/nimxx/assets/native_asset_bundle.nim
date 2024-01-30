import std/os
import ./abstract_asset_bundle

import pkg/malebolgia/lockers

var nativeAssetBasePath = initLocker(getAppDir())

proc setNativeAssetBasePath*(basePath: string) =
    lock nativeAssetBasePath as nabp:
        nabp = basePath

type NativeAssetBundle* = ref object of AssetBundle
    mBaseUrl: string

proc newNativeAssetBundle*(): NativeAssetBundle =
    result.new()
    lock nativeAssetBasePath as nabp:
        when defined(ios):
            result.mBaseUrl = "file://" & nabp
        elif defined(macosx):
            result.mBaseUrl = "file://" & nabp & "/../Resources"
        else:
            result.mBaseUrl = "file://" & nabp & "/res"

method urlForPath*(ab: NativeAssetBundle, path: string): string =
    return ab.mBaseUrl & "/" & path
