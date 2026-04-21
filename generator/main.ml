open Jingoo
open Jg_types
open Lua_api

type site_config = { name : string; subtitle : string; base_url : string }

type item = {
  slug : string;
  title : string;
  date : string;
  html_fragment : string;
  languages : string list;
  url : string;
}

type collection_config = {
  name : string;
  dir : string;
  template : string;
  permalink : string;
  item_var : string;
  sort_by : string;
  sort_order : string;
}

type page_config = { output : string; template : string }

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

let extract_directive content key =
  let prefix = "#+" ^ String.uppercase_ascii key ^ ":" in
  let prefix_len = String.length prefix in
  let lines = String.split_on_char '\n' content in
  let rec find = function
    | [] -> None
    | line :: rest ->
        let trimmed = String.trim line in
        if
          String.length trimmed >= prefix_len
          && String.uppercase_ascii (String.sub trimmed 0 prefix_len) = prefix
        then
          Some
            (String.trim
               (String.sub trimmed prefix_len
                  (String.length trimmed - prefix_len)))
        else find rest
  in
  find lines

let is_image_url url =
  let exts = [ ".png"; ".jpg"; ".jpeg"; ".gif"; ".svg"; ".webp"; ".bmp" ] in
  let lower = String.lowercase_ascii url in
  List.exists (fun ext -> Filename.check_suffix lower ext) exts

let strip_file_prefix url =
  let prefix = "file:" in
  let plen = String.length prefix in
  if String.length url >= plen && String.sub url 0 plen = prefix then
    String.sub url plen (String.length url - plen)
  else url

let render_org content =
  let doc = Orgcaml.Parser.parse content in
  let html = Orgcaml.Html.render_document doc in
  html

let fix_image_links html =
  let a_prefix = "<a href=\"" in
  let aplen = String.length a_prefix in
  let buf = Buffer.create (String.length html) in
  let hlen = String.length html in
  let rec go i =
    if i >= hlen then ()
    else if i + aplen <= hlen && String.sub html i aplen = a_prefix then
      let start = i + aplen in
      match String.index_from_opt html start '"' with
      | None ->
          Buffer.add_char buf html.[i];
          go (i + 1)
      | Some end_pos ->
          let url = String.sub html start (end_pos - start) in
          let clean_url = strip_file_prefix url in
          if is_image_url clean_url then (
            let close_a = "</a>" in
            match
              let search_from = end_pos + 1 in
              let rec find_close j =
                if j + String.length close_a > hlen then None
                else if String.sub html j (String.length close_a) = close_a then
                  Some (j + String.length close_a)
                else find_close (j + 1)
              in
              find_close search_from
            with
            | Some after_close ->
                Buffer.add_string buf
                  (Printf.sprintf "<img src=\"%s\" alt=\"%s\" />" clean_url
                     (Filename.basename clean_url));
                go after_close
            | None ->
                Buffer.add_char buf html.[i];
                go (i + 1))
          else (
            Buffer.add_string buf a_prefix;
            Buffer.add_string buf clean_url;
            go (i + aplen + String.length url))
    else (
      Buffer.add_char buf html.[i];
      go (i + 1))
  in
  go 0;
  Buffer.contents buf

let extract_languages html =
  let prefix = "class=\"language-" in
  let plen = String.length prefix in
  let hlen = String.length html in
  let rec find acc i =
    if i + plen >= hlen then List.rev acc
    else
      match String.index_from_opt html i 'c' with
      | None -> List.rev acc
      | Some pos ->
          if pos + plen <= hlen && String.sub html pos plen = prefix then
            let start = pos + plen in
            match String.index_from_opt html start '"' with
            | None -> List.rev acc
            | Some end_pos ->
                let lang = String.sub html start (end_pos - start) in
                let acc = if List.mem lang acc then acc else lang :: acc in
                find acc (end_pos + 1)
          else find acc (pos + 1)
  in
  find [] 0

let day_of_week y m d =
  let t = [| 0; 3; 2; 5; 0; 3; 5; 1; 4; 6; 2; 4 |] in
  let y = if m < 3 then y - 1 else y in
  (y + (y / 4) - (y / 100) + (y / 400) + t.(m - 1) + d) mod 7

let month_abbr =
  [|
    "";
    "Jan";
    "Feb";
    "Mar";
    "Apr";
    "May";
    "Jun";
    "Jul";
    "Aug";
    "Sep";
    "Oct";
    "Nov";
    "Dec";
  |]

