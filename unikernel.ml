open Lwt.Infix

module type HTTP = Cohttp_mirage.Server.S

module Main (FS : Mirage_kv.RO) (Http : HTTP) = struct
  let rec dispatcher fs uri =
    match Uri.path uri with
    | "" | "/" -> dispatcher fs (Uri.with_path uri "index.html")
    | path -> (
        let mime = Magic_mime.lookup path in
        let headers = Cohttp.Header.init_with "content-type" mime in
        FS.get fs (Mirage_kv.Key.v path) >>= function
        | Error _ -> Http.respond_not_found ()
        | Ok body -> Http.respond_string ~status:`OK ~headers ~body ())

  let start fs http =
    let callback _conn req _body =
      let uri = Cohttp.Request.uri req in
      Logs.info (fun f -> f "request %s" (Uri.to_string uri));
      dispatcher fs uri
    in
    let spec = Http.make ~callback () in
    http (`TCP 8080) spec
end
