type site_config = { name : string; subtitle : string; base_url : string }

type lua_value =
  | VStr of string
  | VNum of float
  | VBool of bool
  | VList of lua_value list
  | VObj of (string * lua_value) list

type item = {
  slug : string;
  title : string;
  date : string;
  html_fragment : string;
  languages : string list;
  tags : string list;
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

type page_config = {
  output : string;
  template : string;
  args : (string * lua_value) list;
  collections : string list;
}

type tag_pages_config = { template : string; permalink : string }
