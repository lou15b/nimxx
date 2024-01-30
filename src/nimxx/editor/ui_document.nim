{.used.}
import std/json
import std/async

import ./editor_types
import ../ [ undo_manager, view, serializers, ui_resource ]

const savingAndLoadingEnabled* = not defined(ios) and not defined(android)

const ViewPboardKind* = "io.github.yglukhov.nimx"

#### Hacked out - we need to have our own file dialog
# when savingAndLoadingEnabled:
#     import pkg/os_files / dialog

proc newUIDocument*(e: Editor): UIDocument =
    result.new()
    result.undoManager = newUndoManager()
    result.view = new(View, e.workspace.bounds)
    result.view.autoResizingMask = {afFlexibleWidth, afFlexibleHeight}

proc defaultName*(ui: UIDocument, className: string): string =
    var index = 0
    var proposedName = className & "_"
    while proposedName & $index in ui.takenViewNames:
        inc index

    proposedName = proposedName & $index
    ui.takenViewNames.add(proposedName)
    return proposedName

proc serializeView*(ui: UIDocument): string =
    let s = newJsonSerializer()
    # pushParentResource(ui.path)
    s.serialize(ui.view)
    # popParentResource()
    return $s.jsonNode()

when savingAndLoadingEnabled:
    import ../assets/asset_loading

    #### Hacked out - we need to have our own file dialog
    # proc fileDialog(title: string, kind: DialogKind): string =
    #     var di: DialogInfo
    #     di.title = title
    #     di.kind = kind
    #     di.filters = @[(name:"Nimx UI", ext:"*.nimx")]
    #     di.extension = "nimx"
    #     di.show()

    proc save*(d: UIDocument) =
        if d.path.len == 0:
            #### Hacked out - we need to have our own file dialog
            discard
            # var di: DialogInfo
            # di.extension = "nimx"
            # di.kind = dkSaveFile
            # di.filters = @[(name:"Nimx", ext:"*.nimx")]
            # di.title = "Save document"
            # d.path = di.show()

        if d.path.len > 0:
            let s = newJsonSerializer()
            # pushParentResource(d.path)
            s.serialize(d.view)
            # popParentResource()
            writeFile(d.path, $s.jsonNode())

    proc saveAs*(d: UIDocument) =
        #### Hacked out - we need to have our own file dialog
        discard
        # var di: DialogInfo
        # di.extension = "nimx"
        # di.kind = dkSaveFile
        # di.filters = @[(name:"Nimx", ext:"*.nimx")]
        # di.title = "Save document as"

        # var path = di.show()
        # if path.len > 0:
        #     d.path = path
        #     d.save()


    proc loadViewToEditAsync(path: string): Future[View] =
        var r = newFuture[View]()
        loadAsset[JsonNode]("file://" & path) do(jn: JsonNode, err: string):
            r.complete(deserializeView(jn))
        result = r

    proc loadFromPath*(d: UIDocument, path: string) {.async.}=
        d.path = path
        if d.path.len > 0:
            let superview = d.view.superview
            d.view.removeFromSuperview()
            d.view = await loadViewToEditAsync(path)
            doAssert(not d.view.isNil)
            if not superview.isNil:

                block fillTakenViewNames:
                    d.takenViewNames.setLen(0)
                    d.takenViewNames.add(d.view.name)
                    var subviews = d.view.subviews
                    var nsubviews: seq[View]
                    while subviews.len > 0:
                        for s in subviews:
                            d.takenViewNames.add(s.name)
                            nsubviews.add(s.subviews)
                        subviews = nsubviews
                        nsubviews.setLen(0)

                superview.addSubview(d.view)

    proc open*(d: UIDocument) =
        #### Hacked out - we need to have our own file dialog
        discard
        # var di: DialogInfo
        # di.extension = "nimx"
        # di.kind = dkOpenFile
        # di.filters = @[(name:"Nimx", ext:"*.nimx")]
        # di.title = "Open document"

        # var path = di.show()
        # if path.len > 0:
        #     asyncCheck d.loadFromPath(path)