let day_abbr = [| "Sun"; "Mon"; "Tue"; "Wed"; "Thu"; "Fri"; "Sat" |]

let rfc822_of_date date_str =
  match String.split_on_char '-' date_str with
  | [ y; m; d ] ->
      let yi = int_of_string y
      and mi = int_of_string m
      and di = int_of_string d in
      Printf.sprintf "%s, %02d %s %04d 00:00:00 +0000"
        day_abbr.(day_of_week yi mi di)
        di month_abbr.(mi) yi
  | _ -> date_str

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

let model_of_item item =
  Tobj
    [
      ("slug", Tstr item.slug);
      ("title", Tstr item.title);
      ("date", Tstr item.date);
      ("body", Tsafe item.html_fragment);
      ("languages", Tlist (List.map (fun l -> Tstr l) item.languages));
      ("title_escaped", Tsafe (xml_escape item.title));
      ("rfc822_date", Tstr (rfc822_of_date item.date));
      ("body_cdata", Tsafe (cdata_wrap item.html_fragment));
      ("url", Tstr item.url);
    ]

let site_model (config : site_config) =
  Tobj
    [
      ("name", Tstr config.name);
      ("subtitle", Tstr config.subtitle);
      ("base_url", Tstr config.base_url);
    ]

let expand_permalink permalink item_slug =
  let buf = Buffer.create (String.length permalink) in
  let len = String.length permalink in
  let rec go i =
    if i >= len then ()
    else if i + 5 <= len && String.sub permalink i 5 = ":slug" then (
      Buffer.add_string buf item_slug;
      go (i + 5))
    else (
      Buffer.add_char buf permalink.[i];
      go (i + 1))
  in
  go 0;
  Buffer.contents buf

(* Lua helpers *)

let get_string_field ls idx field =
  Lua.getfield ls idx field;
  let v = Lua.tostring ls (-1) in
  Lua.pop ls 1;
  v

let get_string_field_default ls idx field default =
  match get_string_field ls idx field with Some v -> v | None -> default

let read_site_config ls =
  Lua.getglobal ls "site";
  let name = get_string_field_default ls (-1) "name" "" in
  let subtitle = get_string_field_default ls (-1) "subtitle" "" in
  let base_url = get_string_field_default ls (-1) "base_url" "" in
  Lua.pop ls 1;
  { name; subtitle; base_url }

let read_collections ls =
  Lua.getglobal ls "collections";
  let colls = ref [] in
  Lua.pushnil ls;
  while Lua.next ls (-2) <> 0 do
    let coll_name = Lua.tostring ls (-2) |> Option.value ~default:"" in
    let dir = get_string_field_default ls (-1) "dir" "" in
    let template = get_string_field_default ls (-1) "template" "" in
    let permalink = get_string_field_default ls (-1) "permalink" "/:slug" in
    let item_var = get_string_field_default ls (-1) "item_var" "item" in
    let sort_by = get_string_field_default ls (-1) "sort_by" "date" in
    let sort_order = get_string_field_default ls (-1) "sort_order" "desc" in
    colls :=
      {
        name = coll_name;
        dir;
        template;
        permalink;
        item_var;
        sort_by;
        sort_order;
      }
      :: !colls;
    Lua.pop ls 1
  done;
  Lua.pop ls 1;
  List.rev !colls

let read_pages ls =
  Lua.getglobal ls "pages";
  let n = Lua.objlen ls (-1) in
  let pages = ref [] in
  for i = 1 to n do
    Lua.rawgeti ls (-1) i;
    let output = get_string_field_default ls (-1) "output" "" in
    let template = get_string_field_default ls (-1) "template" "" in
    pages := { output; template } :: !pages;
    Lua.pop ls 1
  done;
  Lua.pop ls 1;
  List.rev !pages

