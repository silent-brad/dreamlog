open Mirage

let stack = generic_stackv4v6 default_network
let data = generic_kv_ro "../htdocs"
let http_srv = cohttp_server @@ conduit_direct ~tls:false stack

let main =
  let packages = [ package "uri"; package "magic-mime" ] in
  main ~packages "Unikernel.Main" (kv_ro @-> http @-> job)

let () = register "mirage-site" [ main $ data $ http_srv ]
