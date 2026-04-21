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
        let url = Template.expand_permalink coll.permalink slug in
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
  (* TODO: Remove this as this is internal *)
  if argc < 3 then (
    Printf.eprintf "Usage: %s <config.lua> <output-dir>\n" Sys.argv.(0);
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

  (* Set up output *)
  Util.clean_dir output_dir;
  Util.copy_recursive static_dir output_dir;

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
      (fun (coll, items) ->
        (coll.name, Tlist (List.map Template.model_of_item items)))
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
          Util.mkdir_p item_dir;
          let models =
            [
              (coll.item_var, Template.model_of_item item);
              ("site", Template.site_model config);
              ("site_name", Tstr config.name);
            ]
            @ collection_models
          in
          let html = Jg_template.Loaded.eval item_tmpl ~models in
          Util.write_file (Filename.concat item_dir "index.html") html)
        items)
    collection_data;

  (* Render pages *)
  List.iter
    (fun page ->
      let page_tmpl = Jg_template.Loaded.from_file ~env page.template in
      let models =
        [
          ("site", Template.site_model config);
          ("site_name", Tstr config.name);
          ("base_url", Tstr config.base_url);
        ]
        @ collection_models
      in
      let html = Jg_template.Loaded.eval page_tmpl ~models in
      let out_path = Filename.concat output_dir page.output in
      Util.mkdir_p (Filename.dirname out_path);
      Util.write_file out_path html)
    pages;

  (* Copy imgs subdirectories from each collection's content dir *)
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
  Printf.printf "Built %d items across %d collections\n" total_items
    (List.length collections)
