let parse content = Orgcaml.Parser.parse content

let get_property doc key =
  List.assoc_opt (String.uppercase_ascii key) doc.Orgcaml.Ast.properties

let render doc = Orgcaml.Html.render_document doc
let languages doc = Orgcaml.Parser.languages doc

let parse_tags doc =
  match get_property doc "TAGS" with
  | None -> []
  | Some tags_str ->
      let sep = if String.contains tags_str ',' then ',' else ' ' in
      String.split_on_char sep tags_str
      |> List.map String.trim
      |> List.filter (fun s -> s <> "")
