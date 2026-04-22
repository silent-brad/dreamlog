open Lua_api
open Types

let get_string_field ls idx field =
  Lua.getfield ls idx field;
  let v = Lua.tostring ls (-1) in
  Lua.pop ls 1;
  v

let get_string_field_default ls idx field default =
  match get_string_field ls idx field with Some v -> v | None -> default

let read_string_list ls idx =
  let n = Lua.objlen ls idx in
  let items = ref [] in
  for i = 1 to n do
    Lua.rawgeti ls idx i;
    let s = Lua.tostring ls (-1) |> Option.value ~default:"" in
    Lua.pop ls 1;
    items := s :: !items
  done;
  List.rev !items

let rec read_lua_value ls idx =
  let abs_idx = if idx > 0 then idx else Lua.gettop ls + 1 + idx in
  match Lua.type_ ls abs_idx with
  | Lua.LUA_TTABLE -> read_lua_table ls abs_idx
  | Lua.LUA_TBOOLEAN -> VBool (Lua.toboolean ls abs_idx)
  | Lua.LUA_TNUMBER -> VNum (Lua.tonumber ls abs_idx)
  | _ -> VStr (Lua.tostring ls abs_idx |> Option.value ~default:"")

and read_lua_table ls abs_idx =
  let n = Lua.objlen ls abs_idx in
  if n > 0 then begin
    let items = ref [] in
    for i = n downto 1 do
      Lua.rawgeti ls abs_idx i;
      let v = read_lua_value ls (-1) in
      Lua.pop ls 1;
      items := v :: !items
    done;
    VList !items
  end
  else begin
    let entries = ref [] in
    Lua.pushnil ls;
    while Lua.next ls abs_idx <> 0 do
      let key = Lua.tostring ls (-2) |> Option.value ~default:"" in
      let value = read_lua_value ls (-1) in
      entries := (key, value) :: !entries;
      Lua.pop ls 1
    done;
    VObj (List.rev !entries)
  end

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
    let args =
      Lua.getfield ls (-1) "args";
      let a =
        match Lua.type_ ls (-1) with
        | Lua.LUA_TTABLE -> (
            match read_lua_value ls (-1) with
            | VObj entries -> entries
            | _ -> [])
        | _ -> []
      in
      Lua.pop ls 1;
      a
    in
    let collections =
      Lua.getfield ls (-1) "collections";
      let c =
        match Lua.type_ ls (-1) with
        | Lua.LUA_TTABLE -> read_string_list ls (-1)
        | _ -> []
      in
      Lua.pop ls 1;
      c
    in
    pages := { output; template; args; collections } :: !pages;
    Lua.pop ls 1
  done;
  Lua.pop ls 1;
  List.rev !pages

let read_tag_pages ls =
  Lua.getglobal ls "tag_pages";
  match Lua.type_ ls (-1) with
  | Lua.LUA_TTABLE ->
      let template = get_string_field_default ls (-1) "template" "" in
      let permalink =
        get_string_field_default ls (-1) "permalink" "/tags/:tag"
      in
      Lua.pop ls 1;
      Some { template; permalink }
  | _ ->
      Lua.pop ls 1;
      None
