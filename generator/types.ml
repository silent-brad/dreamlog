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
