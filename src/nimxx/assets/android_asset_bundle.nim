import ./abstract_asset_bundle
import ./android_asset_url_handler # Required to register the android_asset handler

type AndroidAssetBundle* = ref object of AssetBundle

proc `=destroy`*(x: typeof AndroidAssetBundle()[]) =
  `=destroy`((typeof AssetBundle()[])(x))

# method forEachAsset*(ab: AssetBundle, action: proc(path: string): bool) =
#     raise newException()

proc newAndroidAssetBundle*(): AndroidAssetBundle =
  result.new()

method urlForPath*(ab: AndroidAssetBundle, path: string): string =
  return "android_asset://" & path
