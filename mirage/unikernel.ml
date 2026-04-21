open Lwt.Infix

module type HTTP = Cohttp_mirage.Server.S

module Main (FS : Mirage_kv.RO) (Http : HTTP) = struct
  let try_serve fs path =
    let mime = Magic_mime.lookup path in
    let headers = Cohttp.Header.init_with "content-type" mime in
    FS.get fs (Mirage_kv.Key.v path) >>= function
    | Ok body ->
        Lwt.return_some (Http.respond_string ~status:`OK ~headers ~body ())
    | Error _ -> Lwt.return_none

  let respond_not_found fs =
    let headers = Cohttp.Header.init_with "content-type" "text/html" in
    FS.get fs (Mirage_kv.Key.v "404.html") >>= function
    | Ok body -> Http.respond_string ~status:`Not_found ~headers ~body ()
    | Error _ -> Http.respond_not_found ()

  let rec dispatcher fs uri =
    match Uri.path uri with
    | "" | "/" -> dispatcher fs (Uri.with_path uri "/index.html")
    | path -> (
        try_serve fs path >>= function
        | Some resp -> resp
        | None -> (
            let index_path = path ^ "/index.html" in
            try_serve fs index_path >>= function
            | Some resp -> resp
            | None -> respond_not_found fs))

  let start fs http =
    let callback _conn req _body =
      let uri = Cohttp.Request.uri req in
      Logs.info (fun f -> f "request %s" (Uri.to_string uri));
      dispatcher fs uri
    in
    let spec = Http.make ~callback () in
    http (`TCP 8080) spec
end
