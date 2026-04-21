open Jingoo
open Jg_types

type post = {
  slug : string;
  title : string;
  date : string;
  html_fragment : string;
  languages : string list;
}

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
                else if
                  String.sub html j (String.length close_a) = close_a
                then Some (j + String.length close_a)
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

let model_of_post p =
  Tobj
    [
      ("slug", Tstr p.slug);
      ("title", Tstr p.title);
      ("date", Tstr p.date);
      ("body", Tsafe p.html_fragment);
      ("languages", Tlist (List.map (fun l -> Tstr l) p.languages));
      ("title_escaped", Tsafe (xml_escape p.title));
      ("rfc822_date", Tstr (rfc822_of_date p.date));
      ("body_cdata", Tsafe (cdata_wrap p.html_fragment));
    ]

let () =
  let argc = Array.length Sys.argv in
  if argc < 5 then (
    Printf.eprintf
      "Usage: %s <content-dir> <output-dir> <template-dir> <static-dir> \
       [base-url]\n"
      Sys.argv.(0);
    exit 1);
  let content_dir = Sys.argv.(1) in
  let output_dir = Sys.argv.(2) in
  let template_dir = Sys.argv.(3) in
  let static_dir = Sys.argv.(4) in
  let base_url = if argc > 5 then Sys.argv.(5) else "" in
  let site_name = "MirageOS Blog" in

  clean_dir output_dir;

  copy_recursive static_dir output_dir;

  let env =
    { std_env with template_dirs = [ template_dir ]; autoescape = false }
  in

  let post_tmpl = Jg_template.Loaded.from_file ~env "post.html" in
  let index_tmpl = Jg_template.Loaded.from_file ~env "index.html" in
  let rss_tmpl = Jg_template.Loaded.from_file ~env "rss.xml" in
  let not_found_tmpl = Jg_template.Loaded.from_file ~env "404.html" in

  let files = Sys.readdir content_dir |> Array.to_list in
  let org_files =
    files
    |> List.filter (fun f -> Filename.check_suffix f ".org")
    |> List.sort String.compare
  in
  let posts =
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
        { slug; title; date; html_fragment; languages })
      org_files
  in
  let posts = List.sort (fun a b -> String.compare b.date a.date) posts in

  List.iter
    (fun p ->
      let post_dir = Filename.concat output_dir p.slug in
      Unix.mkdir post_dir 0o755;
      let html =
        Jg_template.Loaded.eval post_tmpl
          ~models:[ ("post", model_of_post p); ("site_name", Tstr site_name) ]
      in
      write_file (Filename.concat post_dir "index.html") html)
    posts;

  let post_models = Tlist (List.map model_of_post posts) in

  let index_html =
    Jg_template.Loaded.eval index_tmpl
      ~models:[ ("posts", post_models); ("site_name", Tstr site_name) ]
  in
  write_file (Filename.concat output_dir "index.html") index_html;

  let rss_xml =
    Jg_template.Loaded.eval rss_tmpl
      ~models:
        [
          ("posts", post_models);
          ("site_name", Tstr site_name);
          ("base_url", Tstr base_url);
        ]
  in
  write_file (Filename.concat output_dir "rss.xml") rss_xml;

  let not_found_html =
    Jg_template.Loaded.eval not_found_tmpl
      ~models:[ ("site_name", Tstr site_name) ]
  in
  write_file (Filename.concat output_dir "404.html") not_found_html;

  let imgs_src = Filename.concat content_dir "imgs" in
  if Sys.file_exists imgs_src && Sys.is_directory imgs_src then
    copy_recursive imgs_src (Filename.concat output_dir "imgs");

  Printf.printf "Built %d posts\n" (List.length posts)
