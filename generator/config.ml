open Lua_api
open Types

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
