open Tc
open Types

(* Dark *)
module P = Pointer
module RT = Runtime
module TL = Toplevel

(* ---------------------------- *)
(* Focus *)
(* ---------------------------- *)
(* show the prev 5 *)
(* obvi this should use getClientBoundingBox, but that's tough in Elm *)
let height (i : int) : int = if i < 4 then 0 else 14 * (i - 4)

let focusItem (i : int) : msg Tea.Cmd.t =
  Tea_task.attempt
    (fun x -> FocusAutocompleteItem x)
    (Tea_task.nativeBinding (fun _ ->
         let open Webapi.Dom in
         match Document.getElementById "autocomplete-holder" document with
         | Some el ->
             Element.setScrollTop el (i |> height |> float_of_int)
         | None ->
             () ))


(* ---------------------------- *)
(* display *)
(* ---------------------------- *)
let asName (aci : autocompleteItem) : string =
  match aci with
  | ACFunction {fnName} ->
      fnName
  | ACField name ->
      name
  | ACVariable name ->
      name
  | ACCommand command ->
      ":" ^ command.commandName
  | ACLiteral lit ->
      lit
  | ACOmniAction ac ->
    ( match ac with
    | NewDB maybeName ->
      ( match maybeName with
      | Some name ->
          "New DB named " ^ name
      | None ->
          "New DB" )
    | NewHandler maybeName ->
      ( match maybeName with
      | Some name ->
          "New event handler named " ^ name
      | None ->
          "New event handler" )
    | NewFunction maybeName ->
      ( match maybeName with
      | Some name ->
          "New function named " ^ name
      | None ->
          "New function" )
    | NewHTTPHandler maybeName ->
      ( match maybeName with
      | Some name ->
          "New HTTP handler named " ^ name
      | None ->
          "New HTTP handler" )
    | NewEventSpace name ->
        "New handler in the " ^ name ^ " space" )
  | ACConstructorName name ->
      let arityOneConstructors = ["Just"; "Ok"; "Error"] in
      if List.member ~value:name arityOneConstructors
      then name ^ " ______"
      else name
  | ACKeyword k ->
    ( match k with
    | KLet ->
        "let"
    | KIf ->
        "if"
    | KLambda ->
        "lambda"
    | KMatch ->
        "match" )
  | ACHTTPModifier name ->
      name
  | ACCronTiming timing ->
      timing
  | ACEventSpace space ->
      space
  | ACDBColType tipe ->
      tipe
  | ACParamTipe tipe ->
      tipe
  | ACExtra _ ->
      ""


let asTypeString (item : autocompleteItem) : string =
  match item with
  | ACFunction f ->
      f.fnParameters
      |> List.map ~f:(fun x -> x.paramTipe)
      |> List.map ~f:RT.tipe2str
      |> String.join ~sep:", "
      |> fun s -> "(" ^ s ^ ") ->  " ^ RT.tipe2str f.fnReturnTipe
  | ACField _ ->
      "field"
  | ACVariable _ ->
      "variable"
  | ACCommand _ ->
      ""
  | ACConstructorName _ ->
      "option"
  | ACLiteral lit ->
      let tipe =
        lit
        |> Decoders.parseDvalLiteral
        |> Option.withDefault ~default:DIncomplete
        |> RT.typeOf
        |> RT.tipe2str
      in
      tipe ^ " literal"
  | ACOmniAction _ ->
      ""
  | ACKeyword _ ->
      "keyword"
  | ACHTTPModifier _ ->
      "method"
  | ACCronTiming _ ->
      "interval"
  | ACEventSpace _ ->
      "event space"
  | ACDBColType _ ->
      "type"
  | ACParamTipe _ ->
      "param type"
  | ACExtra _ ->
      ""


let asString (aci : autocompleteItem) : string = asName aci ^ asTypeString aci

(* ---------------------------- *)
(* External: utils *)
(* ---------------------------- *)
let findFunction (a : autocomplete) (name : string) : function_ option =
  List.find ~f:(fun f -> f.fnName = name) a.functions


let isStringEntry (a : autocomplete) : bool =
  String.startsWith ~prefix:"\"" a.value


let isLargeStringEntry (a : autocomplete) : bool =
  isStringEntry a && String.contains ~substring:"\n" a.value


let isSmallStringEntry (a : autocomplete) : bool =
  isStringEntry a && not (isLargeStringEntry a)


let highlighted (a : autocomplete) : autocompleteItem option =
  List.getAt ~index:a.index (a.completions @ a.invalidCompletions)


let getValue (a : autocomplete) : string =
  match highlighted a with Some item -> asName item | None -> a.value


let rec sharedPrefix2 (l : string) (r : string) : string =
  match (String.uncons l, String.uncons r) with
  | Some (l1, lrest), Some (r1, rrest) ->
      if l1 = r1 then String.fromChar l1 ^ sharedPrefix2 lrest rrest else ""
  | _ ->
      ""


let sharedPrefixList (strs : string list) : string =
  match List.head strs with
  | None ->
      ""
  | Some s ->
      List.foldl ~f:sharedPrefix2 ~init:s strs


(* Find the shared prefix of all the possible suggestions (eg "List::") *)
let sharedPrefix (a : autocomplete) : string =
  a.completions |> List.map ~f:asName |> sharedPrefixList


let rec containsOrdered (needle : string) (haystack : string) : bool =
  match String.uncons needle with
  | Some (c, newneedle) ->
      let char = String.fromChar c in
      String.contains ~substring:char haystack
      && containsOrdered
           newneedle
           ( haystack
           |> String.split ~on:char
           |> List.drop ~count:1
           |> String.join ~sep:char )
  | None ->
      true


(* returns (indent, suggestion, search), where: *)
(* - indent is the string that occurs before the match *)
(* - suggestion is the match rewritten with the search *)
(* - search is the search rewritten to match the suggestion *)
(* Returns no suggestion or indent for an OmniAction *)
let compareSuggestionWithActual (a : autocomplete) (actual : string) :
    string * string * string =
  match highlighted a with
  | Some (ACOmniAction _) ->
      ("", "", actual)
  | _ ->
      let suggestion = sharedPrefix a in
      ( match
          Js.String.indexOf (String.toLower actual) (String.toLower suggestion)
        with
      | -1 ->
          ("", suggestion, actual)
      | index ->
          let prefix = String.slice ~from:0 ~to_:index suggestion in
          let suffix =
            String.slice
              ~from:(index + String.length actual)
              ~to_:(String.length suggestion)
              suggestion
          in
          (prefix, prefix ^ actual ^ suffix, actual) )


let nonAdminFunctions (fns : function_ list) : function_ list = fns

let dvalFields (dv : dval) : string list =
  match dv with DObj dict -> StrDict.keys dict | _ -> []


let findCompatibleThreadParam ({fnParameters} : function_) (tipe : tipe) :
    parameter option =
  fnParameters
  |> List.head
  |> Option.andThen ~f:(fun fst ->
         if RT.isCompatible fst.paramTipe tipe then Some fst else None )


let findParamByType ({fnParameters} : function_) (tipe : tipe) :
    parameter option =
  fnParameters |> List.find ~f:(fun p -> RT.isCompatible p.paramTipe tipe)


let dvalForTarget (m : model) ((tlid, pd) : target) : dval option =
  TL.get m tlid
  |> Option.andThen ~f:TL.asHandler
  |> Option.map ~f:(fun x -> x.ast)
  |> Option.andThen ~f:(AST.getValueParent pd)
  |> Option.map ~f:P.toID
  |> Option.andThen ~f:(Analysis.getCurrentLiveValue m tlid)
  (* don't filter on incomplete values *)
  |> Option.andThen ~f:(fun dv_ -> if dv_ = DIncomplete then None else Some dv_)


let isThreadMember (m : model) ((tlid, pd) : target) =
  TL.get m tlid
  |> Option.andThen ~f:TL.asHandler
  |> Option.map ~f:(fun x -> x.ast)
  |> Option.andThen ~f:(AST.findParentOfWithin_ (P.toID pd))
  |> Option.map ~f:(fun e ->
         match e with F (_, Thread _) -> true | _ -> false )
  |> Option.withDefault ~default:false


let paramTipeForTarget (m : model) ((tlid, pd) : target) : tipe option =
  TL.get m tlid
  |> Option.andThen ~f:TL.asHandler
  |> Option.map ~f:(fun x -> x.ast)
  |> Option.andThen ~f:(fun ast -> AST.getParamIndex ast (P.toID pd))
  |> Option.andThen ~f:(fun (name, index) ->
         m.complete.functions
         |> List.find ~f:(fun f -> name = f.fnName)
         |> Option.map ~f:(fun x -> x.fnParameters)
         |> Option.andThen ~f:(List.getAt ~index)
         |> Option.map ~f:(fun x -> x.paramTipe) )


let matchesTypes (isThreadMember : bool) (paramTipe : tipe) (dv : dval option)
    : function_ -> bool =
 fun fn ->
  let matchesReturnType = RT.isCompatible fn.fnReturnTipe paramTipe in
  let matchesParamType =
    match dv with
    | Some dval ->
        if isThreadMember
        then None <> findCompatibleThreadParam fn (RT.typeOf dval)
        else None <> findParamByType fn (RT.typeOf dval)
    | None ->
        true
  in
  matchesReturnType && matchesParamType


(* ------------------------------------ *)
(* Dynamic Items *)
(* ------------------------------------ *)

let qLiteral (s : string) : autocompleteItem option =
  if Decoders.isLiteralString s
  then Some (ACLiteral s)
  else if String.length s > 0
  then
    if String.startsWith ~prefix:(String.toLower s) "false"
    then Some (ACLiteral "false")
    else if String.startsWith ~prefix:(String.toLower s) "true"
    then Some (ACLiteral "true")
    else if String.startsWith ~prefix:(String.toLower s) "null"
    then Some (ACLiteral "null")
    else None
  else None


(* ------------------------------------ *)
(* Validators *)
(* ------------------------------------ *)

(*
  urls
  From https://www.w3.org/Addressing/URL/5_URI_BNF.html
  path = void | xpalphas [ / path ]
  xalpha = alpha | digit | safe | extra | escape
  xalphas = xalpha [ xalphas ]
  xpalpha = xalpha | +
  xpalphas = xpalpha [ xpalpha ]
  alpha = [a-zA-Z]
  digit = [0-9]
  safe = $ | - | _ | @ | . | &
  extra = ! | * | <doublequote> | ' | ( | ) | ,
  reserved = = | ; | / | # | ? | : | space
  escape = % hex hex
*)
(* let urlPathSafeCharacters = "[-a-zA-Z0-9$_@.&!*\"'(),%/]" *)
(* let nonUrlPathSafeCharacters = "[^-a-zA-Z0-9$_@.&!*\"'(),%/]" *)
(* let urlPathValidator = "[-a-zA-Z0-9$_@.&!*\"'(),%/]+" *)

(* allow : for parameter names. TODO: do better job parsing here *)
let eventNameSafeCharacters = "[-a-zA-Z0-9$_@.&!*\"'(),%/:]"

let nonEventNameSafeCharacters = "[^-a-zA-Z0-9$_@.&!*\"'(),%/:]"

let httpNameValidator = "/[-a-zA-Z0-9$_@.&!*\"'(),%/:]*"

let eventNameValidator = "[-a-zA-Z0-9$_@.&!*\"'(),%/:]+"

let varnameValidator = "[a-z_][a-zA-Z0-9_]*"

let varnamePatternValidator = varnameValidator

let constructorPatternValidator = "[A-Z_][a-zA-Z0-9_]*"

let constructorNameValidator = "Just|Nothing|Ok|Error"

let dbColTypeValidator = "\\[?[A-Z]\\w+\\]?"

let dbColNameValidator = "\\w+"

let dbNameValidator = "[A-Z][a-zA-Z0-9_]*"

let eventModifierValidator = "[a-zA-Z_][\\sa-zA-Z0-9_]*"

let httpVerbValidator = "[A-Z]+"

let eventSpaceValidator = "[A-Z0-9_]+"

let fieldNameValidator = ".+"

let keynameValidator = ".+"

let fnNameValidator = "[a-z][a-zA-Z0-9_]*"

let paramTypeValidator = "[A-Z][a-z]*"

let assertValid pattern value : string =
  if Util.reExactly pattern value
  then value
  else Debug.crash ("Failed validator: " ^ pattern ^ ", " ^ value)


(* ------------------------------------ *)
(* Omniactions *)
(* ------------------------------------ *)

let rec stripCharsFromFront (disallowed : string) (s : string) : string =
  match String.uncons s with
  | None ->
      s
  | Some (c, rest) ->
      let needle = String.fromChar c in
      if Util.reContains ~re:disallowed needle
      then stripCharsFromFront disallowed rest
      else s


let stripChars (disallowed : string) (s : string) : string =
  Regex.replace disallowed "" s


let qNewDB (s : string) : omniAction option =
  let name =
    s
    |> stripChars "[^a-zA-Z0-9_]"
    |> stripCharsFromFront "[^a-zA-Z]"
    |> String.capitalize
  in
  if name = ""
  then Some (NewDB None)
  else
    let validName = assertValid dbNameValidator name in
    Some (NewDB (Some validName))


let qFunction (s : string) : omniAction =
  let name =
    s
    |> stripChars "[^a-zA-Z0-9_]"
    |> stripCharsFromFront "[^a-zA-Z]"
    |> String.uncapitalize
  in
  if name = ""
  then NewFunction None
  else NewFunction (Some (assertValid fnNameValidator name))


let qHandler (s : string) : omniAction =
  let name =
    s |> stripChars nonEventNameSafeCharacters |> String.uncapitalize
  in
  if name = ""
  then NewHandler None
  else NewHandler (Some (assertValid eventNameValidator name))


let qHTTPHandler (s : string) : omniAction =
  let name = s |> stripChars nonEventNameSafeCharacters in
  if name = ""
  then NewHTTPHandler None
  else if String.startsWith ~prefix:"/" name
  then NewHTTPHandler (Some (assertValid httpNameValidator name))
  else NewHTTPHandler (Some (assertValid httpNameValidator ("/" ^ name)))


let qEventSpace (s : string) : omniAction option =
  let name = s |> String.toUpper |> stripChars "[^A-Z0-9_]" in
  if name = ""
  then None
  else Some (NewEventSpace (assertValid eventSpaceValidator name))


let isDynamicItem (item : autocompleteItem) : bool =
  match item with ACLiteral _ -> true | ACOmniAction _ -> true | _ -> false


let isStaticItem (item : autocompleteItem) : bool = not (isDynamicItem item)

let toDynamicItems target (q : string) : autocompleteItem list =
  match target with
  | None ->
      (* omnicompletion *)
      let omnis =
        if q = ""
        then
          (qHTTPHandler q :: Option.values [qNewDB q])
          @ [qFunction q; qHandler q]
        else
          [qHTTPHandler q; qFunction q; qHandler q]
          @ Option.values [qNewDB q; qEventSpace q]
      in
      List.map ~f:(fun o -> ACOmniAction o) omnis
  | Some (_, PExpr _) ->
      Option.values [qLiteral q]
  | Some (_, PField _) ->
      [ACField q]
  | Some (_, PEventSpace _) ->
      if q == "" then [] else [ACEventSpace (String.toUpper q)]
  | _ ->
      []


let withDynamicItems
    (target : target option) (query : string) (acis : autocompleteItem list) :
    autocompleteItem list =
  let new_ = toDynamicItems target query in
  let withoutDynamic = List.filter ~f:isStaticItem acis in
  withoutDynamic @ new_


let paramFor (m : model) (tlid : tlid) (id : id) : parameter option =
  TL.get m tlid
  |> Option.andThen ~f:TL.asHandler
  |> Option.map ~f:(fun x -> x.ast)
  |> Option.andThen ~f:(fun ast -> AST.getParamIndex ast id)
  |> Option.andThen ~f:(fun (name, index) ->
         m.complete.functions
         |> List.find ~f:(fun f -> name = f.fnName)
         |> Option.map ~f:(fun x -> x.fnParameters)
         |> Option.andThen ~f:(List.getAt ~index) )


let paramForTarget (m : model) (a : autocomplete) : parameter option =
  match a.target with
  | None ->
      None
  | Some (tlid, p) ->
      paramFor m tlid (P.toID p)


(* ------------------------------------ *)
(* Create the list *)
(* ------------------------------------ *)
let generate (m : model) (a : autocomplete) : autocomplete =
  let space =
    a.target
    |> Option.map ~f:Tuple2.first
    |> Option.map ~f:(TL.getTL m)
    |> Option.andThen ~f:TL.spaceOf
  in
  let dval = Option.andThen ~f:(dvalForTarget m) a.target in
  let varnames = Analysis.currentVarnamesFor m a.target in
  let paramTipe =
    a.target
    |> Option.andThen ~f:(paramTipeForTarget m)
    |> Option.withDefault ~default:TAny
  in
  let isThreadMember =
    Option.map ~f:(isThreadMember m) a.target
    |> Option.withDefault ~default:false
  in
  let fields =
    match dval with
    | Some dv when RT.typeOf dv = TObj ->
      ( match a.target with
      | Some (_, pd) when P.typeOf pd = Field ->
          List.map ~f:(fun x -> ACField x) (dvalFields dv)
      | _ ->
          [] )
    | _ ->
        []
  in
  let isExpression =
    match a.target with Some (_, p) -> P.typeOf p = Expr | None -> false
  in
  (* functions *)
  let funcList = if isExpression then a.functions else [] in
  let functions = List.map ~f:(fun x -> ACFunction x) funcList in
  let extras =
    match a.target with
    | Some (_, p) ->
      ( match P.typeOf p with
      (* autocomplete HTTP verbs if the handler is in the HTTP event space *)
      | EventModifier ->
        ( match space with
        | Some HSHTTP ->
            [ ACHTTPModifier "GET"
            ; ACHTTPModifier "POST"
            ; ACHTTPModifier "PUT"
            ; ACHTTPModifier "DELETE"
            ; ACHTTPModifier "PATCH" ]
        | Some HSCron ->
            [ ACCronTiming "Daily"
            ; ACCronTiming "Weekly"
            ; ACCronTiming "Fortnightly"
            ; ACCronTiming "Every 1hr"
            ; ACCronTiming "Every 12hrs"
            ; ACCronTiming "Every 1min" ]
        | Some HSOther ->
            []
        | Some HSEmpty ->
            []
        | None ->
            [] )
      | EventSpace ->
          [ACEventSpace "HTTP"; ACEventSpace "CRON"]
      | DBColType ->
          let builtins =
            [ "String"
            ; "Int"
            ; "Boolean"
            ; "Float"
            ; "Title"
            ; "Url"
            ; "Date"
            ; "Password"
            ; "UUID" ]
          in
          let compound = List.map ~f:(fun s -> "[" ^ s ^ "]") builtins in
          List.map ~f:(fun x -> ACDBColType x) (builtins @ compound)
      | ParamTipe ->
          [ ACParamTipe "Any"
          ; ACParamTipe "String"
          ; ACParamTipe "Int"
          ; ACParamTipe "Boolean"
          ; ACParamTipe "Float"
          ; ACParamTipe "Date"
          ; ACParamTipe "Obj"
          ; ACParamTipe "Block"
          ; ACParamTipe "Char"
          ; ACParamTipe "List" ]
      | _ ->
          [] )
    | _ ->
        []
  in
  let exprs =
    if isExpression
    then
      let constructors =
        [ ACConstructorName "Just"
        ; ACConstructorName "Nothing"
        ; ACConstructorName "Ok"
        ; ACConstructorName "Error" ]
      in
      let varnames = List.map ~f:(fun x -> ACVariable x) varnames in
      let keywords =
        List.map ~f:(fun x -> ACKeyword x) [KLet; KIf; KLambda; KMatch]
      in
      varnames @ constructors @ keywords @ functions
    else []
  in
  let regular = extras @ exprs @ fields in
  let commands = List.map ~f:(fun x -> ACCommand x) Commands.commands in
  let items = if a.isCommandMode then commands else regular in
  let matcher = function
    | ACFunction fn ->
        matchesTypes isThreadMember paramTipe dval fn
    | _ ->
        true
  in
  {a with allCompletions = items; matcher}


let filter
    (matcher : autocompleteItem -> bool)
    (list : autocompleteItem list)
    (query : string) : autocompleteItem list * autocompleteItem list =
  let lcq = query |> String.toLower in
  let stringify i =
    (if 1 >= String.length lcq then asName i else asString i)
    |> Regex.replace {js|⟶|js} "->"
  in
  (* split into different lists *)
  let dynamic, candidates0 = List.partition ~f:isDynamicItem list in
  let candidates1, notSubstring =
    List.partition
      ~f:(stringify >> String.toLower >> String.contains ~substring:lcq)
      candidates0
  in
  let startsWith, candidates2 =
    List.partition
      ~f:(stringify >> String.startsWith ~prefix:query)
      candidates1
  in
  let startsWithCI, candidates3 =
    List.partition
      ~f:(stringify >> String.toLower >> String.startsWith ~prefix:lcq)
      candidates2
  in
  let substring, substringCI =
    List.partition
      ~f:(stringify >> String.contains ~substring:query)
      candidates3
  in
  let stringMatch =
    List.filter
      ~f:(asName >> String.toLower >> containsOrdered lcq)
      notSubstring
  in
  let allMatches =
    [dynamic; startsWith; startsWithCI; substring; substringCI; stringMatch]
    |> List.concat
  in
  (* Now split list by type validity *)
  List.partition ~f:matcher allMatches


let init (fns : function_ list) (isAdmin : bool) : autocomplete =
  let default = Defaults.defaultModel.complete in
  let functions = if isAdmin then fns else nonAdminFunctions fns in
  {default with functions; admin = isAdmin}


let refilter (query : string) (old : autocomplete) : autocomplete =
  (* add or replace the literal the user is typing to the completions *)
  let fudgedCompletions =
    withDynamicItems old.target query old.allCompletions
  in
  let newCompletions, invalidCompletions =
    filter old.matcher fudgedCompletions query
  in
  let oldHighlight = highlighted old in
  let allCompletions = newCompletions @ invalidCompletions in
  let newCount = List.length allCompletions in
  let oldHighlightNewPos =
    oldHighlight
    |> Option.andThen ~f:(fun oh -> List.elemIndex ~value:oh allCompletions)
  in
  let index =
    (* Clear the highlight conditions *)
    if query = ""
       (* when we had previously highlighted something due to any actual match *)
       && ( (old.index <> -1 && old.value <> query)
          (* or this condition previously held and nothing has changed *)
          || old.index = -1 )
    then -1
    else
      (* If an entry is highlighted, and you press another *)
      (* valid key for that entry, keep it highlighted *)
      match oldHighlightNewPos with
      | Some i ->
          i
      (* If an entry vanishes, highlight 0 *)
      | None ->
          (* if nothing matches, highlight nothing *)
          if newCount = 0
          then
            -1
            (* we matched something but its gone, go to top of *)
            (* list *)
          else 0
  in
  { old with
    index
  ; completions = newCompletions
  ; invalidCompletions
  ; value = query
  ; prevValue = old.value }


let regenerate (m : model) (a : autocomplete) : autocomplete =
  generate m a |> refilter a.value


(* ---------------------------- *)
(* Autocomplete state *)
(* ---------------------------- *)
let reset (m : model) (a : autocomplete) : autocomplete =
  let userFunctionMetadata =
    m.userFunctions
    |> List.map ~f:(fun x -> x.ufMetadata)
    |> List.filterMap ~f:Functions.ufmToF
  in
  let unusedDeprecatedFns = Refactor.unusedDeprecatedFunctions m in
  let functions =
    m.builtInFunctions
    |> List.filter ~f:(fun f ->
           not
             (List.member
                ~value:f.fnName
                (List.map ~f:(fun x -> x.fnName) userFunctionMetadata)) )
    |> List.filter ~f:(fun f ->
           not (StrSet.member ~value:f.fnName unusedDeprecatedFns) )
    |> List.append userFunctionMetadata
  in
  let result = init functions a.admin |> regenerate m in
  {result with visible = VariantTesting.defaultAutocompleteVisible m}


let numCompletions (a : autocomplete) : int =
  List.length a.completions + List.length a.invalidCompletions


let selectDown (a : autocomplete) : autocomplete =
  let max_ = numCompletions a in
  let max = max max_ 1 in
  let new_ = (a.index + 1) mod max in
  {a with index = new_}


let selectUp (a : autocomplete) : autocomplete =
  let max = numCompletions a - 1 in
  {a with index = (if a.index <= 0 then max else a.index - 1)}


(* Implementation: *)
(* n The autocomplete list should include: *)
(*    y all imported functions *)
(*    y restricted by types that are allowed *)
(*    y allowed field names *)
(*    n library names *)
(*    y case-insensitive *)
(* n order by most likely, offer other alternatives below *)
(*   n slight typos *)
(*   n slight typeos *)
(* y Press enter to select *)
(* y Press right to fill as much as is definitive *)
(*  *)
let setQuery (q : string) (a : autocomplete) : autocomplete = refilter q a

let appendQuery (str : string) (a : autocomplete) : autocomplete =
  let q =
    if isStringEntry a
    then String.dropRight ~count:1 a.value ^ str ^ "\""
    else a.value ^ str
  in
  setQuery q a


let documentationForItem (aci : autocompleteItem) : string option =
  match aci with
  | ACFunction f ->
      if String.length f.fnDescription <> 0
      then Some f.fnDescription
      else Some "function call with no description"
  | ACCommand c ->
      Some (c.doc ^ " (" ^ c.shortcut ^ ")")
  | ACConstructorName "Just" ->
      Some "An Option containing a value"
  | ACConstructorName "Nothing" ->
      Some "An Option representing Nothing"
  | ACConstructorName "Ok" ->
      Some "A successful Result containing a value"
  | ACConstructorName "Error" ->
      Some "A Result representing a failure"
  | ACConstructorName name ->
      Some ("TODO: this should never occur: the constructor " ^ name)
  | ACField fieldname ->
      Some ("The '" ^ fieldname ^ "' field of the object")
  | ACVariable var ->
      if String.isCapitalized var
      then Some ("The database '" ^ var ^ "'")
      else Some ("The variable '" ^ var ^ "'")
  | ACLiteral lit ->
      Some ("the literal value '" ^ lit ^ "'")
  | ACKeyword KLet ->
      Some "A `let` expression allows you assign a variable to an expression"
  | ACKeyword KIf ->
      Some "An `if` expression allows you to branch on a boolean condition"
  | ACKeyword KLambda ->
      Some
        "A `lambda` creates an anonymous function. This is most often used for iterating through lists"
  | ACKeyword KMatch ->
      Some
        "A `match` expression allows you to pattern match on a value, and return different expressions based on many possible conditions"
  | ACOmniAction _ ->
      None
  | ACHTTPModifier verb ->
      Some ("Make this handler match the " ^ verb ^ " HTTP verb")
  | ACCronTiming timing ->
      Some ("Request this handler to trigger " ^ timing)
  | ACEventSpace "HTTP" ->
      Some "This handler will respond to HTTP requests"
  | ACEventSpace "CRON" ->
      Some "This handler will periodically trigger"
  | ACEventSpace name ->
      Some ("This handler will respond when events are emitted to " ^ name)
  | ACDBColType tipe ->
      Some ("This field will be a " ^ tipe)
  | ACParamTipe tipe ->
      if String.startsWith ~prefix:"[" tipe
      then
        let name =
          tipe |> String.dropLeft ~count:1 |> String.dropRight ~count:1
        in
        Some ("This parameter will be a " ^ name ^ " list")
      else Some ("This parameter will be a " ^ tipe)
  | ACExtra _ ->
      None


let setTarget (m : model) (t : target option) (a : autocomplete) : autocomplete
    =
  {a with target = t} |> regenerate m


let setVisible (visible : bool) (a : autocomplete) : autocomplete =
  {a with visible}


(* ------------------------------------ *)
(* Commands *)
(* ------------------------------------ *)
let enableCommandMode (a : autocomplete) : autocomplete =
  {a with isCommandMode = true}


let update (m : model) (mod_ : autocompleteMod) (a : autocomplete) :
    autocomplete =
  match mod_ with
  | ACSetQuery str ->
      setQuery str a
  | ACAppendQuery str ->
      appendQuery str a
  | ACReset ->
      reset m a
  | ACSelectDown ->
      selectDown a
  | ACSelectUp ->
      selectUp a
  | ACSetTarget target ->
      setTarget m target a
  | ACRegenerate ->
      regenerate m a
  | ACEnableCommandMode ->
      enableCommandMode a
  | ACSetVisible visible ->
      setVisible visible a


(* --------------------------- *)
(* Modifications *)
(* --------------------------- *)
let selectSharedPrefix (ac : autocomplete) : modification =
  let sp = sharedPrefix ac in
  if sp = "" then NoChange else AutocompleteMod (ACSetQuery sp)