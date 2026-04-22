open Jingoo
open Jg_types
open Lua_api
open Types

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
        let content = Util.read_file filepath in
        let title =
          Option.value ~default:slug (Content.extract_directive content "TITLE")
        in
        let date =
          Option.value ~default:"" (Content.extract_directive content "DATE")
        in
        let html_fragment =
          Content.render_org content |> Content.fix_image_links
        in
        let languages = Content.extract_languages html_fragment in
        let tags = Content.parse_tags content in
        let url = Template.expand_permalink coll.permalink slug in
        { slug; title; date; html_fragment; languages; tags; url })
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

let run lua_path output_dir =
  let base_dir = Filename.dirname lua_path in

  let ls = LuaL.newstate () in
  LuaL.openlibs ls;
  (match LuaL.loadfile ls lua_path with
  | Lua.LUA_OK -> (
      match Lua.pcall ls 0 0 0 with
      | Lua.LUA_OK -> ()
      | _ -> failwith (Option.value ~default:"lua error" (Lua.tostring ls (-1)))
      )
  | _ -> failwith "could not load lua config");

  let (config : site_config) = Config.read_site_config ls in
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
  let collections = Config.read_collections ls in
  let pages = Config.read_pages ls in
  let tag_pages_config = Config.read_tag_pages ls in

  let tag_url =
    match tag_pages_config with
    | Some tc -> fun tag -> Template.expand_tag_permalink tc.permalink tag
    | None -> fun _ -> ""
  in

  Util.clean_dir output_dir;
  Util.copy_recursive static_dir output_dir;

  let env =
    { std_env with template_dirs = [ templates_dir ]; autoescape = false }
  in

  let collection_data =
    List.map
      (fun coll ->
        let items = process_collection base_dir coll in
        (coll, items))
      collections
  in

  let all_tags =
    let tag_items = Hashtbl.create 16 in
    List.iter
      (fun ((_coll : collection_config), items) ->
        List.iter
          (fun (item : item) ->
            List.iter
              (fun tag ->
                let existing =
                  try Hashtbl.find tag_items tag with Not_found -> []
                in
                Hashtbl.replace tag_items tag (item :: existing))
              item.tags)
          items)
      collection_data;
    Hashtbl.fold
      (fun tag items acc -> (tag, List.rev items) :: acc)
      tag_items []
    |> List.sort (fun (a, _) (b, _) -> String.compare a b)
  in

  let tags_model =
    ( "tags",
      Tlist
        (List.map
           (fun (tag, items) ->
             Tobj
               [
                 ("name", Tstr tag);
                 ("url", Tstr (tag_url tag));
                 ("count", Tint (List.length items));
               ])
           all_tags) )
  in

  let collection_models =
    List.map
      (fun (coll, items) ->
        (coll.name, Tlist (List.map (Template.model_of_item ~tag_url) items)))
      collection_data
  in

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
          Util.mkdir_p item_dir;
          let models =
            [
              (coll.item_var, Template.model_of_item ~tag_url item);
              ("site", Template.site_model config);
              ("site_name", Tstr config.name);
              tags_model;
            ]
            @ collection_models
          in
          let html = Jg_template.Loaded.eval item_tmpl ~models in
          Util.write_file (Filename.concat item_dir "index.html") html)
        items)
    collection_data;

  List.iter
    (fun (page : page_config) ->
      let page_tmpl = Jg_template.Loaded.from_file ~env page.template in
      let page_items =
        if page.collections <> [] then
          let items =
            List.concat_map
              (fun ((coll : collection_config), items) ->
                if List.mem coll.name page.collections then items else [])
              collection_data
          in
          let sorted =
            List.sort
              (fun (a : item) (b : item) -> String.compare b.date a.date)
              items
          in
          [
            ("items", Tlist (List.map (Template.model_of_item ~tag_url) sorted));
          ]
        else []
      in
      let page_args =
        List.map (fun (k, v) -> (k, Template.lua_value_to_tvalue v)) page.args
      in
      let models =
        [
          ("site", Template.site_model config);
          ("site_name", Tstr config.name);
          ("base_url", Tstr config.base_url);
          tags_model;
        ]
        @ collection_models @ page_items @ page_args
      in
      let html = Jg_template.Loaded.eval page_tmpl ~models in
      let out_path = Filename.concat output_dir page.output in
      Util.mkdir_p (Filename.dirname out_path);
      Util.write_file out_path html)
    pages;

  (match tag_pages_config with
  | Some tc ->
      let tag_tmpl = Jg_template.Loaded.from_file ~env tc.template in
      List.iter
        (fun (tag, items) ->
          let url = Template.expand_tag_permalink tc.permalink tag in
          let tag_dir =
            Filename.concat output_dir
              (String.sub url 1 (String.length url - 1))
          in
          Util.mkdir_p tag_dir;
          let models =
            [
              ("tag", Tstr tag);
              ("items", Tlist (List.map (Template.model_of_item ~tag_url) items));
              ("site", Template.site_model config);
              ("site_name", Tstr config.name);
              tags_model;
            ]
            @ collection_models
          in
          let html = Jg_template.Loaded.eval tag_tmpl ~models in
          Util.write_file (Filename.concat tag_dir "index.html") html)
        all_tags
  | None -> ());

  List.iter
    (fun ((coll : collection_config), _items) ->
      let imgs_src =
        Filename.concat (Filename.concat base_dir coll.dir) "imgs"
      in
      if Sys.file_exists imgs_src && Sys.is_directory imgs_src then
        Util.copy_recursive imgs_src (Filename.concat output_dir "imgs"))
    collection_data;

  let total_items =
    List.fold_left
      (fun acc (_coll, items) -> acc + List.length items)
      0 collection_data
  in
  Printf.printf "Built %d items across %d collections, %d tags\n" total_items
    (List.length collections) (List.length all_tags)
