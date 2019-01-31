open Tc
open Types

let entryID : string = "entry-box"

let leftButton : int = 0

let initialVPos : vPos = {vx = 475; vy = 200}

let centerPos : pos = {x = 475; y = 200}

let origin : pos = {x = 0; y = 0}

let moveSize : int = 50

let pageHeight : int = 400

let pageWidth : int = 500

let defaultEditor : serializableEditor =
  { clipboard = None
  ; timersEnabled = true
  ; cursorState = Deselected
  ; lockedHandlers = []
  ; routingTableOpenDetails = StrSet.empty }


let defaultSyncState : syncState = {inFlight = false; ticks = 0}

let defaultUrlState : urlState = {lastPos = {x = 0; y = 0}}

let defaultCanvas : canvasProps =
  { offset =
      origin (* These is intended to be (Viewport.toCentedOn centerPos) *)
  ; fnOffset = origin
  ; enablePan = true }


let defaultModel : model =
  { error = {message = None; showDetails = false}
  ; lastMsg = Initialization
  ; lastMod = NoChange (* this is awkward, but avoids circular deps *)
  ; complete =
      { functions = []
      ; admin = false
      ; completions = []
      ; invalidCompletions = []
      ; allCompletions = []
      ; index = -1
      ; value = ""
      ; prevValue = ""
      ; target = None
      ; matcher = (fun _ -> true)
      ; isCommandMode = false
      ; visible = true }
  ; userFunctions = []
  ; deletedUserFunctions = []
  ; builtInFunctions = []
  ; currentPage = Toplevels {x = 0; y = 0}
  ; hovering = []
  ; tests = []
  ; toplevels = []
  ; deletedToplevels = []
  ; analyses = StrDict.empty
  ; traces = StrDict.empty
  ; unfetchedTraces = StrDict.empty
  ; f404s = []
  ; unlockedDBs = []
  ; integrationTestState = NoIntegrationTest
  ; visibility = Native.PageVisibility.Visible (* partially saved in editor *)
  ; syncState = defaultSyncState
  ; urlState = defaultUrlState
  ; timersEnabled = true (* saved in editor *)
  ; clipboard = None
  ; cursorState = Deselected
  ; executingFunctions = []
  ; tlCursors = StrDict.empty
  ; featureFlags = StrDict.empty
  ; lockedHandlers = []
  ; canvas = defaultCanvas
  ; canvasName = "builtwithdark"
  ; userContentHost = "builtwithdark.com"
  ; environment = "none"
  ; csrfToken = "UNSET_CSRF"
  ; latest404 =
      Js.Date.now ()
      |> ( +. ) (1000.0 (* ms *) *. 60.0 *. 60.0 *. 24.0 *. -7.0)
      |> Js.Date.fromFloat
      |> Js.Date.toISOString
  ; routingTableOpenDetails = StrSet.empty }