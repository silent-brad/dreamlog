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