let process_collection base_dir (coll : collection_config) =
  let content_dir = Filename.concat base_dir coll.dir in
  let files = Sys.readdir content_dir |> Array.to_list in
  let org_files =
    files
    |> List.filter (fun f -> Filename.check_suffix f ".org")
    |> List.sort String.compare
  in
  let items =
    List.map
      (fun filename ->
        let slug = Filename.chop_suffix filename ".org" in
        let filepath = Filename.concat content_dir filename in
        let content = read_file filepath in
        let title =
          Option.value ~default:slug (extract_directive content "TITLE")
        in
        let date =
          Option.value ~default:"" (extract_directive content "DATE")
        in
        let html_fragment = render_org content |> fix_image_links in
        let languages = extract_languages html_fragment in
        let url = expand_permalink coll.permalink slug in
        { slug; title; date; html_fragment; languages; url })
      org_files
  in
  let items =
    let cmp a b =
      match coll.sort_by with
      | "date" ->
          if coll.sort_order = "asc" then String.compare a.date b.date
          else String.compare b.date a.date
      | _ ->
          if coll.sort_order = "asc" then String.compare a.date b.date
          else String.compare b.date a.date
    in
    List.sort cmp items
  in
  items

let () =
  let argc = Array.length Sys.argv in
  if argc < 3 then (
    Printf.eprintf "Usage: %s <site.lua> <output-dir>\n" Sys.argv.(0);
    exit 1);
  let lua_path = Sys.argv.(1) in
  let output_dir = Sys.argv.(2) in
  let base_dir = Filename.dirname lua_path in

  (* Load and execute site.lua *)
  let ls = LuaL.newstate () in
  LuaL.openlibs ls;
  (match LuaL.loadfile ls lua_path with
  | Lua.LUA_OK -> (
      match Lua.pcall ls 0 0 0 with
      | Lua.LUA_OK -> ()
      | _ -> failwith (Option.value ~default:"lua error" (Lua.tostring ls (-1)))
      )
  | _ -> failwith "could not load site.lua");

  (* Read configuration from Lua state *)
  let (config : site_config) = read_site_config ls in
  let templates_dir =
    Lua.getglobal ls "templates_dir";
    let v = Lua.tostring ls (-1) |> Option.value ~default:"templates" in
    Lua.pop ls 1;
    Filename.concat base_dir v
  in
  let static_dir =
    Lua.getglobal ls "static_dir";
    let v = Lua.tostring ls (-1) |> Option.value ~default:"static" in
    Lua.pop ls 1;
    Filename.concat base_dir v
  in
  let collections = read_collections ls in
  let pages = read_pages ls in

  (* Set up output *)
  clean_dir output_dir;
  copy_recursive static_dir output_dir;

  let env =
    { std_env with template_dirs = [ templates_dir ]; autoescape = false }
  in

  (* Process all collections *)
  let collection_data =
    List.map
      (fun coll ->
        let items = process_collection base_dir coll in
        (coll, items))
      collections
  in

  (* Build collection models for templates *)
  let collection_models =
    List.map
      (fun (coll, items) -> (coll.name, Tlist (List.map model_of_item items)))
      collection_data
  in

  (* Render collection items *)
  List.iter
    (fun ((coll : collection_config), items) ->
      let item_tmpl = Jg_template.Loaded.from_file ~env coll.template in
      List.iter
        (fun item ->
          let url_path = item.url in
          let item_dir =
            Filename.concat output_dir
              (String.sub url_path 1 (String.length url_path - 1))
          in
          mkdir_p item_dir;
          let models =
            [
              (coll.item_var, model_of_item item);
              ("site", site_model config);
              ("site_name", Tstr config.name);
            ]
            @ collection_models
          in
          let html = Jg_template.Loaded.eval item_tmpl ~models in
          write_file (Filename.concat item_dir "index.html") html)
        items)
    collection_data;

  (* Render pages *)
  List.iter
    (fun page ->
      let page_tmpl = Jg_template.Loaded.from_file ~env page.template in
      let models =
        [
          ("site", site_model config);
          ("site_name", Tstr config.name);
          ("base_url", Tstr config.base_url);
        ]
        @ collection_models
      in
      let html = Jg_template.Loaded.eval page_tmpl ~models in
      let out_path = Filename.concat output_dir page.output in
      mkdir_p (Filename.dirname out_path);
      write_file out_path html)
    pages;

  (* Copy imgs subdirectories from each collection's content dir *)
  List.iter
    (fun ((coll : collection_config), _items) ->
      let imgs_src =
        Filename.concat (Filename.concat base_dir coll.dir) "imgs"
      in
      if Sys.file_exists imgs_src && Sys.is_directory imgs_src then
        copy_recursive imgs_src (Filename.concat output_dir "imgs"))
    collection_data;

  let total_items =
    List.fold_left
      (fun acc (_coll, items) -> acc + List.length items)
      0 collection_data
  in
  Printf.printf "Built %d items across %d collections\n" total_items
    (List.length collections)
