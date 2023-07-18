import ./asset_loading, ./asset_cache

const debugResCache = false

type AssetLoader* = ref object
    totalSize : int
    loadedSize: int
    itemsToLoad: int
    itemsLoaded: int
    onComplete*: proc() {.gcsafe.}
    onProgress*: proc(p: float) {.gcsafe.}
    assetCache*: AssetCache # Cache to put the loaded resources to. If nil, default cache is used.
    when debugResCache:
        assetsToLoad: seq[string]

proc newAssetLoader*(): AssetLoader {.inline.} =
    result.new()

proc onAssetLoaded(ld: AssetLoader, path: string) =
    inc ld.itemsLoaded
    when debugResCache:
        ld.assetsToLoad.keepIf(proc(a: string):bool = a != path)
        echo "REMAINING ITEMS: ", ld.assetsToLoad
    if ld.itemsToLoad == ld.itemsLoaded:
        ld.onComplete()
    if not ld.onProgress.isNil:
        ld.onProgress( ld.itemsLoaded.float / ld.itemsToLoad.float)

proc startLoadingAsset(ld: AssetLoader, path: string) =
    let url = "res://" & path
    loadAsset(url, path, ld.assetCache) do():
        ld.onAssetLoaded(path)

proc loadAssets*(ld: AssetLoader, resourceNames: openarray[string]) =
    ld.itemsToLoad += resourceNames.len
    if ld.assetCache.isNil:
        ld.assetCache = newAssetCache()
    when debugResCache:
        ld.assetsToLoad = @resourceNames
    for i in resourceNames:
        ld.startLoadingAsset(i)
