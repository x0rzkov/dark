open Core_kernel
open Libcommon
open Libexecution
open Util
open Types
open Types.RuntimeT

let secrets_in_canvas (canvas_id : Uuidm.t) : secret list =
  Db.fetch
    ~name:"all secrets by canvas"
    "SELECT secret_name, secret_value FROM secrets WHERE canvas_id=$1"
    ~params:[Uuid canvas_id]
  |> List.map ~f:(function
         | [secret_name; secret_value] ->
             {secret_name; secret_value}
         | _ ->
             Exception.internal "Bad DB format for secrets")