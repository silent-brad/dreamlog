let read_file path = In_channel.with_open_bin path In_channel.input_all

let write_file path contents =
  Out_channel.with_open_bin path (fun oc ->
      Out_channel.output_string oc contents)

let xml_escape s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (function
      | '&' -> Buffer.add_string buf "&amp;"
      | '<' -> Buffer.add_string buf "&lt;"
      | '>' -> Buffer.add_string buf "&gt;"
      | '"' -> Buffer.add_string buf "&quot;"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

let cdata_wrap s =
  let buf = Buffer.create (String.length s) in
  let len = String.length s in
  let rec go i =
    if i >= len then ()
    else if i + 2 < len && s.[i] = ']' && s.[i + 1] = ']' && s.[i + 2] = '>'
    then (
      Buffer.add_string buf "]]]]><![CDATA[>";
      go (i + 3))
    else (
      Buffer.add_char buf s.[i];
      go (i + 1))
  in
  go 0;
  "<![CDATA[" ^ Buffer.contents buf ^ "]]>"

let rec rm_rf path =
  if Sys.is_directory path then (
    let entries = Sys.readdir path |> Array.to_list in
    List.iter (fun entry -> rm_rf (Filename.concat path entry)) entries;
    Unix.rmdir path)
  else Sys.remove path

let clean_dir dir =
  if Sys.file_exists dir then
    let entries = Sys.readdir dir |> Array.to_list in
    List.iter (fun entry -> rm_rf (Filename.concat dir entry)) entries
  else Unix.mkdir dir 0o755

let rec copy_recursive src dst =
  if Sys.is_directory src then (
    if not (Sys.file_exists dst) then Unix.mkdir dst 0o755;
    let entries = Sys.readdir src |> Array.to_list in
    List.iter
      (fun entry ->
        copy_recursive (Filename.concat src entry) (Filename.concat dst entry))
      entries)
  else write_file dst (read_file src)

let rec mkdir_p dir =
  if not (Sys.file_exists dir) then (
    mkdir_p (Filename.dirname dir);
    Unix.mkdir dir 0o755)
