import std/tables
import pkg/variant

type AssetCache* = TableRef[string, Variant]

template newAssetCache*(): AssetCache = newTable[string, Variant]()

template registerAsset*(ac: AssetCache, path: string, asset: typed) =
  ac[path] = newVariant(asset)
